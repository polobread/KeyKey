using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using Microsoft.Win32;

namespace KeyKeySettings;

// Runs only in Settings, never inside another application's TSF process.
internal sealed class DesktopUpdater : IDisposable
{
    private const string RegistryPath = @"Software\chichi77\KeyKey\DesktopUpdates";
    private bool initialized;
    private volatile bool unsavedChanges;
    private readonly CanShutdownCallback canShutdown;
    private readonly ShutdownCallback shutdown;
    public bool Available => initialized;
    internal bool CanShutdown => !unsavedChanges;
    public string Status { get; private set; } = "此建置尚未設定簽章更新服務，不會連線。";
    public bool Automatic => initialized && win_sparkle_get_automatic_check_for_updates() == 1;

    public DesktopUpdater()
    {
        // Native callbacks must not synchronously wait for WPF: cleanup on the
        // UI thread could otherwise deadlock against a pending shutdown query.
        canShutdown = () => CanShutdown ? 1 : 0;
        shutdown = () => Application.Current.Dispatcher.BeginInvoke(() => Application.Current.Shutdown());
    }

    public void Initialize()
    {
        if (initialized) return;
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("KeyKey.UpdateConfig")
                ?? throw new InvalidOperationException("缺少更新設定");
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

            NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), (name, assembly, path) =>
                name == "WinSparkle.dll" ? NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory, name)) : IntPtr.Zero);
            var version = Assembly.GetExecutingAssembly().GetName().Version!;
            win_sparkle_set_app_details("chichi77", "琦琦輸入法", $"{version.Major}.{version.Minor}.{version.Build}");
            win_sparkle_set_registry_path(RegistryPath);
            win_sparkle_set_appcast_url(uri.AbsoluteUri);
            if (win_sparkle_set_eddsa_public_key(key) != 1)
                throw new InvalidOperationException("WinSparkle 拒絕公開金鑰");
            win_sparkle_set_update_check_interval(86400);
            win_sparkle_set_can_shutdown_callback(canShutdown);
            win_sparkle_set_shutdown_request_callback(shutdown);
            using var preferences = Registry.CurrentUser.CreateSubKey(RegistryPath);
            if (preferences.GetValue("ConsentInitialized") is null)
            {
                win_sparkle_set_automatic_check_for_updates(0);
                preferences.SetValue("ConsentInitialized", 1, RegistryValueKind.DWord);
            }
            win_sparkle_init();
            initialized = true;
            Status = "只檢查發行版本，不傳送輸入內容。下載通過 Ed25519 驗證後，才啟動安裝程式並要求管理員授權。";
        }
        catch (Exception error) when (error is DllNotFoundException or BadImageFormatException
            or EntryPointNotFoundException or InvalidOperationException or FormatException
            or JsonException or KeyNotFoundException or IOException or UnauthorizedAccessException)
        {
            Status = $"更新服務無法啟用：{error.Message}（未開始檢查更新）";
        }
    }

    public void Check() { if (initialized) win_sparkle_check_update_with_ui(); }
    public void SetUnsavedChanges(bool value) => unsavedChanges = value;
    public void SetAutomatic(bool value)
    {
        if (initialized) win_sparkle_set_automatic_check_for_updates(value ? 1 : 0);
    }
    public void Dispose()
    {
        if (initialized) { win_sparkle_cleanup(); initialized = false; }
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CanShutdownCallback();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void ShutdownCallback();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_init();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_cleanup();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern void win_sparkle_set_app_details(string company, string app, string version);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_registry_path([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_appcast_url([MarshalAs(UnmanagedType.LPUTF8Str)] string url);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int win_sparkle_set_eddsa_public_key([MarshalAs(UnmanagedType.LPUTF8Str)] string key);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_update_check_interval(int seconds);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int win_sparkle_get_automatic_check_for_updates();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_automatic_check_for_updates(int value);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_check_update_with_ui();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_can_shutdown_callback(CanShutdownCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_shutdown_request_callback(ShutdownCallback callback);
}
