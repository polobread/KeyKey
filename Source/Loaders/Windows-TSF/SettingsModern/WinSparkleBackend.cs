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
    DateTimeOffset LastAttempt { get; set; }
    void Configure(string key, string feed, string version, UpdateCallbacks callbacks, bool betaChannel = false);
    void Initialize();
    void Check(bool background = false);
    void Cleanup();
}

internal sealed class WinSparkleBackend : IDesktopUpdateBackend
{
    private const string RegistryPath = @"Software\chichi77\KeyKey\DesktopUpdates";
    private readonly string registryPath;
    private string preferencesPath = RegistryPath;
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
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(preferencesPath);
            return key?.GetValue("KeyKeyAutomaticChecks") is int value && value == 1;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(preferencesPath);
            key.SetValue("KeyKeyAutomaticChecks", value ? 1 : 0, RegistryValueKind.DWord);
        }
    }
    public DateTimeOffset LastAttempt
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(preferencesPath);
            return key?.GetValue("KeyKeyLastAttempt") is long ticks && ticks >= DateTimeOffset.MinValue.Ticks &&
                ticks <= DateTimeOffset.MaxValue.Ticks ? new DateTimeOffset(ticks, TimeSpan.Zero) : DateTimeOffset.MinValue;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(preferencesPath);
            key.SetValue("KeyKeyLastAttempt", value.UtcTicks, RegistryValueKind.QWord);
        }
    }
    public void Configure(string key, string feed, string version, UpdateCallbacks callbacks, bool betaChannel = false)
    {
        win_sparkle_set_app_details("chichi77", "琦琦輸入法", version);
        // Beta consent/skipped versions must not change stable updater preferences.
        preferencesPath = betaChannel ? registryPath + @"\Beta" : registryPath;
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
        else if (preferences.GetValue("KeyKeyAutomaticChecks") is null)
            Automatic = win_sparkle_get_automatic_check_for_updates() == 1;
        // Settings schedules daily checks through the same 10-second path as a
        // manual check. Native automatic checks have no start/cancel callback.
        win_sparkle_set_automatic_check_for_updates(0);
    }
    public void Initialize() => win_sparkle_init();
    // Both APIs start native workers immediately; never wait for network on WPF.
    public void Check(bool background = false)
    {
        if (background) win_sparkle_check_update_without_ui();
        else win_sparkle_check_update_with_ui();
    }
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
    [DllImport("WinSparkle.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void win_sparkle_check_update_without_ui();
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
