using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;
using Microsoft.Win32;
using KeyKeySettings;

// Actual pinned WinSparkle DLL, loopback HTTP and throwaway keys/registry only.
// Test callbacks consume the payload; no test can launch an installer or UAC.
internal static class NativeTests
{
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_check_update_with_ui_and_install();

    internal static void Run(string[] args)
    {
        var option = Array.IndexOf(args, "--openssl");
        var openssl = option >= 0 && option + 1 < args.Length ? args[option + 1] : "openssl";
        var directory = Path.Combine(Path.GetTempPath(), "KeyKeyUpdaterTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var payload = Encoding.UTF8.GetBytes("Inert KeyKey test payload. This is not an executable.");
            var package = Path.Combine(directory, "payload.exe");
            File.WriteAllBytes(package, payload);
            string Key(string name)
            {
                var pem = Path.Combine(directory, name + ".pem");
                RunOpenSsl(openssl, "genpkey", "-algorithm", "ED25519", "-out", pem);
                var der = Path.Combine(directory, name + ".der");
                RunOpenSsl(openssl, "pkey", "-in", pem, "-pubout", "-outform", "DER", "-out", der);
                return Convert.ToBase64String(File.ReadAllBytes(der).AsSpan(12, 32));
            }
            var key = Key("test");
            var wrongKey = Key("wrong");
            var signature = Path.Combine(directory, "signature.bin");
            RunOpenSsl(openssl, "pkeyutl", "-sign", "-rawin", "-inkey", Path.Combine(directory, "test.pem"),
                "-in", package, "-out", signature);
            var signed = Convert.ToBase64String(File.ReadAllBytes(signature));
            AutomaticPreferenceTest(key);
            NotificationOnlyTest(key, background: false);
            NotificationOnlyTest(key, background: true);
            foreach (var mode in new[] { "no-update", "empty-feed-x64", "empty-feed-x86", "valid", "beta-next", "beta-same", "beta-older", "beta-to-final", "tampered", "wrong-key", "missing-signature", "broken-feed" })
            {
                using var done = new ManualResetEventSlim();
                using var server = new LoopbackServer(mode, payload, signed);
                var registryPath = @"Software\chichi77\KeyKey\UpdaterTests\" + Guid.NewGuid().ToString("N");
                var backend = new WinSparkleBackend(registryPath);
                int errors = 0, found = 0, notFound = 0, installs = 0, shutdowns = 0;
                bool matchingPayload = false;
                try
                {
                    backend.Configure(mode == "wrong-key" ? wrongKey : key, server.Feed,
                        mode.StartsWith("beta-", StringComparison.Ordinal) ? "1.3.2b2" : "1.0.0",
                        new UpdateCallbacks(() => 1,
                            () => { Interlocked.Increment(ref shutdowns); done.Set(); },
                            () => { Interlocked.Increment(ref errors); done.Set(); },
                            () => Interlocked.Increment(ref found),
                            () => { Interlocked.Increment(ref notFound); done.Set(); },
                            () => { }, () => { }, path =>
                            {
                                matchingPayload = File.ReadAllBytes(path).SequenceEqual(payload);
                                Interlocked.Increment(ref installs);
                                return 1; // Handled by the test, NEVER fall through to ShellExecute.
                            }));
                    Program.Check(backend.Automatic, "Fresh updater did not default to weekly checks");
                    backend.Initialize();
                    win_sparkle_check_update_with_ui_and_install();
                    Program.Check(WaitWithDispatcher(() => done.IsSet, TimeSpan.FromSeconds(30)),
                        "Native updater timed out: " + mode);
                    if (mode is "valid" or "beta-next" or "beta-to-final")
                        Program.Check(found == 1 && installs == 1 && shutdowns == 1 && errors == 0 && matchingPayload,
                            "Valid signed payload did not reach the interception callback intact");
                    else if (mode is "no-update" or "beta-same" or "beta-older" || mode.StartsWith("empty-feed-", StringComparison.Ordinal))
                        Program.Check(notFound == 1 && errors == 0 && installs == 0 && shutdowns == 0,
                            "Native same-version or empty feed was not reported as no update");
                    else
                        Program.Check(errors == 1 && installs == 0 && shutdowns == 0,
                            "Invalid update reached installer handling: " + mode);
                    Console.WriteLine("Native WinSparkle passed: " + mode);
                }
                finally
                {
                    backend.Cleanup();
                    Registry.CurrentUser.DeleteSubKeyTree(registryPath, throwOnMissingSubKey: false);
                }
            }
            StalledQueryTest(key);
        }
        finally
        {
            // Exact randomly-created directory, no enumeration of outside paths.
            Directory.Delete(directory, recursive: true);
        }
    }

    private static void AutomaticPreferenceTest(string key)
    {
        foreach (var (saved, initialized) in new (bool?, bool)[] {
            (null, false), (false, false), (false, true), (true, false), (true, true) })
        {
            var registryPath = @"Software\chichi77\KeyKey\UpdaterTests\" + Guid.NewGuid().ToString("N");
            void Start(WinSparkleBackend backend)
            {
                backend.Configure(key, "https://example.invalid/feed.xml", "1.3.2",
                    new UpdateCallbacks(() => 0, () => { }, () => { }, () => { },
                        () => { }, () => { }, () => { }, _ => 1));
                backend.Initialize(); // Native scheduling stays disabled; no query is requested.
            }
            var backend = new WinSparkleBackend(registryPath);
            try
            {
                using (var preferences = Registry.CurrentUser.CreateSubKey(registryPath))
                {
                    if (saved.HasValue) preferences.SetValue("KeyKeyAutomaticChecks", saved.Value ? 1 : 0);
                    if (initialized) preferences.SetValue("ConsentInitialized", 1);
                }
                Start(backend);
                Program.Check(backend.Automatic == (saved ?? true), "Initialization changed the saved weekly-check choice");
                backend.Automatic = false;
                backend.Cleanup();
                backend = new WinSparkleBackend(registryPath);
                Start(backend);
                Program.Check(!backend.Automatic, "Saved weekly-check opt-out did not survive restart");
            }
            finally
            {
                backend.Cleanup();
                Registry.CurrentUser.DeleteSubKeyTree(registryPath, throwOnMissingSubKey: false);
            }
        }
        Console.WriteLine("Weekly checks default on; existing choices and opt-outs survive initialization/restart");
    }

    private static void NotificationOnlyTest(string key, bool background)
    {
        using var server = new LoopbackServer("valid", Array.Empty<byte>(), "");
        using var completed = new ManualResetEventSlim();
        var registryPath = @"Software\chichi77\KeyKey\UpdaterTests\" + Guid.NewGuid().ToString("N");
        var backend = new WinSparkleBackend(registryPath);
        int installs = 0, shutdowns = 0, errors = 0, found = 0, notFound = 0;
        try
        {
            backend.Configure(key, server.Feed, "1.0.0", new UpdateCallbacks(() => 1,
                () => Interlocked.Increment(ref shutdowns),
                () => { Interlocked.Increment(ref errors); completed.Set(); },
                () => { Interlocked.Increment(ref found); completed.Set(); },
                () => { Interlocked.Increment(ref notFound); completed.Set(); },
                () => { }, () => { }, _ =>
                {
                    Interlocked.Increment(ref installs);
                    return 1; // Never execute an installer, even if this regression fails.
                }));
            backend.Initialize();
            backend.Check(background);
            var notified = WaitWithDispatcher(() => completed.IsSet, TimeSpan.FromSeconds(30));
            Program.Check(notified && found == 1 && errors == 0 && notFound == 0,
                $"Native {(background ? "weekly" : "manual")} update notification failed " +
                $"({RuntimeInformation.ProcessArchitecture}): completed={notified}, found={found}, " +
                $"errors={errors}, notFound={notFound}, feedRequests={server.FeedRequests}, " +
                $"payloadRequests={server.PayloadRequests}");
            // Give an unintended prefetch time to reach the loopback server.
            WaitWithDispatcher(() => false, TimeSpan.FromMilliseconds(300));
            Program.Check(server.PayloadRequests == 0 && installs == 0 && shutdowns == 0 && errors == 0,
                "Checking for updates downloaded a package or started installation without user confirmation");
            Console.WriteLine($"Native WinSparkle {(background ? "weekly" : "manual")} notification did not prefetch or install");
        }
        finally
        {
            backend.Cleanup();
            Registry.CurrentUser.DeleteSubKeyTree(registryPath, throwOnMissingSubKey: false);
        }
    }

    private static bool WaitWithDispatcher(Func<bool> completed, TimeSpan timeout)
    {
        // These tests run on an STA, like Settings. Keep its message loop alive
        // while native UI/network workers and loopback continuations run.
        var elapsed = Stopwatch.StartNew();
        while (!completed() && elapsed.Elapsed < timeout)
        {
            var frame = new DispatcherFrame();
            Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,
                () => frame.Continue = false);
            Dispatcher.PushFrame(frame);
            Thread.Sleep(1);
        }
        return completed();
    }

    internal static void StalledQueryTest(string key)
    {
        using var server = new LoopbackServer("stalled", Array.Empty<byte>(), "");
        var registryPath = @"Software\chichi77\KeyKey\UpdaterTests\" + Guid.NewGuid().ToString("N");
        var configuration = JsonSerializer.Serialize(new { schema_version = 1, public_ed25519_key = key,
            windows_x64_feed_url = server.Feed, windows_x86_feed_url = server.Feed });
        using var updater = new DesktopUpdater(new WinSparkleBackend(registryPath), Dispatcher.CurrentDispatcher,
            () => throw new Exception("Stalled query requested shutdown"),
            () => new MemoryStream(Encoding.UTF8.GetBytes(configuration)),
            readBetaPreference: () => false, writeBetaPreference: _ => { });
        try
        {
            updater.Initialize();
            Program.Check(updater.Available, "Native stalled-query updater did not initialize");
            var elapsed = Stopwatch.StartNew();
            updater.Check(background: true);
            bool heartbeat = false;
            Dispatcher.CurrentDispatcher.BeginInvoke(() => heartbeat = true);
            while (elapsed.Elapsed < TimeSpan.FromSeconds(15) &&
                (!updater.Status.Contains("逾時") || !updater.Available))
            {
                var frame = new DispatcherFrame();
                Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, () => frame.Continue = false);
                Dispatcher.PushFrame(frame);
                Thread.Sleep(1);
            }
            Program.Check(heartbeat && elapsed.Elapsed >= TimeSpan.FromSeconds(9.5) &&
                updater.Status.Contains("逾時") && updater.Available && !updater.Busy,
                "Native stalled TLS query did not cancel in 10 seconds and restore manual retry");
            Console.WriteLine("Native WinSparkle stalled TLS query cancelled after 10 seconds without blocking WPF");
        }
        finally
        {
            updater.Dispose();
            Program.Check(updater.NativeCleanup.Wait(TimeSpan.FromSeconds(10)), "Native timeout cleanup did not finish");
            Registry.CurrentUser.DeleteSubKeyTree(registryPath, throwOnMissingSubKey: false);
        }
    }

    private static void RunOpenSsl(string openssl, params string[] arguments)
    {
        var info = new ProcessStartInfo(openssl) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        using var process = Process.Start(info) ?? throw new Exception("Unable to start OpenSSL");
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        Program.Check(process.WaitForExit(30000), "OpenSSL timed out");
        Program.Check(process.ExitCode == 0, "OpenSSL failed: " + error.GetAwaiter().GetResult());
        output.GetAwaiter().GetResult();
    }

    private sealed class LoopbackServer : IDisposable
    {
        private readonly TcpListener listener = new(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource stop = new();
        private readonly Task serving;
        private readonly string mode;
        private readonly byte[] payload;
        private readonly string signature;
        private int payloadRequests, feedRequests;
        internal int PayloadRequests => Volatile.Read(ref payloadRequests);
        internal int FeedRequests => Volatile.Read(ref feedRequests);
        public string Feed { get; }
        public LoopbackServer(string mode, byte[] payload, string signature)
        {
            this.mode = mode; this.payload = payload; this.signature = signature;
            listener.Start();
            Feed = $"{(mode == "stalled" ? "https" : "http")}://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/appcast.xml";
            // Keep server continuations off the WPF context, including
            // cancellation on dispose.
            serving = Task.Run(Serve);
        }
        private async Task Serve()
        {
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    using var client = await listener.AcceptTcpClientAsync(stop.Token);
                    if (mode == "stalled")
                    {
                        // Accept TCP but never answer the TLS handshake.
                        await Task.Delay(Timeout.Infinite, stop.Token);
                        continue;
                    }
                    using var stream = client.GetStream();
                    using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
                    var request = await reader.ReadLineAsync(stop.Token) ?? "";
                    while (await reader.ReadLineAsync(stop.Token) is { Length: > 0 }) { }
                    byte[] body;
                    if (request.Contains("/payload.exe"))
                    {
                        Interlocked.Increment(ref payloadRequests);
                        body = payload.ToArray();
                        if (mode == "tampered") body[0] ^= 1;
                    }
                    else
                    {
                        Interlocked.Increment(ref feedRequests);
                        var version = mode switch
                        {
                            "no-update" => "1.0.0", "beta-next" => "1.3.2b10", "beta-same" => "1.3.2b2",
                            "beta-older" => "1.3.2b1", "beta-to-final" => "1.3.2", _ => "2.0.0"
                        };
                        var sig = mode == "missing-signature" ? "" : $"sparkle:edSignature=\"{signature}\"";
                        var xml = $"<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>Test</title><item><title>Test {version}</title><enclosure url=\"{Feed.Replace("appcast.xml", "payload.exe")}\" sparkle:version=\"{version}\" length=\"{payload.Length}\" type=\"application/octet-stream\" {sig}/></item></channel></rss>";
                        if (mode.StartsWith("empty-feed-", StringComparison.Ordinal))
                            xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory,
                                mode == "empty-feed-x86" ? "windows-x86.xml" : "windows-x64.xml"));
                        body = Encoding.UTF8.GetBytes(mode == "broken-feed" ? "<broken>" : xml);
                    }
                    var header = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                    await stream.WriteAsync(header, stop.Token);
                    await stream.WriteAsync(body, stop.Token);
                }
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
            catch (SocketException) when (stop.IsCancellationRequested) { }
        }
        public void Dispose()
        {
            stop.Cancel(); listener.Stop();
            serving.GetAwaiter().GetResult(); stop.Dispose();
        }
    }
}
