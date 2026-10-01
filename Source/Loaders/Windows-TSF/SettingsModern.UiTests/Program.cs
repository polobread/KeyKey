using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Xml.Linq;
using KeyKeySettings;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        var directory = Path.Combine(Path.GetTempPath(), "keykey-wpf-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", directory);
        try
        {
            // Construct real WPF controls and exercise their routed events without
            // opening a desktop window or touching the user's active settings.
            var app = new App();
            app.InitializeComponent();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            var window = new MainWindow();
            var status = Control<TextBlock>(window, "Status");
            Check(!status.Text.Contains("失敗") && !status.Text.Contains("找不到"),
                "Native settings backend or database failed to load");
            Check(Control<CheckBox>(window, "ShowCangjie").IsChecked == true &&
                  Control<CheckBox>(window, "ShowSimplex").IsChecked == true,
                "New table modes were not displayed by default");
            Check(Control<CheckBox>(window, "CangjieDynamicFrequency").IsChecked == false,
                "Old Windows dynamic-frequency default changed");
            var compose = Control<CheckBox>(window, "SimplexComposeWhileTyping");
            var clear = Control<CheckBox>(window, "SimplexClearOnError");
            Check(clear.IsChecked == true, "Simplex clear-on-error default changed");
            compose.IsChecked = true;
            Check(clear.IsChecked == false, "Compose did not disable clear-on-error");
            clear.IsChecked = true;
            Check(compose.IsChecked == false, "Clear-on-error did not disable compose");
            compose.IsChecked = true;
            foreach (var name in new[] { "ShowSmartMandarin", "ShowTraditionalMandarin", "ShowCangjie", "ShowSimplex" })
                Control<CheckBox>(window, name).IsChecked = false;
            var apply = Control<Button>(window, "ApplyButton");
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text.Contains("至少顯示一種"), "Empty mode selection was not rejected");
            Control<CheckBox>(window, "ShowSimplex").IsChecked = true;
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text == "設定已套用", "Apply failed");
            var loader = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.plist"));
            Check(Value(loader, "PrimaryInputMethod") == "Generic-simplex-cin",
                "Hiding the current input method did not select Simplex");
            var simplex = XDocument.Load(Path.Combine(directory,
                "com.polobread.chichi77-keykey.windows.Generic-simplex-cin.plist"));
            Check(Value(simplex, "ComposeWhileTyping") == "true" &&
                  Value(simplex, "ClearReadingBufferAtCompositionError") == "false" &&
                  Value(simplex, "ShouldCommitAtMaximumRadicalLength") == "true",
                "Table options did not persist");
            window.Close();
            var reopened = new MainWindow();
            Check(Control<CheckBox>(reopened, "ShowSimplex").IsChecked == true &&
                  Control<CheckBox>(reopened, "ShowCangjie").IsChecked == false &&
                  Control<CheckBox>(reopened, "SimplexComposeWhileTyping").IsChecked == true &&
                  Control<CheckBox>(reopened, "SimplexClearOnError").IsChecked == false,
                "Settings did not survive reopening");
            reopened.Close();
            Console.WriteLine("WPF settings controls, validation, native backend and Apply/reopen passed");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { Directory.Delete(directory, true); }
    }

    private static T Control<T>(MainWindow window, string name) where T : FrameworkElement
        => (T)(window.FindName(name) ?? throw new Exception("Missing control: " + name));
    private static string? Value(XDocument doc, string key)
        => doc.Root?.Element("dict")?.Elements("key").First(e => e.Value == key)
            .ElementsAfterSelf().First().Value;
    private static void Check(bool ok, string message)
    {
        if (!ok) throw new Exception(message);
    }
}
