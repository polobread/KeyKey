using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows.Threading;
using KeyKeySettings;

internal static class Program
{
    internal static void Check(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,
            () => frame.Continue = false);
        Dispatcher.PushFrame(frame);
    }
    private static void Until(Func<bool> ready)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (!ready() && DateTime.UtcNow < deadline) { Pump(); Thread.Sleep(1); }
        Check(ready(), "Asynchronous updater operation did not finish");
    }
    private static void Finish(Task task) { Until(() => task.IsCompleted); task.GetAwaiter().GetResult(); }
    private static T Finish<T>(Task<T> task) { Finish((Task)task); return task.GetAwaiter().GetResult(); }
    private static string Config(string? key = null, string x64 = "https://example.invalid/x64.xml",
        string x86 = "https://example.invalid/x86.xml") => JsonSerializer.Serialize(new
        {
            schema_version = 1, public_ed25519_key = key ?? Convert.ToBase64String(new byte[32]),
            windows_x64_feed_url = x64, windows_x86_feed_url = x86
        });
    private sealed class FakeBackend : IDesktopUpdateBackend
    {
        public bool Automatic { get; set; }
        public DateTimeOffset LastAttempt { get; set; }
        public int Configures, Starts, Checks, Cleanups;
        public bool FailStart;
        public ManualResetEventSlim? CleanupGate;
        public string Feed = "", Version = "";
        public bool BetaChannel;
        public UpdateCallbacks Callbacks = null!;
        public void Configure(string key, string feed, string version, UpdateCallbacks callbacks, bool betaChannel = false)
        { Configures++; Feed = feed; Version = version; Callbacks = callbacks; BetaChannel = betaChannel; }
        public void Initialize() { Starts++; if (FailStart) throw new IOException("test initialization failure"); }
        public void Check(bool background = false) => Checks++;
        public void Cleanup() { Cleanups++; CleanupGate?.Wait(); Callbacks.Error(); Callbacks.Shutdown(); }
    }
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(Dispatcher.CurrentDispatcher));
            LifecycleTests();
            AutomaticScheduleTests();
            BetaChannelTests();
            ReinstallTests();
            TimeoutTests();
            if (args.Contains("--native")) NativeTests.Run(args);
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
    private static void AutomaticScheduleTests()
    {
        var backend = new FakeBackend { Automatic = true };
        using var updater = new DesktopUpdater(backend, Dispatcher.CurrentDispatcher, () => { },
            () => new MemoryStream(Encoding.UTF8.GetBytes(Config())),
            readBetaPreference: () => false, writeBetaPreference: _ => { });
        DispatcherTimer? Timer() => (DispatcherTimer?)typeof(DesktopUpdater)
            .GetField("automaticTimer", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!
            .GetValue(updater);
        updater.Initialize();
        Check(backend.Checks == 0 && Timer()!.Interval.TotalSeconds is > 590 and <= 600,
            "Startup did not defer the first check for ten minutes");
        backend.LastAttempt = DateTimeOffset.UtcNow.AddDays(-1);
        updater.SetAutomatic(true);
        Check(Timer()!.Interval > TimeSpan.FromDays(5.99),
            "A recent persisted attempt did not preserve the remaining weekly interval");
        backend.LastAttempt = DateTimeOffset.UtcNow.AddDays(-8);
        updater.SetAutomatic(true);
        Check(Timer()!.Interval.TotalSeconds is > 590 and <= 600,
            "An overdue client skipped the startup delay");
        updater.Check();
        Check(backend.Checks == 1 && Timer()!.Interval > TimeSpan.FromDays(6.99),
            "A manual attempt did not move the next deadline seven days ahead");
        backend.Callbacks.NotFound(); Pump();
        updater.SetAutomatic(false);
        Check(Timer() is null, "Opt-out left an automatic timer running");
    }
    private static void LifecycleTests()
    {
        int shutdowns = 0;
        DesktopUpdater Create(FakeBackend fake, string json) => new(fake, Dispatcher.CurrentDispatcher,
            () => shutdowns++, () => new MemoryStream(Encoding.UTF8.GetBytes(json)),
            readBetaPreference: () => false, writeBetaPreference: _ => { });
        foreach (var json in new[] { Config(key: ""), Config(x64: "", x86: ""), Config(key: "bad"),
            Config(key: Convert.ToBase64String(new byte[31])), Config(x64: "http://example.invalid/", x86: "http://example.invalid/"),
            Config(x64: "https://user:pass@example.invalid/", x86: "https://user:pass@example.invalid/"),
            Config(x64: "https://example.invalid/#x", x86: "https://example.invalid/#x"), "{}", "{",
            Config().Replace("\"schema_version\":1", "\"schema_version\":2") })
        {
            var invalid = new FakeBackend();
            using var updater = Create(invalid, json);
            updater.Initialize(); updater.Check(); updater.SetAutomatic(true);
            Check(!updater.Available && invalid.Configures == 0 && invalid.Checks == 0 && !invalid.Automatic,
                "Disabled/invalid config reached the native SDK");
        }
        var backend = new FakeBackend();
        var product = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version!;
        var baseVersion = $"{product.Major}.{product.Minor}.{product.Build}";
        string BetaConfig(string version, string channel) => Config().TrimEnd('}') +
            $",\"release_version\":\"{version}\",\"update_channel\":\"{channel}\"}}";
        foreach (var beta in new[] { 1, 2, 10 })
        {
            var fake = new FakeBackend();
            using var client = Create(fake, BetaConfig(baseVersion + "-beta" + beta, "beta"));
            client.Initialize();
            Check(client.Available && fake.Version == baseVersion + "b" + beta, "Beta machine version was lost");
        }
        foreach (var json in new[] { BetaConfig(baseVersion + "-beta1", "stable"),
            BetaConfig(baseVersion + "-beta0", "beta"), BetaConfig("99.0.0-beta1", "beta") })
        {
            var fake = new FakeBackend();
            using var client = Create(fake, json);
            client.Initialize();
            Check(fake.Configures == 0, "Invalid beta configuration reached native updater");
        }
        using var session = Create(backend, Config());
        int notifications = 0;
        var uiDispatcher = Dispatcher.CurrentDispatcher;
        session.StateChanged += () =>
        {
            Check(uiDispatcher.CheckAccess(), "State event left the UI thread");
            notifications++;
        };
        session.Initialize(); session.Initialize();
        Check(session.Available && backend.Starts == 1 && backend.Feed.EndsWith(Environment.Is64BitProcess ? "x64.xml" : "x86.xml"),
            "Architecture or idempotent initialization failed");
        session.Check(); session.Check();
        Check(backend.Checks == 1 && session.Busy, "Repeated check started concurrent native requests");
        Task.Run(backend.Callbacks.NotFound).GetAwaiter().GetResult(); Pump();
        Check(!session.Busy && session.Status.Contains("最新版本"), "No-update result not surfaced");
        session.Check(); Task.Run(backend.Callbacks.Error).GetAwaiter().GetResult(); Pump();
        Check(!session.Busy && session.Status.Contains("未完成"), "Failure prevents retry");
        backend.Callbacks.Dismissed(); Pump();
        Check(session.Status.Contains("未完成"), "Dismissal erased the failure result");
        session.Check(); backend.Callbacks.Found(); Pump();
        Check(session.Busy && session.Status.Contains("新版本"), "Found update state missing");
        backend.Callbacks.Cancelled(); backend.Callbacks.Dismissed(); Pump();
        Check(!session.Busy && session.Status.Contains("取消"), "Cancellation did not restore retry");
        session.Check(); backend.Callbacks.Dismissed(); Pump();
        Check(!session.Busy && session.Status.Contains("關閉"), "Closing a pending check leaves it busy");
        session.SetAutomatic(true); Check(session.Automatic, "Opt-in was not saved");
        session.SetAutomatic(false); Check(!session.Automatic, "Opt-out was not saved");
        session.SetUnsavedChanges(true);
        Check(backend.Callbacks.CanShutdown() == 0 && backend.Callbacks.BeforeInstall("unused.exe") == -1,
            "Unsaved edits allow installer launch"); Pump();
        session.SetUnsavedChanges(false);
        Check(backend.Callbacks.CanShutdown() == 1 && backend.Callbacks.BeforeInstall("unused.exe") == 0,
            "Saved settings do not retain normal installer handling");
        Task.Run(backend.Callbacks.Shutdown).GetAwaiter().GetResult();
        session.SetUnsavedChanges(true); Pump();
        Check(shutdowns == 0 && session.Status.Contains("保持開啟"), "Queued shutdown lost a newly edited draft");
        session.SetUnsavedChanges(false); backend.Callbacks.Shutdown(); Pump();
        Check(shutdowns == 1, "Clean shutdown was not dispatched");
        backend.Callbacks.Found();
        var beforeDispose = notifications;
        session.Dispose(); session.Dispose(); Finish(session.NativeCleanup); Pump();
        Check(!session.Available && !session.CanShutdown && !session.Busy &&
            backend.Cleanups == 1 && notifications == beforeDispose && shutdowns == 1,
            "Cleanup callbacks, queued callbacks or double disposal changed disposed state");
        var previousChecks = backend.Checks;
        session.Initialize(); session.Check();
        Check(backend.Starts == 1 && backend.Checks == previousChecks, "Disposed session restarted");
        var failing = new FakeBackend { FailStart = true };
        using var failed = Create(failing, Config());
        failed.Initialize();
        Finish(failed.NativeCleanup);
        Check(!failed.Available && failing.Cleanups == 1 && failed.Status.Contains("無法啟用") && shutdowns == 1,
            "Failed initialization did not clean up or retained stale callbacks");
        failing.FailStart = false;
        failed.Initialize(); Pump();
        Check(failed.Available && !failed.Status.Contains("未完成") && shutdowns == 1,
            "A callback queued by failed initialization changed the retried session");
        var oldCallbacks = failing.Callbacks;
        failed.Dispose(); oldCallbacks.Shutdown(); Finish(failed.NativeCleanup); Pump();
        Check(shutdowns == 1 && failing.Cleanups == 2, "Retried initialization retained shutdown after disposal");
        Console.WriteLine("Updater configuration, architecture, retry, opt-in, threaded callbacks and shutdown races passed");
    }

    private static void BetaChannelTests()
    {
        bool consent = false;
        int shutdowns = 0;
        string configuration = Config().TrimEnd('}') +
            ",\"windows_x64_beta_feed_url\":\"https://example.invalid/beta-x64.xml\",\"windows_x86_beta_feed_url\":\"https://example.invalid/beta-x86.xml\"}";
        var backend = new FakeBackend();
        using var client = new DesktopUpdater(backend, Dispatcher.CurrentDispatcher, () => shutdowns++,
            () => new MemoryStream(Encoding.UTF8.GetBytes(configuration)),
            readBetaPreference: () => consent, writeBetaPreference: value => consent = value);
        client.Initialize();
        Check(!client.BetaEnabled && !backend.BetaChannel && client.CanChangeBeta, "Beta must default off");
        var oldCallbacks = backend.Callbacks;
        Check(Finish(client.SetBetaAsync(true)) && consent && client.BetaEnabled && backend.BetaChannel &&
            backend.Feed.Contains("/beta-"), "Explicit beta opt-in did not choose pinned architecture feed");
        oldCallbacks.Found(); oldCallbacks.Shutdown(); Pump();
        Check(!client.Busy && shutdowns == 0, "Old-channel callback affected the new session");
        client.Check();
        Check(!Finish(client.SetBetaAsync(false)) && client.BetaEnabled, "Channel changed during a native update cycle");
        backend.Callbacks.Cancelled(); Pump();
        client.SetUnsavedChanges(true);
        Check(!Finish(client.SetBetaAsync(false)), "Channel changed with unsaved edits");
        client.SetUnsavedChanges(false);
        Check(Finish(client.SetBetaAsync(false)) && !consent && !backend.BetaChannel && !backend.Feed.Contains("/beta-"),
            "Opt-out did not return to stable");
        Check(backend.Checks == 1 && shutdowns == 0, "Channel toggle performed a network check or shutdown");
        Console.WriteLine("Default-off beta channel, architecture feeds, busy/unsaved guards and stale callbacks passed");
    }

    private static void TimeoutTests()
    {
        int shutdowns = 0;
        var backend = new FakeBackend();
        using var cleanupGate = new ManualResetEventSlim();
        backend.CleanupGate = cleanupGate;
        using var client = new DesktopUpdater(backend, Dispatcher.CurrentDispatcher, () => shutdowns++,
            () => new MemoryStream(Encoding.UTF8.GetBytes(Config())),
            readBetaPreference: () => false, writeBetaPreference: _ => { }, checkTimeout: TimeSpan.FromMilliseconds(30));
        client.Initialize(); client.Check();
        var expiredCallbacks = backend.Callbacks;
        Until(() => !client.Busy);
        Check(client.Status.Contains("逾時") && !client.Available && backend.Checks == 1,
            "Unresponsive CDN did not expire, or timeout automatically retried");
        bool uiRan = false;
        Dispatcher.CurrentDispatcher.BeginInvoke(() => uiRan = true); Pump();
        Check(uiRan && !client.NativeCleanup.IsCompleted, "Native cancellation blocked the WPF thread");
        expiredCallbacks.Found(); expiredCallbacks.Shutdown(); Pump();
        Check(expiredCallbacks.CanShutdown() == 0 && expiredCallbacks.BeforeInstall("unused.exe") == -1,
            "Expired native session could still launch an installer");
        Check(!client.Busy && client.Status.Contains("逾時") && shutdowns == 0,
            "Expired native callback changed state or shut down Settings");
        cleanupGate.Set(); Finish(client.NativeCleanup); Pump();
        Check(client.Available && backend.Starts == 1 && backend.Checks == 1,
            "Cleanup did not restore manual retry or performed an automatic query");
        client.Check(); expiredCallbacks.Error(); Pump();
        Check(client.Busy && backend.Starts == 2 && backend.Checks == 2,
            "Manual retry did not create a new session or accepted an expired callback");
        backend.Callbacks.NotFound(); Pump();
        Check(!client.Busy && client.Status.Contains("最新版本"), "Retry result was lost");
        client.Dispose(); Finish(client.NativeCleanup);

        var pending = new TaskCompletionSource<Uri>();
        int pages = 0;
        using var reinstall = new DesktopUpdater(new FakeBackend(), Dispatcher.CurrentDispatcher, () => { },
            () => new MemoryStream(Encoding.UTF8.GetBytes(Config(key: ""))),
            (_, _, _) => pending.Task, _ => pages++, checkTimeout: TimeSpan.FromMilliseconds(30));
        reinstall.Initialize(); Finish(reinstall.ReinstallAsync());
        Check(reinstall.Status.Contains("逾時") && reinstall.CanReinstall,
            "Download-page lookup ignored timeout or blocked retry");
        pending.SetResult(new Uri("https://github.com/polobread/KeyKey/releases/tag/v1.3.2")); Pump();
        Check(pages == 0 && reinstall.Status.Contains("逾時"), "Expired lookup opened a browser or overwrote timeout");
        Console.WriteLine("Query timeout, nonblocking native cancellation, manual retry and stale response cases passed");
    }

    private static void ReinstallTests()
    {
        string Release(string version, string architecture, string suffix = "-setup.unsigned.exe", long size = 1) =>
            JsonSerializer.Serialize(new { tag_name = "v" + version, draft = false,
                prerelease = version.Contains("-beta", StringComparison.Ordinal),
                html_url = "https://untrusted.invalid/", assets = new[] {
                    new { name = $"chichi77-KeyKey-{version.Split("-beta", StringSplitOptions.None)[0]}-windows-{architecture}{suffix}", size } } });
        Check(SameVersionDownload.SelectPage(Release("1.3.2", "x64"), "1.3.2", "x64").AbsoluteUri ==
            "https://github.com/polobread/KeyKey/releases/tag/v1.3.2", "Reinstall trusts an external page URL");
        Check(SameVersionDownload.SelectPage(Release("1.3.2", "x86", ".zip"), "1.3.2", "x86").Scheme == "https",
            "Manual x86 ZIP download is unavailable");
        Check(SameVersionDownload.SelectPage(Release("1.3.2-beta2", "x64"), "1.3.2-beta2", "x64").AbsoluteUri ==
            "https://github.com/polobread/KeyKey/releases/tag/v1.3.2-beta2", "Beta reinstall queried the stable tag");
        foreach (var json in new[] { Release("1.3.3", "x64"), Release("1.3.1", "x64"),
            Release("1.3.2", "x86"), Release("1.3.2", "x64", size: 0),
            Release("1.3.2", "x64").Replace("\"draft\":false", "\"draft\":true") })
        {
            bool rejected = false;
            try { SameVersionDownload.SelectPage(json, "1.3.2", "x64"); }
            catch (InvalidOperationException) { rejected = true; }
            Check(rejected, "Reinstall accepted a different version, architecture, empty or draft package");
        }

        int requests = 0, opened = 0;
        var pending = new TaskCompletionSource<Uri>();
        var backend = new FakeBackend();
        DesktopUpdater Create() => new(backend, Dispatcher.CurrentDispatcher, () => throw new Exception("Manual download shut down Settings"),
            () => new MemoryStream(Encoding.UTF8.GetBytes(Config(key: ""))),
            (version, architecture, token) =>
            {
                Check(architecture == (Environment.Is64BitProcess ? "x64" : "x86"), "Reinstall chose another architecture");
                requests++; return pending.Task;
            }, _ => opened++);
        void Finish(Task task)
        {
            while (!task.IsCompleted) Pump();
            task.GetAwaiter().GetResult();
        }
        using var updater = Create();
        updater.Initialize();
        Check(!updater.Available && updater.CanReinstall && requests == 0, "Manual download depends on update keys or connects on startup");
        updater.SetUnsavedChanges(true); Finish(updater.ReinstallAsync());
        Check(requests == 0 && !updater.CanReinstall, "Reinstall ignored existing drafts");
        updater.SetUnsavedChanges(false);
        var first = updater.ReinstallAsync(); Finish(updater.ReinstallAsync()); updater.Check();
        Check(requests == 1 && updater.Busy && !updater.CanReinstall && backend.Checks == 0, "Concurrent reinstall or update requests started");
        updater.SetUnsavedChanges(true);
        pending.SetResult(new Uri("https://github.com/polobread/KeyKey/releases/tag/v1.3.2")); Finish(first);
        Check(opened == 0 && !updater.Busy && updater.Status.Contains("儲存"), "A newly edited draft did not stop manual reinstall");
        updater.SetUnsavedChanges(false);
        pending = new TaskCompletionSource<Uri>();
        var retry = updater.ReinstallAsync(); pending.SetException(new System.Net.Http.HttpRequestException("offline")); Finish(retry);
        Check(updater.CanReinstall && updater.Status.Contains("offline"), "Failed reinstall prevents retry");
        pending = new TaskCompletionSource<Uri>();
        var success = updater.ReinstallAsync();
        pending.SetResult(new Uri("https://github.com/polobread/KeyKey/releases/tag/v1.3.2")); Finish(success);
        Check(opened == 1 && updater.CanReinstall && updater.Status.Contains("手動"), "Same-version page did not open or retry remained disabled");
        pending = new TaskCompletionSource<Uri>();
        var closing = updater.ReinstallAsync(); updater.Dispose();
        var before = updater.Status;
        pending.SetResult(new Uri("https://github.com/polobread/KeyKey/releases/tag/v1.3.2")); Finish(closing);
        Check(opened == 1 && updater.Status == before && !updater.CanReinstall, "Disposed Settings opened a page or changed state");
        Console.WriteLine("Same-version manual reinstall, exact version/architecture, draft, retry and disposal cases passed");
    }
}
