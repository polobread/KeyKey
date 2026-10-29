using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Xml.Linq;
using KeyKeySettings;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private static IReadOnlyList<PhraseRow> LoadRustPhrases()
    {
        using var data = NativeUserData.Open();
        return data.Load();
    }
    private static void VerifyGuanyinmaData(MainWindow window)
    {
        Check(window.FindName("InputCore") is null, "The retired core selector is still present");
        Check(File.Exists(Path.Combine(Path.GetDirectoryName(SettingsStore.LoaderPath)!, "GuanyinmaUserData.db")), "Settings must open Rust data by default");
        Check(!File.Exists(Path.Combine(Path.GetDirectoryName(SettingsStore.LoaderPath)!, "SmartMandarinUserData.db")), "Settings opened the old writable store");
        using var rust = NativeUserData.Open();
        Check(rust.Save(0, "妮好", "ㄋㄧˇ,ㄏㄠˇ") && rust.Load().Count == 1, "Managed Rust insert failed");
        var reopened = new MainWindow();
        Check(reopened.FindName("InputCore") is null &&
            Control<DataGrid>(reopened, "UserPhrases").Items.Cast<PhraseRow>().Single().Text == "妮好", "Reopened settings changed its data owner");
        var row = rust.Load().Single();
        Check(rust.Save(row.RowId, "妮豪", "ㄋㄧˇ,ㄏㄠˊ") && rust.Load().Single().Text == "妮豪", "Managed Rust update failed");
        Check(rust.Reset() && rust.Load().Count == 1, "Managed reset removed custom phrases");
        Check(rust.Delete(rust.Load().Single().RowId) && rust.Load().Count == 0, "Managed Rust delete failed");
        reopened.Close();
        Console.WriteLine("Required Guanyinma data, obsolete preference isolation and managed CRUD/reset smoke passed");
    }
    private static void VerifyPhoneticControls(MainWindow window, string directory)
    {
        var keys = Control<ComboBox>(window, "CandidateSelectionKeys");
        var size = Control<Slider>(window, "ComposingTextBufferSize");
        var apply = Control<Button>(window, "ApplyButton");
        var path = Path.Combine(directory, "com.polobread.chichi77-keykey.windows.SmartMandarin.plist");
        string[] presets = ["12345678", "asdfghjk", "asdfzxcv"];
        Check(!keys.IsEditable && keys.Items.Cast<string>().SequenceEqual(presets) && keys.SelectedIndex == 0,
            "Selection keys must offer exactly the three macOS presets and default to digits");
        Check(size.Minimum == 10 && size.Maximum == 20 && size.Value == 10 &&
              size.IsSnapToTickEnabled && size.TickFrequency == 1 && size.SmallChange == 1,
            "Composition slider must default to 10 and use integer steps from 10 to 20");
        Check(App.Updater.CanShutdown, "Loading phonetic controls marked settings as edited");
        foreach (var index in new[] { 1, 2, 0 })
        {
            keys.SelectedIndex = index;
            Check(!App.Updater.CanShutdown, "Changing selection-key preset did not protect unsaved settings");
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(window, "Status").Text == "設定已套用" && App.Updater.CanShutdown,
                "Applying selection-key preset failed: " + Control<TextBlock>(window, "Status").Text);
            Check(Value(XDocument.Load(path), "CandidateSelectionKeys") == presets[index], "Preset not saved");
            var reopened = new MainWindow();
            Check((string)Control<ComboBox>(reopened, "CandidateSelectionKeys").SelectedItem == presets[index],
                "Selection-key preset not restored");
            reopened.Close();
        }
        foreach (var length in Enumerable.Range(11, 10).Append(10))
        {
            size.Value = length;
            Check(!App.Updater.CanShutdown, "Moving composition slider did not protect unsaved settings");
            var label = Control<TextBlock>(window, "ComposingTextBufferSizeLabel");
            label.GetBindingExpression(TextBlock.TextProperty)!.UpdateTarget();
            Check(label.Text == $"{length} 音節", "Composition length label did not follow slider");
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(window, "Status").Text == "設定已套用" && App.Updater.CanShutdown &&
                  Value(XDocument.Load(path), "ComposingTextBufferSize") == length.ToString(),
                "Composition length not saved as an integer");
            var reopened = new MainWindow();
            Check(Control<Slider>(reopened, "ComposingTextBufferSize").Value == length,
                "Composition length not restored");
            reopened.Close();
        }
        // Old custom/automatic keys must be shown as numeric, then normalized on Apply.
        foreach (var legacy in new[] { "", "asdfjkl;", "12345677", "123456789" })
        {
            new XDocument(new XElement("plist", new XElement("dict",
                new XElement("key", "CandidateSelectionKeys"), new XElement("string", legacy),
                new XElement("key", "ComposingTextBufferSize"), new XElement("string", "15")))).Save(path);
            var snapshot = File.ReadAllText(path);
            var reopened = new MainWindow();
            Check((string)Control<ComboBox>(reopened, "CandidateSelectionKeys").SelectedItem == presets[0] &&
                  Control<Slider>(reopened, "ComposingTextBufferSize").Value == 15 &&
                  File.ReadAllText(path) == snapshot && App.Updater.CanShutdown,
                "Legacy keys did not fall back to digits without saving on open");
            Control<Button>(reopened, "ApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(reopened, "Status").Text == "設定已套用" &&
                  Value(XDocument.Load(path), "CandidateSelectionKeys") == presets[0],
                "Legacy selection keys were not normalized on Apply");
            reopened.Close();
        }
        Console.WriteLine("Phonetic presets, integer slider, unsaved protection and legacy Apply/reopen passed");
    }

    private static void VerifyCapsLock(MainWindow window, string directory)
    {
        var option = Control<CheckBox>(window, "IgnoreCapsLockInChinese");
        Check(option.IsChecked == true, "Windows Chinese Caps Lock option must default to enabled");
        foreach (var enabled in new[] { false, true })
        {
            option.IsChecked = enabled;
            Control<Button>(window, "ApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(window, "Status").Text == "設定已套用", "Caps Lock Apply failed");
            var loader = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.plist"));
            Check(Value(loader, "IgnoreCapsLockInChinese") == (enabled ? "true" : "false"), "Caps Lock choice not saved");
            var reopened = new MainWindow();
            Check(Control<CheckBox>(reopened, "IgnoreCapsLockInChinese").IsChecked == enabled, "Caps Lock choice not restored");
            reopened.Close();
        }
        Console.WriteLine("Chinese Caps Lock default, disable/enable, Apply and reopen passed");
    }
    private static void VerifySymbolShortcut(MainWindow window, string directory)
    {
        var option = Control<CheckBox>(window, "SymbolPanelShortcut");
        Check(option.IsChecked == true, "Symbol shortcut must default to enabled");
        option.IsChecked = false;
        Control<Button>(window, "ApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(Control<TextBlock>(window, "Status").Text == "設定已套用", "Disable shortcut Apply failed");
        var loader = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.plist"));
        Check(Value(loader, "SymbolPanelShortcutEnabled") == "false", "Disabled shortcut not saved");
        var reopened = new MainWindow();
        Check(Control<CheckBox>(reopened, "SymbolPanelShortcut").IsChecked == false, "Disabled shortcut not restored");
        Control<CheckBox>(reopened, "SymbolPanelShortcut").IsChecked = true;
        Control<Button>(reopened, "ApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(Control<TextBlock>(reopened, "Status").Text == "設定已套用", "Enable shortcut Apply failed");
        reopened.Close();
        var enabled = new MainWindow();
        Check(Control<CheckBox>(enabled, "SymbolPanelShortcut").IsChecked == true, "Enabled shortcut not restored");
        enabled.Close();
        Console.WriteLine("Symbol shortcut default, disable/enable, Apply and reopen passed");
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct OSVersion
    {
        public uint Size, Major, Minor, Build, Platform;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string ServicePack;
        public ushort ServicePackMajor, ServicePackMinor, Suite;
        public byte ProductType, Reserved;
    }
    [DllImport("kernel32.dll")]
    private static extern ulong VerSetConditionMask(ulong mask, uint type, byte condition);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool VerifyVersionInfoW(ref OSVersion version, uint type, ulong mask);

    private static void VerifyUpdateWindowsCompatibility()
    {
        // Same check used by WinSparkle for a Windows 10+ appcast. The test host
        // embeds the Settings manifest so missing supportedOS fails on Windows 11 too.
        var version = new OSVersion { Size = (uint)Marshal.SizeOf<OSVersion>(), Major = 10, ServicePack = "" };
        ulong mask = 0;
        foreach (uint field in new uint[] { 2, 1, 4 }) mask = VerSetConditionMask(mask, field, 3);
        Check(VerifyVersionInfoW(ref version, 7, mask), "Windows 10+ update rejected by the application manifest");
    }

    private static void VerifyUpdateShutdownProtection(MainWindow window)
    {
        var text = Control<TextBox>(window, "PhraseText");
        var reading = Control<TextBox>(window, "PhraseReading");
        var status = Control<TextBlock>(window, "Status");
        var apply = Control<Button>(window, "ApplyButton");
        var add = Control<Button>(window, "AddPhraseButton");
        Check(App.Updater.CanShutdown, "Fresh window incorrectly blocks an update");
        var reinstall = Control<Button>(window, "ReinstallCurrent");
        Check(reinstall.IsEnabled && !Control<Button>(window, "CheckUpdate").IsEnabled,
            "Manual reinstall should remain available without a signed update configuration");

        text.Text = "更新龘";
        reading.Text = "ㄍㄥ,ㄒㄧㄣ,ㄉㄚˊ";
        Check(!App.Updater.CanShutdown, "Phrase draft does not block update shutdown");
        Check(!reinstall.IsEnabled, "Phrase draft does not disable manual reinstall");
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(status.Text == "設定已套用" && !App.Updater.CanShutdown &&
              LoadRustPhrases().All(p => p.Text != "更新龘"),
              "Applying general settings discarded protection for an unsaved phrase");
        reading.Text = "ㄍㄥ";
        add.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(status.Text.StartsWith("儲存失敗") && !App.Updater.CanShutdown,
              "Failed phrase save removed update shutdown protection");
        reading.Text = "ㄍㄥ,ㄒㄧㄣ,ㄉㄚˊ";
        add.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(status.Text == "自訂詞已儲存" && App.Updater.CanShutdown,
              "Successfully saved phrase still blocks an update");
        Check(reinstall.IsEnabled, "Saved phrase did not enable manual reinstall");

        var phrases = Control<DataGrid>(window, "UserPhrases");
        phrases.SelectedItem = phrases.Items.OfType<PhraseRow>().Single(p => p.Text == "更新龘");
        Check(App.Updater.CanShutdown, "Selecting a saved phrase incorrectly marks settings as edited");
        var beep = Control<CheckBox>(window, "TypingBeep");
        beep.IsChecked = !beep.IsChecked;
        Check(!App.Updater.CanShutdown, "Unsaved general setting does not block an update");
        Check(!reinstall.IsEnabled, "Unsaved settings do not disable manual reinstall");
        reading.Text = "ㄍㄥˋ,ㄒㄧㄣ,ㄉㄚˊ";
        Control<Button>(window, "UpdatePhraseButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(status.Text == "自訂詞已儲存" && !App.Updater.CanShutdown,
              "Saving a phrase incorrectly cleared unsaved general settings");
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(App.Updater.CanShutdown, "Applying settings after saving phrase still blocks an update");
        Check(reinstall.IsEnabled, "Applying saved settings did not enable manual reinstall");

        // A second phrase edit must be tracked against the successfully saved value.
        phrases.SelectedItem = phrases.Items.OfType<PhraseRow>().Single(p => p.Text == "更新龘");
        Check(App.Updater.CanShutdown, "Selecting the modified saved phrase blocks an update");
        reading.Text = "ㄍㄥ,ㄒㄧㄣ,ㄉㄚˊ";
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(!App.Updater.CanShutdown, "Apply cleared a modified existing phrase draft");
        Control<Button>(window, "UpdatePhraseButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(status.Text == "自訂詞已儲存" && App.Updater.CanShutdown,
              "Modified phrase did not clear its own protection after saving");

        var collection = Control<DataGrid>(window, "Collections").Items.OfType<CollectionRow>().First();
        collection.Enabled = !collection.Enabled;
        Check(!App.Updater.CanShutdown, "Collection model changes do not block an update");
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(App.Updater.CanShutdown, "Saved collection settings still block an update");
        Console.WriteLine("Updater Windows compatibility and settings/phrase shutdown protection passed");
    }

    private static void VerifyDiagnosticSwitch(MainWindow window)
    {
        var toggle = Control<CheckBox>(window, "DiagnosticLogging");
        var apply = Control<Button>(window, "ApplyButton");
        Check(toggle.IsChecked == false && !DiagnosticSettings.Read().Active,
            "Diagnostic switch must default to off");
        toggle.IsChecked = true;
        Check(!App.Updater.CanShutdown && !DiagnosticSettings.Read().Active,
            "Unsaved diagnostic toggle must be protected and must not start logging");
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        var session = DiagnosticSettings.Read();
        Check(session.Active && session.ExpiresAtUtc - session.StartedAtUtc == 3 * 86400,
            "Applying diagnostic switch did not persist the three-day deadline");
        Control<CheckBox>(window, "TypingBeep").IsChecked = !Control<CheckBox>(window, "TypingBeep").IsChecked;
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(DiagnosticSettings.Read() == session, "Unrelated Apply extended the diagnostic deadline");
        var reopened = new MainWindow();
        Check(Control<CheckBox>(reopened, "DiagnosticLogging").IsChecked == true &&
              Control<TextBlock>(reopened, "DiagnosticStatus").Text.Contains("自動關閉"),
            "Diagnostic state did not survive reopening");
        reopened.Close();
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        File.WriteAllText(DiagnosticSettings.Path,
            $"<plist><dict><key>StartedAtUtc</key><string>{now - 3 * 86400}</string><key>ExpiresAtUtc</key><string>{now}</string></dict></plist>");
        var expired = new MainWindow();
        Check(Control<CheckBox>(expired, "DiagnosticLogging").IsChecked == false &&
              Control<TextBlock>(expired, "DiagnosticStatus").Text.Contains("已到期"),
            "Expired diagnostics reopened as enabled");
        expired.Close();
        toggle.IsChecked = false;
        apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(!DiagnosticSettings.Read().Active, "Manual diagnostic disable was not saved");
        Console.WriteLine("WPF diagnostic toggle, deadline preservation and expiry passed");
    }

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
    private static int Main(string[] args)
    {
        var directory = Path.Combine(Path.GetTempPath(), "keykey-wpf-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", directory);
        try
        {
            VerifyUpdateWindowsCompatibility();
            // Construct real WPF controls and exercise their routed events without
            // opening a desktop window or touching the user's active settings.
            var app = new App();
            app.InitializeComponent();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            if (args.Contains("--guanyinma-data"))
                SettingsStore.Write(SettingsStore.LoaderPath, new Dictionary<string, string> { ["InputCore"] = "Manjusri" });
            var window = new MainWindow();
            if (args.Contains("--guanyinma-data"))
            {
                VerifyGuanyinmaData(window); window.Close(); return 0;
            }
            if (args.Contains("--phonetic-controls"))
            {
                VerifyPhoneticControls(window, directory);
                if (Environment.GetEnvironmentVariable("KEYKEY_TEST_SETTINGS_PREVIEW") is { Length: > 0 } previewPath)
                {
                    var content = (FrameworkElement)window.Content;
                    LogicalTreeHelper.GetChildren(content).OfType<TabControl>().Single().SelectedIndex = 1;
                    ((Panel)content).Background = SystemColors.WindowBrush;
                    content.Measure(new Size(900, 900));
                    content.Arrange(new Rect(0, 0, 900, 900));
                    content.UpdateLayout();
                    var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap(
                        (int)content.ActualWidth, (int)content.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                    bitmap.Render(content);
                    var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
                    encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
                    using var output = File.Create(previewPath);
                    encoder.Save(output);
                }
                window.Close();
                return 0;
            }
            if (args.Contains("--caps-lock"))
            {
                VerifyCapsLock(window, directory);
                window.Close();
                return 0;
            }
            if (args.Contains("--symbol-shortcut"))
            {
                VerifySymbolShortcut(window, directory);
                window.Close();
                return 0;
            }
            if (args.Contains("--updater"))
            {
                VerifyUpdateShutdownProtection(window);
                window.Close();
                return 0;
            }
            var status = Control<TextBlock>(window, "Status");
            Check(Control<RadioButton>(window, "DefaultChineseMode").IsChecked == true &&
                  Control<RadioButton>(window, "DefaultEnglishMode").IsChecked == false,
                "Startup mode must default to Chinese");
            Control<RadioButton>(window, "DefaultEnglishMode").IsChecked = true;
            Check(!status.Text.Contains("失敗") && !status.Text.Contains("找不到"),
                "Native settings backend or database failed to load");
            Check(Control<CheckBox>(window, "ShowCangjie").IsChecked == true &&
                  Control<CheckBox>(window, "ShowSimplex").IsChecked == true,
                "New table modes were not displayed by default");
            Check(Control<CheckBox>(window, "CangjieDynamicFrequency").IsChecked == false,
                "Old Windows dynamic-frequency default changed");
            var cangjieCompose = Control<CheckBox>(window, "CangjieComposeWhileTyping");
            var cangjiePrefix = Control<CheckBox>(window, "CangjiePrefixCandidates");
            var cangjieClear = Control<CheckBox>(window, "CangjieClearOnError");
            Check(cangjieCompose.IsChecked == false && cangjiePrefix.IsChecked == false &&
                  !cangjiePrefix.IsEnabled, "Cangjie preview defaults/dependency changed");
            cangjieCompose.IsChecked = true;
            Check(cangjiePrefix.IsEnabled && cangjieClear.IsChecked == false,
                "Cangjie realtime did not enable prefix and disable error clearing");
            cangjiePrefix.IsChecked = true;
            cangjieClear.IsChecked = true;
            Check(!cangjiePrefix.IsEnabled && cangjiePrefix.IsChecked == true &&
                  cangjieCompose.IsChecked == false, "Cangjie error clearing did not suspend prefix");
            cangjieCompose.IsChecked = true;
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
            var keys = Control<ComboBox>(window, "CandidateSelectionKeys");
            var size = Control<Slider>(window, "ComposingTextBufferSize");
            Check((string)keys.SelectedItem == "12345678" && size.Value == 10 &&
                Control<CheckBox>(window, "ShowCandidateListWithSpace").IsChecked == false &&
                Control<CheckBox>(window, "SimplifiedChineseOutput").IsChecked == false,
                "Smart defaults changed");
            keys.SelectedIndex = 1;
            size.Value = 15;
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text.Contains("至少顯示一種"), "Empty mode selection was not rejected");
            Control<CheckBox>(window, "ShowSimplex").IsChecked = true;
            apply.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(status.Text == "設定已套用", "Apply failed: " + status.Text);
            var loader = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.plist"));
            Check(Value(loader, "DefaultInputMode") == "English", "English startup mode did not persist");
            Check(Value(loader, "PrimaryInputMethod") == "Generic-simplex-cin",
                "Hiding the current input method did not select Simplex");
            var simplex = XDocument.Load(Path.Combine(directory,
                "com.polobread.chichi77-keykey.windows.Generic-simplex-cin.plist"));
            Check(Value(simplex, "ComposeWhileTyping") == "true" &&
                  Value(simplex, "ClearReadingBufferAtCompositionError") == "false" &&
                  Value(simplex, "ShouldCommitAtMaximumRadicalLength") == "true",
                "Table options did not persist");
            var cangjieSaved = XDocument.Load(Path.Combine(directory,
                "com.polobread.chichi77-keykey.windows.Generic-cj-cin.plist"));
            Check(Value(cangjieSaved, "PrefixCandidates") == "true" &&
                  Value(cangjieSaved, "ComposeWhileTyping") == "true",
                  "Cangjie prefix choices did not persist");
            var smart = XDocument.Load(Path.Combine(directory, "com.polobread.chichi77-keykey.windows.SmartMandarin.plist"));
            Check(Value(smart, "CandidateSelectionKeys") == "asdfghjk" && Value(smart, "ComposingTextBufferSize") == "15",
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
            using var words = NativeUserData.Open();
            Check(words.Save(0, "銀航", "ㄧㄣˊ,ㄏㄤˊ"), "Saving isolated custom phrase failed");
            var savedPhrase = words.Load().Single(p => p.Text == "銀航");
            Check(words.Save(0, "銀航", "ㄧㄣˊ,ㄏㄤˊ") && words.Load().Count(p => p.Text == "銀航") == 1, "Idempotent add duplicated a phrase");
            savedPhrase = words.Load().Single(p => p.Text == "銀航");
            Check(!words.Save(savedPhrase.RowId + 100, "銀航", "ㄧㄣˊ,ㄒㄧㄥˊ"),
                "Missing rowid update inserted phrase");
            Check(!words.Save(0, "😀", ""), "Incomplete missing reading saved");
            window.Close();
            var reopened = new MainWindow();
            Check(Control<RadioButton>(reopened, "DefaultEnglishMode").IsChecked == true,
                "English startup mode did not survive reopening");
            Check(Control<CheckBox>(reopened, "ShowSimplex").IsChecked == true &&
                  Control<CheckBox>(reopened, "ShowCangjie").IsChecked == false &&
                  Control<CheckBox>(reopened, "SimplexComposeWhileTyping").IsChecked == true &&
                  Control<CheckBox>(reopened, "SimplexClearOnError").IsChecked == false,
                "Settings did not survive reopening");
            Check((string)Control<ComboBox>(reopened, "CandidateSelectionKeys").SelectedItem == "asdfghjk" &&
                Control<Slider>(reopened, "ComposingTextBufferSize").Value == 15, "Advanced settings did not reopen");
            Control<DataGrid>(reopened, "UserPhrases").SelectedItem =
                Control<DataGrid>(reopened, "UserPhrases").Items.Cast<PhraseRow>().Single(p => p.Text == "銀航");
            Check(Control<TextBox>(reopened, "PhraseReading").Text == "ㄧㄣˊ,ㄏㄤˊ",
                "Saved reading lost on reopen selection");
            Control<RadioButton>(reopened, "DefaultChineseMode").IsChecked = true;
            Control<Button>(reopened, "ApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(Control<TextBlock>(reopened, "Status").Text == "設定已套用", "Restore Chinese startup mode failed");
            reopened.Close();
            var chineseReopened = new MainWindow();
            Check(Control<RadioButton>(chineseReopened, "DefaultChineseMode").IsChecked == true,
                "Chinese startup mode did not survive reopening");
            VerifyUpdateShutdownProtection(chineseReopened);
            VerifyDiagnosticSwitch(chineseReopened);
            chineseReopened.Close();
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
