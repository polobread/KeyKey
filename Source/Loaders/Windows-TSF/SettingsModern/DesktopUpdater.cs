using System.IO;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;

namespace KeyKeySettings;

// Runs only in Settings, never inside another application's TSF process.
internal sealed class DesktopUpdater : IDisposable
{
    private readonly IDesktopUpdateBackend backend;
    private readonly Dispatcher dispatcher;
    private readonly Action requestShutdown;
    private readonly Func<Stream> readConfiguration;
    private readonly Func<string, string, CancellationToken, Task<Uri>> findReinstallDownload;
    private readonly Action<Uri> openDownloadPage;
    private readonly Func<bool> readBetaPreference;
    private readonly Action<bool> writeBetaPreference;
    private bool betaEnabled, betaAvailable;
    private readonly CancellationTokenSource lifetime = new();
    private volatile bool initialized;
    private int generation;
    private volatile bool disposed;
    private volatile bool unsavedChanges;
    private bool updateBusy;
    private bool reinstalling;
    private bool waitingForRetry;
    private Task nativeCleanup = Task.CompletedTask;
    private DispatcherTimer? checkTimer, automaticTimer;
    private readonly TimeSpan checkTimeout;
    private static readonly TimeSpan AutomaticInterval = TimeSpan.FromDays(7);
    private DateTimeOffset automaticNotBefore = DateTimeOffset.UtcNow.AddMinutes(10);
    private DateTimeOffset lastAttemptInMemory = DateTimeOffset.MinValue;
    internal Task NativeCleanup => nativeCleanup;
    private static string ProductVersion
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version!;
            return $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }
    private string releaseVersion = ProductVersion;
    public bool Available => !disposed && (initialized || (waitingForRetry && nativeCleanup.IsCompletedSuccessfully));
    public bool CanReinstall => !disposed && !Busy && !unsavedChanges;
    internal bool CanShutdown => !disposed && !unsavedChanges;
    public bool Busy => updateBusy || reinstalling;
    public string Status { get; private set; } = "此建置尚未設定簽章更新服務；可手動下載目前版本重新安裝。";
    public bool Automatic => Available && backend.Automatic;
    public bool BetaEnabled => betaEnabled;
    public bool CanChangeBeta => Available && betaAvailable && !Busy && !unsavedChanges;
    public event Action? StateChanged;

    public DesktopUpdater() : this(new WinSparkleBackend(), Dispatcher.CurrentDispatcher,
        () => Application.Current.Shutdown(),
        () => Assembly.GetExecutingAssembly().GetManifestResourceStream("KeyKey.UpdateConfig")
            ?? throw new InvalidOperationException("缺少更新設定")) { }

    internal DesktopUpdater(IDesktopUpdateBackend backend, Dispatcher dispatcher,
        Action requestShutdown, Func<Stream> readConfiguration,
        Func<string, string, CancellationToken, Task<Uri>>? findReinstallDownload = null,
        Action<Uri>? openDownloadPage = null,
        Func<bool>? readBetaPreference = null, Action<bool>? writeBetaPreference = null,
        TimeSpan? checkTimeout = null)
    {
        this.backend = backend;
        this.dispatcher = dispatcher;
        this.requestShutdown = requestShutdown;
        this.readConfiguration = readConfiguration;
        this.findReinstallDownload = findReinstallDownload ?? SameVersionDownload.FindAsync;
        this.openDownloadPage = openDownloadPage ?? (uri => Process.Start(
            new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }));
        this.readBetaPreference = readBetaPreference ?? BetaUpdatePreferences.Read;
        this.writeBetaPreference = writeBetaPreference ?? BetaUpdatePreferences.Write;
        this.checkTimeout = checkTimeout ?? TimeSpan.FromSeconds(10);
    }

    public void Initialize()
    {
        if (initialized || disposed || !nativeCleanup.IsCompletedSuccessfully) return;
        var session = ++generation;
        void Dispatch(Action action) => Post(session, action);
        bool ActiveSession() => !disposed && initialized && session == Volatile.Read(ref generation);
        bool configured = false;
        try
        {
            betaEnabled = readBetaPreference();
            using var stream = readConfiguration();
            using var document = JsonDocument.Parse(stream);
            var config = document.RootElement;
            if (config.GetProperty("schema_version").GetInt32() != 1)
                throw new InvalidOperationException("不支援的更新設定");
            if (config.TryGetProperty("release_version", out var configuredVersion))
            {
                var candidate = configuredVersion.GetString() ?? "";
                if (!Regex.IsMatch(candidate, "^" + Regex.Escape(ProductVersion) + @"(?:-beta[1-9]\d*)?$"))
                    throw new InvalidOperationException("更新版號與產品不符");
                var expectedChannel = candidate.Contains("-beta", StringComparison.Ordinal) ? "beta" : "stable";
                if (!config.TryGetProperty("update_channel", out var channel) || channel.GetString() != expectedChannel)
                    throw new InvalidOperationException("更新版號與 channel 不符");
                releaseVersion = candidate;
            }
            var key = config.GetProperty("public_ed25519_key").GetString() ?? "";
            var platform = Environment.Is64BitProcess ? "windows_x64" : "windows_x86";
            var stableFeed = config.GetProperty(platform + "_feed_url").GetString() ?? "";
            var betaFeed = config.TryGetProperty(platform + "_beta_feed_url", out var betaUrl)
                ? betaUrl.GetString() ?? "" : "";
            static bool ReviewedFeed(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
                uri.Scheme == "https" && uri.UserInfo.Length == 0 && uri.Fragment.Length == 0;
            betaAvailable = ReviewedFeed(stableFeed) && ReviewedFeed(betaFeed);
            // Missing beta configuration is never silently replaced with stable.
            var feed = betaEnabled ? betaFeed : stableFeed;
            if (key.Length == 0 || feed.Length == 0) return;
            if (Convert.FromBase64String(key).Length != 32 ||
                !Uri.TryCreate(feed, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                uri.UserInfo.Length != 0 || uri.Fragment.Length != 0)
                throw new InvalidOperationException("更新網址或公開金鑰無效");

            backend.Configure(key, uri.AbsoluteUri, releaseVersion.Replace("-beta", "b", StringComparison.Ordinal),
                new UpdateCallbacks(
                    () => ActiveSession() && CanShutdown ? 1 : 0,
                    () => Dispatch(() =>
                    {
                        // WinSparkle queries readiness BEFORE launching the installer.
                        // An edit made in that interval must survive its shutdown request.
                        if (CanShutdown) requestShutdown();
                        else SetState("安裝程式已啟動；設定有新的未儲存編輯，視窗將保持開啟。", false);
                    }),
                    () => Dispatch(() => SetState("更新未完成。請查看更新視窗的錯誤訊息，關閉後可重試。", false)),
                    () => Dispatch(() => SetState("有新版本可用。請在更新視窗確認下載與安裝。", true)),
                    () => Dispatch(() => SetState("目前已是最新版本。", false)),
                    () => Dispatch(() => SetState("已取消更新，可稍後重新檢查。", false)),
                    () => Dispatch(() => SetState(Busy ? "更新視窗已關閉，可重新檢查。" : Status, false)),
                    _ =>
                    {
                        if (ActiveSession() && CanShutdown) return 0; // Keep normal interactive/UAC handling.
                        Dispatch(() => SetState("請先套用設定或儲存自訂詞，再重新檢查更新。", false));
                        return -1; // WINSPARKLE_RETURN_ERROR: never fall through to launching the file.
                    }), betaEnabled);
            configured = true;
            initialized = true;
            SetState("只檢查並通知新版，不預先下載。按下更新後才下載，通過簽章驗證後啟動安裝程式並要求管理員授權。", false);
            backend.Initialize();
            UpdateAutomaticTimer();
        }
        catch (Exception error) when (error is DllNotFoundException or BadImageFormatException
            or EntryPointNotFoundException or InvalidOperationException or FormatException
            or JsonException or KeyNotFoundException or IOException or UnauthorizedAccessException
            or System.Security.SecurityException)
        {
            initialized = false;
            generation++;
            if (configured) nativeCleanup = Task.Run(backend.Cleanup);
            SetState($"更新服務無法啟用：{error.Message}（未開始檢查更新）", false);
        }
    }

    // Native callbacks must not wait for WPF: cleanup on the UI thread waits
    // for native threads, and synchronous dispatch would deadlock that shutdown.
    private void Post(int session, Action action)
    {
        if (disposed || dispatcher.HasShutdownStarted) return;
        dispatcher.BeginInvoke(() => { if (!disposed && initialized && session == generation) action(); });
    }

    private void SetState(string status, bool busy)
    {
        StopCheckTimer();
        Status = status;
        updateBusy = busy;
        StateChanged?.Invoke();
    }

    public void Check(bool background = false)
    {
        if (!Available || Busy) return;
        if (waitingForRetry)
        {
            waitingForRetry = false;
            Initialize();
            if (!initialized) return;
        }
        lastAttemptInMemory = DateTimeOffset.UtcNow;
        try { backend.LastAttempt = lastAttemptInMemory; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { UpdateAutomaticTimer(); SetState($"無法儲存檢查時間：{error.Message}", false); return; }
        UpdateAutomaticTimer();
        SetState("正在檢查更新…", true);
        var session = generation;
        checkTimer = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = checkTimeout };
        checkTimer.Tick += (_, _) => { _ = TimeoutCheckAsync(session); };
        checkTimer.Start();
        try { backend.Check(background); }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        { SetState($"檢查失敗：{error.Message}，請稍後按「立即檢查更新」再試。", false); }
    }

    private void StopCheckTimer()
    {
        checkTimer?.Stop();
        checkTimer = null;
    }

    private async Task TimeoutCheckAsync(int session)
    {
        if (disposed || !initialized || session != generation || checkTimer is null) return;
        // Invalidate callbacks BEFORE cancelling the native worker. Cleanup
        // joins its helper threads, so it must never run on the WPF thread.
        initialized = false;
        generation++;
        waitingForRetry = true;
        nativeCleanup = Task.Run(backend.Cleanup);
        SetState("檢查更新逾時（10 秒）；請稍後按「立即檢查更新」再試。", false);
        try { await nativeCleanup; }
        catch (Exception error) when (error is InvalidOperationException or IOException)
        {
            waitingForRetry = false;
            if (!disposed) SetState($"檢查已逾時，請關閉設定視窗後重試：{error.Message}", false);
        }
        if (!disposed) StateChanged?.Invoke();
    }

    private void UpdateAutomaticTimer()
    {
        automaticTimer?.Stop();
        automaticTimer = null;
        if (!Available || !backend.Automatic) return;
        var now = DateTimeOffset.UtcNow;
        var last = lastAttemptInMemory;
        try
        {
            var persisted = backend.LastAttempt;
            if (persisted > last) last = persisted;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            // A storage error defers the next attempt; it must not create a retry loop.
            last = now;
        }
        if (last > now) last = now;
        var next = automaticNotBefore;
        if (last != DateTimeOffset.MinValue && last + AutomaticInterval > next)
            next = last + AutomaticInterval;
        var delay = next - now;
        if (delay < TimeSpan.FromSeconds(1)) delay = TimeSpan.FromSeconds(1);
        var timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher) { Interval = delay };
        automaticTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(automaticTimer, timer) || disposed) return;
            automaticTimer = null;
            automaticNotBefore = DateTimeOffset.UtcNow + AutomaticInterval;
            if (Available && !Busy && backend.Automatic) Check(background: true);
            else UpdateAutomaticTimer();
        };
        timer.Start();
    }
    public async Task ReinstallAsync()
    {
        if (!CanReinstall) return;
        var current = releaseVersion;
        var architecture = Environment.Is64BitProcess ? "x64" : "x86";
        reinstalling = true;
        SetState($"正在確認版本 {current} 的 Windows {architecture} 下載…", false);
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            deadline.CancelAfter(checkTimeout);
            var page = await findReinstallDownload(current, architecture, deadline.Token).WaitAsync(deadline.Token);
            if (disposed) return;
            if (unsavedChanges)
            {
                SetState("請先套用設定或儲存自訂詞，再重新安裝目前版本。", updateBusy);
                return;
            }
            openDownloadPage(page);
            SetState($"已開啟版本 {current} 的官方下載頁。請下載 Windows {architecture} 套件，手動重新安裝。", updateBusy);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException
            or JsonException or InvalidOperationException or KeyNotFoundException or FormatException
            or System.ComponentModel.Win32Exception)
        {
            if (!disposed) SetState(error is OperationCanceledException
                ? "查詢下載頁逾時（10 秒）；請稍後再試。" : $"無法重新安裝：{error.Message}", updateBusy);
        }
        finally
        {
            reinstalling = false;
            if (!disposed) StateChanged?.Invoke();
        }
    }
    public void SetUnsavedChanges(bool value)
    {
        if (unsavedChanges == value) return;
        unsavedChanges = value;
        StateChanged?.Invoke();
    }
    public void SetAutomatic(bool value)
    {
        if (Available)
        {
            if (value && !backend.Automatic) automaticNotBefore = DateTimeOffset.UtcNow.AddMinutes(10);
            backend.Automatic = value;
            UpdateAutomaticTimer();
        }
    }
    public async Task<bool> SetBetaAsync(bool value)
    {
        if (value == betaEnabled) return true;
        if (!CanChangeBeta) return false;
        var previous = betaEnabled;
        try
        {
            writeBetaPreference(value);
            // Drop old callbacks BEFORE cleanup joins its native threads.
            generation++;
            var cleanupRequired = initialized;
            initialized = false;
            waitingForRetry = false;
            SetState("正在切換更新來源…", true);
            if (cleanupRequired) nativeCleanup = Task.Run(backend.Cleanup);
            await nativeCleanup;
            if (disposed) return false;
            Initialize();
            if (!Available) throw new InvalidOperationException("無法啟用選擇的更新來源");
            SetState(value ? "已選擇 beta 測試版來源；下載與安裝仍需確認。" : "已選擇正式版來源。", false);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                                      InvalidOperationException or System.Security.SecurityException)
        {
            try { writeBetaPreference(previous); }
            catch (Exception rollback) when (rollback is IOException or UnauthorizedAccessException or
                                             System.Security.SecurityException) { }
            betaEnabled = previous;
            if (!initialized) Initialize();
            SetState($"無法切換更新來源：{error.Message}", false);
            return false;
        }
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; // Drop callbacks already queued on the WPF dispatcher.
        StopCheckTimer();
        automaticTimer?.Stop(); automaticTimer = null;
        lifetime.Cancel();
        lifetime.Dispose();
        updateBusy = false;
        reinstalling = false;
        if (initialized) { initialized = false; generation++; nativeCleanup = Task.Run(backend.Cleanup); }
    }
}

internal static class BetaUpdatePreferences
{
    private const string Path = @"Software\chichi77\KeyKey\DesktopUpdatePreferences";
    internal static bool Read()
    {
        using var key = Registry.CurrentUser.OpenSubKey(Path);
        return key?.GetValue("IncludeBeta") is int value && value == 1;
    }
    internal static void Write(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(Path);
        key.SetValue("IncludeBeta", enabled ? 1 : 0, RegistryValueKind.DWord);
    }
}

// Manual download is separate from signed WinSparkle updates and runs only on a user click.
internal static class SameVersionDownload
{
    private static readonly HttpClient Client = new(new HttpClientHandler { AllowAutoRedirect = false })
    {
        Timeout = TimeSpan.FromSeconds(10),
        MaxResponseContentBufferSize = 1024 * 1024
    };

    internal static async Task<Uri> FindAsync(string version, string architecture, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/polobread/KeyKey/releases/tags/v{version}");
        request.Headers.UserAgent.ParseAdd("KeyKeySettings/" + version);
        using var response = await Client.SendAsync(request, token);
        if (response.StatusCode == HttpStatusCode.NotFound)
            throw new InvalidOperationException($"版本 {version} 尚未發布下載套件。");
        response.EnsureSuccessStatusCode();
        return SelectPage(await response.Content.ReadAsStringAsync(token), version, architecture);
    }

    internal static Uri SelectPage(string json, string version, string architecture)
    {
        using var document = JsonDocument.Parse(json);
        var release = document.RootElement;
        var productVersion = version.Split("-beta", StringSplitOptions.None)[0];
        var prefix = $"chichi77-KeyKey-{productVersion}-windows-{architecture}";
        var names = new[] { prefix + "-setup.exe", prefix + "-setup.unsigned.exe", prefix + ".zip" };
        if (release.GetProperty("tag_name").GetString() != "v" + version ||
            release.GetProperty("draft").GetBoolean() ||
            (version.Contains("-beta", StringComparison.Ordinal) &&
                (!release.TryGetProperty("prerelease", out var prerelease) || !prerelease.GetBoolean())) ||
            !release.GetProperty("assets").EnumerateArray().Any(asset =>
                names.Contains(asset.GetProperty("name").GetString(), StringComparer.Ordinal) &&
                asset.GetProperty("size").GetInt64() > 0))
            throw new InvalidOperationException($"版本 {version} 尚無 Windows {architecture} 下載套件。");
        // Construct the trusted page URL; never launch a URL returned in release JSON.
        return new Uri($"https://github.com/polobread/KeyKey/releases/tag/v{version}");
    }
}
