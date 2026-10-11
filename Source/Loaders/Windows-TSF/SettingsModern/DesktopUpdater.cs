using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace KeyKeySettings;

// Runs only in Settings, never inside another application's TSF process.
internal sealed class DesktopUpdater : IDisposable
{
    private readonly IDesktopUpdateBackend backend;
    private readonly Dispatcher dispatcher;
    private readonly Action requestShutdown;
    private readonly Func<Stream> readConfiguration;
    private bool initialized;
    private int generation;
    private volatile bool disposed;
    private volatile bool unsavedChanges;
    public bool Available => initialized && !disposed;
    internal bool CanShutdown => !disposed && !unsavedChanges;
    public bool Busy { get; private set; }
    public string Status { get; private set; } = "此建置尚未設定簽章更新服務，不會連線。";
    public bool Automatic => Available && backend.Automatic;
    public event Action? StateChanged;

    public DesktopUpdater() : this(new WinSparkleBackend(), Dispatcher.CurrentDispatcher,
        () => Application.Current.Shutdown(),
        () => Assembly.GetExecutingAssembly().GetManifestResourceStream("KeyKey.UpdateConfig")
            ?? throw new InvalidOperationException("缺少更新設定")) { }

    internal DesktopUpdater(IDesktopUpdateBackend backend, Dispatcher dispatcher,
        Action requestShutdown, Func<Stream> readConfiguration)
    {
        this.backend = backend;
        this.dispatcher = dispatcher;
        this.requestShutdown = requestShutdown;
        this.readConfiguration = readConfiguration;
    }

    public void Initialize()
    {
        if (initialized || disposed) return;
        var session = ++generation;
        void Dispatch(Action action) => Post(session, action);
        bool configured = false;
        try
        {
            using var stream = readConfiguration();
            using var document = JsonDocument.Parse(stream);
            var config = document.RootElement;
            if (config.GetProperty("schema_version").GetInt32() != 1)
                throw new InvalidOperationException("不支援的更新設定");
            var key = config.GetProperty("public_ed25519_key").GetString() ?? "";
            var feed = config.GetProperty(Environment.Is64BitProcess
                ? "windows_x64_feed_url" : "windows_x86_feed_url").GetString() ?? "";
            if (key.Length == 0 || feed.Length == 0) return;
            if (Convert.FromBase64String(key).Length != 32 ||
                !Uri.TryCreate(feed, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                uri.UserInfo.Length != 0 || uri.Fragment.Length != 0)
                throw new InvalidOperationException("更新網址或公開金鑰無效");

            var version = Assembly.GetExecutingAssembly().GetName().Version!;
            backend.Configure(key, uri.AbsoluteUri, $"{version.Major}.{version.Minor}.{version.Build}",
                new UpdateCallbacks(
                    () => CanShutdown ? 1 : 0,
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
                        if (CanShutdown) return 0; // Keep WinSparkle's normal interactive/UAC handling.
                        Dispatch(() => SetState("請先套用設定或儲存自訂詞，再重新檢查更新。", false));
                        return -1; // WINSPARKLE_RETURN_ERROR: never fall through to launching the file.
                    }));
            configured = true;
            initialized = true;
            SetState("只檢查發行版本，不傳送輸入內容。下載通過簽章驗證後，才啟動安裝程式並要求管理員授權。", false);
            backend.Initialize();
        }
        catch (Exception error) when (error is DllNotFoundException or BadImageFormatException
            or EntryPointNotFoundException or InvalidOperationException or FormatException
            or JsonException or KeyNotFoundException or IOException or UnauthorizedAccessException
            or System.Security.SecurityException)
        {
            initialized = false;
            generation++;
            if (configured) backend.Cleanup();
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
        Status = status;
        Busy = busy;
        StateChanged?.Invoke();
    }

    public void Check()
    {
        if (!Available || Busy) return;
        SetState("正在檢查更新…", true);
        backend.Check();
    }
    public void SetUnsavedChanges(bool value) => unsavedChanges = value;
    public void SetAutomatic(bool value)
    {
        if (Available) backend.Automatic = value;
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; // Drop callbacks already queued on the WPF dispatcher.
        Busy = false;
        if (initialized) { initialized = false; backend.Cleanup(); }
    }
}
