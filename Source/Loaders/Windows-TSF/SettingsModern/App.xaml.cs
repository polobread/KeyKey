using System.Windows;

namespace KeyKeySettings;

public partial class App : Application
{
    internal static DesktopUpdater Updater { get; } = new();
    protected override void OnExit(ExitEventArgs e)
    {
        Updater.Dispose();
        base.OnExit(e);
    }
}
