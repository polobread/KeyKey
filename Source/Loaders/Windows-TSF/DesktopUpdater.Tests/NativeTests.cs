using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
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
                    Program.Check(!backend.Automatic, "Native updater did not default to off");
                    backend.Initialize();
                    win_sparkle_check_update_with_ui_and_install();
                    Program.Check(done.Wait(TimeSpan.FromSeconds(30)), "Native updater timed out: " + mode);
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
        }
        finally
        {
            // Exact randomly-created directory, no enumeration of outside paths.
            Directory.Delete(directory, recursive: true);
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
        public string Feed { get; }
        public LoopbackServer(string mode, byte[] payload, string signature)
        {
            this.mode = mode; this.payload = payload; this.signature = signature;
            listener.Start();
            Feed = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}/appcast.xml";
            serving = Serve();
        }
        private async Task Serve()
        {
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    using var client = await listener.AcceptTcpClientAsync(stop.Token);
                    using var stream = client.GetStream();
                    using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);
                    var request = await reader.ReadLineAsync(stop.Token) ?? "";
                    while (await reader.ReadLineAsync(stop.Token) is { Length: > 0 }) { }
                    byte[] body;
                    if (request.Contains("/payload.exe"))
                    {
                        body = payload.ToArray();
                        if (mode == "tampered") body[0] ^= 1;
                    }
                    else
                    {
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
