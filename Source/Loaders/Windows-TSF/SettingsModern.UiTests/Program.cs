using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Xml.Linq;
using KeyKeySettings;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    [DllImport("KeyKeySettingsBackend.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern IntPtr KeyKeyLookupReadings(string path, string phrase, out int status);
    [DllImport("KeyKeySettingsBackend.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void KeyKeyFreeReadings(IntPtr handle);
    [DllImport("KeyKeySettingsBackend.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyReadingAt(IntPtr handle, int character, int index, StringBuilder? target, int capacity);

    private static bool VerifyReadingBufferContract()
    {
        var handle = KeyKeyLookupReadings(Path.Combine(AppContext.BaseDirectory, "Databases", "KeyKey.db"), "銀行", out int status);
        try {
            if (handle == IntPtr.Zero || status != 1) return false;
            int required = KeyKeyReadingAt(handle, -1, 0, null, 0);
            var shortBuffer = new StringBuilder("unchanged", 32);
            return required > 1 && KeyKeyReadingAt(handle, -1, 0, shortBuffer, 1) == required &&
                shortBuffer.ToString() == "unchanged" && KeyKeyReadingAt(handle, -1, 999, null, 0) == 0;
        }
        finally { if (handle != IntPtr.Zero) KeyKeyFreeReadings(handle); }
    }
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
            var keys = Control<TextBox>(window, "CandidateSelectionKeys");
            var size = Control<TextBox>(window, "ComposingTextBufferSize");
            Check(keys.Text == "" && size.Text == "10" &&
                Control<CheckBox>(window, "ShowCandidateListWithSpace").IsChecked == false &&
                Control<CheckBox>(window, "SimplifiedChineseOutput").IsChecked == false,
                "Smart defaults changed");
            keys.Text = "12345677";
            var preferenceSnapshot = Directory.GetFiles(directory, "*.plist").ToDictionary(p => p, File.ReadAllText);
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text.Contains("8 個不重複") && Directory.GetFiles(directory, "*.plist").Length == preferenceSnapshot.Count &&
                preferenceSnapshot.All(p => File.ReadAllText(p.Key) == p.Value),
                "Invalid advanced setting partly saved preferences");
            keys.Text = "asdfjkl;";
            size.Text = "15";
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text.Contains("至少顯示一種"), "Empty mode selection was not rejected");
            Control<CheckBox>(window, "ShowSimplex").IsChecked = true;
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text == "設定已套用", "Apply failed: " + status.Text);
            var loader = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.plist"));
            Check(Value(loader, "PrimaryInputMethod") == "Generic-simplex-cin",
                "Hiding the current input method did not select Simplex");
            var simplex = XDocument.Load(Path.Combine(directory,
                "com.polobread.chichi77-keykey.windows.Generic-simplex-cin.plist"));
            Check(Value(simplex, "ComposeWhileTyping") == "true" &&
                  Value(simplex, "ClearReadingBufferAtCompositionError") == "false" &&
                  Value(simplex, "ShouldCommitAtMaximumRadicalLength") == "true",
                "Table options did not persist");
            var smart = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.SmartMandarin.plist"));
            Check(Value(smart, "CandidateSelectionKeys") == "asdfjkl;" && Value(smart, "ComposingTextBufferSize") == "15",
                "Advanced settings did not persist");
            var phraseText = Control<TextBox>(window, "PhraseText");
            var phraseReading = Control<TextBox>(window, "PhraseReading");
            phraseReading.Text = "手動讀音";
            phraseText.Text = "銀行";
            Check(phraseReading.Text == "手動讀音", "Editing phrase silently overwrote reading");
            var lookup = NativeBackend.LookupReadings("銀行");
            Check(lookup.Status == 1 && lookup.WholePhraseReadings.Count > 0 && lookup.Characters.Count == 2,
                $"Whole-phrase reading lookup failed: status={lookup.Status}, whole={lookup.WholePhraseReadings.Count}, characters={lookup.Characters.Count}");
            Check(lookup.WholePhraseReadings.Any(r => r.Contains("ㄏㄤˊ")), "Bank contextual reading missing");
            Check(VerifyReadingBufferContract(), "Native reading buffer capacity contract failed");
            Control<Button>(window, "LookupReadingsButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(phraseReading.Text == lookup.WholePhraseReadings[0], "Explicit lookup did not choose whole phrase reading");
            var readingPanel = Control<WrapPanel>(window, "CharacterReadingPanel");
            var readingBoxes = readingPanel.Children.OfType<StackPanel>().Select(p => p.Children.OfType<ComboBox>().Single()).ToArray();
            readingBoxes[1].ApplyTemplate();
            var editableReading = (TextBox)readingBoxes[1].Template.FindName("PART_EditableTextBox", readingBoxes[1]);
            editableReading.Text = "ㄒㄧㄥˊ";
            Check(phraseReading.Text.EndsWith("ㄒㄧㄥˊ"), "Per-character manual edit did not synchronize");
            phraseText.Text = "😀";
            Check(readingPanel.Children.Count == 0, "Stale choices remain after phrase edit");
            Control<Button>(window, "LookupReadingsButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(window, "ReadingStatus").Text.Contains("補齊"), "Missing reading not explained");
            var missing = NativeBackend.LookupReadings("😀");
            Check(missing.Status == 0 && missing.Characters.Count == 1 && missing.Characters[0].Readings.Count == 0,
                "Supplementary code point missing reading was lost");
            Check(NativeBackend.LookupReadings(new string('字', 65)).Status == -1,
                "Long phrase not bounded");
            var polyphonic = NativeBackend.LookupReadings(new string('行', 64));
            Check(polyphonic.Status == 1 && polyphonic.Characters.Count == 64 &&
                polyphonic.Characters.All(c => c.Readings.Count <= 32), "Polyphonic phrase not bounded");
            var supplementary = NativeBackend.LookupReadings("𠀀字");
            Check(supplementary.Characters.Count == 2 && supplementary.Characters[0].Text == "𠀀",
                "Supplementary ideograph split into surrogates");
            Check(NativeBackend.KeyKeySavePhrase(0, "銀行", "ㄧㄣˊ,ㄏㄤˊ") == 1, "Saving isolated custom phrase failed");
            var savedPhrase = NativeBackend.LoadPhrases().Single(p => p.Text == "銀行");
            Check(NativeBackend.KeyKeySavePhrase(0, "銀行", "ㄧㄣˊ,ㄏㄤˊ") == 0, "Duplicate phrase accepted");
            Check(NativeBackend.KeyKeySavePhrase(savedPhrase.RowId + 100, "銀行", "ㄧㄣˊ,ㄒㄧㄥˊ") == 0,
                "Missing rowid update inserted phrase");
            Check(NativeBackend.KeyKeySavePhrase(0, "😀", "") == 0, "Incomplete missing reading saved");
            window.Close();
            var reopened = new MainWindow();
            Check(Control<CheckBox>(reopened, "ShowSimplex").IsChecked == true &&
                  Control<CheckBox>(reopened, "ShowCangjie").IsChecked == false &&
                  Control<CheckBox>(reopened, "SimplexComposeWhileTyping").IsChecked == true &&
                  Control<CheckBox>(reopened, "SimplexClearOnError").IsChecked == false,
                "Settings did not survive reopening");
            Check(Control<TextBox>(reopened, "CandidateSelectionKeys").Text == "asdfjkl;" &&
                Control<TextBox>(reopened, "ComposingTextBufferSize").Text == "15", "Advanced settings did not reopen");
            Control<DataGrid>(reopened, "UserPhrases").SelectedItem =
                NativeBackend.LoadPhrases().Single(p => p.RowId == savedPhrase.RowId);
            Check(Control<TextBox>(reopened, "PhraseReading").Text == "ㄧㄣˊ,ㄏㄤˊ",
                "Saved reading lost on reopen selection");
            reopened.Close();
            Console.WriteLine("WPF settings controls, validation, native backend and Apply/reopen passed");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally {
            try { Directory.Delete(directory, true); }
            catch (IOException) { Console.WriteLine("Isolated TSF profile retained until COM host exits: " + directory); }
        }
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
