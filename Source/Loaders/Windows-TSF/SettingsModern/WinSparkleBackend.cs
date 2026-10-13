using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace KeyKeySettings;

internal sealed record UpdateCallbacks(Func<int> CanShutdown, Action Shutdown,
    Action Error, Action Found, Action NotFound, Action Cancelled, Action Dismissed,
    Func<string, int> BeforeInstall);

internal interface IDesktopUpdateBackend
{
    bool Automatic { get; set; }
    void Configure(string key, string feed, string version, UpdateCallbacks callbacks);
    void Initialize();
    void Check();
    void Cleanup();
}

internal sealed class WinSparkleBackend : IDesktopUpdateBackend
{
    private const string RegistryPath = @"Software\chichi77\KeyKey\DesktopUpdates";
    private readonly string registryPath;
    internal WinSparkleBackend(string registryPath = RegistryPath) => this.registryPath = registryPath;
    // Keep managed delegates rooted until AFTER native cleanup joins its threads.
    private CanShutdownCallback? canShutdown;
    private InstallCallback? beforeInstall;
    private NotificationCallback? shutdown, error, found, notFound, cancelled, dismissed;
    static WinSparkleBackend() => NativeLibrary.SetDllImportResolver(typeof(WinSparkleBackend).Assembly,
        (name, assembly, path) => name == "WinSparkle.dll"
            ? NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory, name)) : IntPtr.Zero);

    public bool Automatic
    {
        get => win_sparkle_get_automatic_check_for_updates() == 1;
        set => win_sparkle_set_automatic_check_for_updates(value ? 1 : 0);
    }
    public void Configure(string key, string feed, string version, UpdateCallbacks callbacks)
    {
        win_sparkle_set_app_details("chichi77", "琦琦輸入法", version);
        // Beta consent/skipped versions must not change stable updater preferences.
        var preferencesPath = version.Contains('b') ? registryPath + @"\Beta" : registryPath;
        win_sparkle_set_registry_path(preferencesPath);
        win_sparkle_set_appcast_url(feed);
        if (win_sparkle_set_eddsa_public_key(key) != 1)
            throw new InvalidOperationException("WinSparkle 拒絕公開金鑰");
        win_sparkle_set_update_check_interval(86400);
        canShutdown = () => callbacks.CanShutdown();
        shutdown = () => callbacks.Shutdown();
        error = () => callbacks.Error();
        found = () => callbacks.Found();
        notFound = () => callbacks.NotFound();
        cancelled = () => callbacks.Cancelled();
        dismissed = () => callbacks.Dismissed();
        beforeInstall = path => callbacks.BeforeInstall(path);
        win_sparkle_set_can_shutdown_callback(canShutdown);
        win_sparkle_set_shutdown_request_callback(shutdown);
        win_sparkle_set_error_callback(error);
        win_sparkle_set_did_find_update_callback(found);
        win_sparkle_set_did_not_find_update_callback(notFound);
        win_sparkle_set_update_cancelled_callback(cancelled);
        win_sparkle_set_update_dismissed_callback(dismissed);
        win_sparkle_set_user_run_installer_callback(beforeInstall);
        using var preferences = Registry.CurrentUser.CreateSubKey(preferencesPath);
        if (preferences.GetValue("ConsentInitialized") is null)
        {
            Automatic = false;
            preferences.SetValue("ConsentInitialized", 1, RegistryValueKind.DWord);
        }
    }
    public void Initialize() => win_sparkle_init();
    public void Check() => win_sparkle_check_update_with_ui();
    public void Cleanup()
    {
        win_sparkle_cleanup();
        GC.KeepAlive(canShutdown);
        GC.KeepAlive(beforeInstall);
        GC.KeepAlive(shutdown);
        GC.KeepAlive(error);
        GC.KeepAlive(found);
        GC.KeepAlive(notFound);
        GC.KeepAlive(cancelled);
        GC.KeepAlive(dismissed);
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CanShutdownCallback();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void NotificationCallback();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int InstallCallback([MarshalAs(UnmanagedType.LPWStr)] string path);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_init();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_cleanup();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern void win_sparkle_set_app_details(string company, string app, string version);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_registry_path([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void win_sparkle_set_appcast_url([MarshalAs(UnmanagedType.LPUTF8Str)] string url);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int win_sparkle_set_eddsa_public_key([MarshalAs(UnmanagedType.LPUTF8Str)] string key);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_update_check_interval(int seconds);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int win_sparkle_get_automatic_check_for_updates();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_automatic_check_for_updates(int value);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_check_update_with_ui();
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_can_shutdown_callback(CanShutdownCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_shutdown_request_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_error_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_did_find_update_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_did_not_find_update_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_update_cancelled_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_update_dismissed_callback(NotificationCallback callback);
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_set_user_run_installer_callback(InstallCallback callback);
}
