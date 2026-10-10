using System.Collections.ObjectModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Microsoft.Win32;

namespace KeyKeySettings;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<CollectionRow> collections = new();
    private readonly List<ComboBox> readingChoices = new();
    private bool updatingReadings;
    private bool trackingUpdateChanges;
    private bool unsavedSettings;
    private bool diagnosticsEdited;
    private DiagnosticSession diagnosticSession;
    private readonly System.Windows.Threading.DispatcherTimer diagnosticTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private string savedPhraseText = "";
    private string savedPhraseReading = "";
    private static readonly string[] Scales =
        ["system", "75", "90", "100", "125", "150", "175", "200", "225", "250", "300", "350"];
    private static readonly string[] Colors = ["Default", "Green", "Yellow", "Red"];
    private static readonly string[] Layouts = ["Standard", "ETen", "ETen26", "Hsu", "Hanyu Pinyin"];
    private static readonly string[] PunctuationTables =
        ["", "Punctuations-cj-mixedwidth-cin", "Punctuations-cj-halfwidth-cin"];

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wparam,
        string lparam, uint flags, uint timeout, out IntPtr result);

    public MainWindow()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            App.Updater.Initialize();
            UpdateStatus.Text = App.Updater.Status;
            CheckUpdate.IsEnabled = AutomaticUpdates.IsEnabled = App.Updater.Available;
            AutomaticUpdates.IsChecked = App.Updater.Automatic;
        };
        AddHandler(TextBox.TextChangedEvent, new TextChangedEventHandler(UpdateSettingsChanged));
        AddHandler(ToggleButton.CheckedEvent, new RoutedEventHandler(UpdateSettingsChanged));
        AddHandler(ToggleButton.UncheckedEvent, new RoutedEventHandler(UpdateSettingsChanged));
        AddHandler(Selector.SelectionChangedEvent, new SelectionChangedEventHandler(UpdateSettingsChanged));
        CandidateScale.ItemsSource = new[] { "跟隨 Windows（預設）" }
            .Concat(Scales.Skip(1).Select(s => s + "%")).ToArray();
        HighlightColor.ItemsSource = new[] { "紫色", "綠色", "黃色", "紅色" };
        PhoneticLayout.ItemsSource = new[] { "標準", "倚天", "倚天 26 鍵", "許氏鍵盤", "漢語拼音" };
        CangjiePunctuation.ItemsSource = new[] { "字表預設（全形）", "混合全半形", "半形" };

        try
        {
            LoadSettings();
            LoadCollections();
            RefreshPhrases();
        }
        catch (Exception ex)
        {
            Status.Text = $"讀取設定失敗：{ex.Message}";
        }
        CapturePhraseEditor();
        trackingUpdateChanges = true;
        diagnosticTimer.Tick += (_, _) =>
        {
            if (diagnosticsEdited) return;
            var active = diagnosticSession.Active;
            if (DiagnosticLogging.IsChecked != active)
            {
                trackingUpdateChanges = false;
                DiagnosticLogging.IsChecked = active;
                trackingUpdateChanges = true;
            }
            UpdateDiagnosticStatus();
        };
        diagnosticTimer.Start();
        Closed += (_, _) => diagnosticTimer.Stop();
        UpdateShutdownProtection();
    }

    private void LoadSettings()
    {
        var loader = SettingsStore.LoaderPath;
        diagnosticSession = DiagnosticSettings.Read();
        DiagnosticLogging.IsChecked = diagnosticSession.Active;
        UpdateDiagnosticStatus();
        VerticalCandidate.IsChecked = SettingsStore.Read(loader,
            "OneDimensionalCandidatePanelStyle", "vertical") != "horizontal";
        HorizontalCandidate.IsChecked = !VerticalCandidate.IsChecked;
        SelectValue(CandidateScale, Scales,
            SettingsStore.Read(loader, "CandidateWindowScalePercent", "system"));
        SelectValue(HighlightColor, Colors,
            SettingsStore.Read(loader, "HighlightColor", "Default"));
        ControlBackslash.IsChecked = ReadBool(loader, "ToggleInputMethodWithControlBackslash", true);
        TypingBeep.IsChecked = ReadBool(loader, "ShouldPlaySoundOnTypingError", true);
        DefaultChineseMode.IsChecked = SettingsStore.Read(loader, "DefaultInputMode", "Chinese") != "English";
        DefaultEnglishMode.IsChecked = !DefaultChineseMode.IsChecked;
        SimplifiedChineseOutput.IsChecked = ReadBool(loader, "SimplifiedChineseOutput", false);
        var sharedOutput = NativeBackend.KeyKeyReadSimplifiedOutput();
        if (sharedOutput >= 0) SimplifiedChineseOutput.IsChecked = sharedOutput != 0;
        ShowCandidateListWithSpace.IsChecked = ReadBool(SettingsStore.SmartPath, "ShowCandidateListWithSpace", false);
        CandidateCursorAtEndOfTargetBlock.IsChecked = ReadBool(SettingsStore.SmartPath, "CandidateCursorAtEndOfTargetBlock", false);
        CandidateSelectionKeys.Text = SettingsStore.Read(SettingsStore.SmartPath, "CandidateSelectionKeys", "");
        ComposingTextBufferSize.Text = SettingsStore.Read(SettingsStore.SmartPath, "ComposingTextBufferSize", "10");
        var suppressed = SettingsStore.ReadArray(loader, "ModulesSuppressedFromUI")
            .ToHashSet(StringComparer.Ordinal);
        ShowSmartMandarin.IsChecked = !suppressed.Contains("SmartMandarin");
        ShowTraditionalMandarin.IsChecked = !suppressed.Contains("TraditionalMandarin");
        ShowCangjie.IsChecked = !suppressed.Contains("Generic-cj-cin");
        ShowSimplex.IsChecked = !suppressed.Contains("Generic-simplex-cin");

        var cangjie = SettingsStore.CangjiePath;
        CangjieCommitAtMaximum.IsChecked = ReadBool(cangjie, "ShouldCommitAtMaximumRadicalLength", false);
        CangjieDynamicFrequency.IsChecked = ReadBool(cangjie, "UseDynamicFrequency", false);
        CangjieClearOnError.IsChecked = ReadBool(cangjie, "ClearReadingBufferAtCompositionError", true);
        CangjieComposeWhileTyping.IsChecked = InputMethodSettings.ReadComposeWhileTyping(cangjie);
        CangjieRareCharacters.IsChecked = SettingsStore.Read(cangjie,
            "UseCharactersSupportedByEncoding", "") is "" or "UTF-8";
        SelectValue(CangjiePunctuation, PunctuationTables,
            SettingsStore.Read(cangjie, "UseOverrideTable", ""));
        var simplex = SettingsStore.SimplexPath;
        SimplexClearOnError.IsChecked = ReadBool(simplex, "ClearReadingBufferAtCompositionError", true);
        SimplexComposeWhileTyping.IsChecked = InputMethodSettings.ReadComposeWhileTyping(simplex);
        SimplexRareCharacters.IsChecked = SettingsStore.Read(simplex,
            "UseCharactersSupportedByEncoding", "") is "" or "UTF-8";

        var phonetic = SettingsStore.TraditionalPath;
        SelectValue(PhoneticLayout, Layouts,
            SettingsStore.Read(phonetic, "KeyboardLayout", "Standard"));
        RareCharacters.IsChecked = SettingsStore.Read(phonetic,
            "UseCharactersSupportedByEncoding", "BIG-5") is "" or "UTF-8";
        ClearSmartCompositionWithEsc.IsChecked =
            SettingsStore.ReadSmartEscClearPreference(SettingsStore.SmartPath);
    }

    private void CheckUpdate_Click(object sender, RoutedEventArgs e) => App.Updater.Check();
    private void DiagnosticLogging_Changed(object sender, RoutedEventArgs e)
    {
        if (trackingUpdateChanges) diagnosticsEdited = true;
        UpdateDiagnosticStatus();
    }

    private void UpdateDiagnosticStatus()
    {
        if (DiagnosticStatus == null) return;
        DiagnosticStatus.Text = DiagnosticLogging.IsChecked == true
            ? diagnosticsEdited ? "套用後開始記錄，3 天後自動關閉。"
                : $"記錄中，將於 {DateTimeOffset.FromUnixTimeSeconds(diagnosticSession.ExpiresAtUtc).ToLocalTime():yyyy/MM/dd HH:mm} 自動關閉。"
            : diagnosticSession.StartedAtUtc > 0 && !diagnosticSession.Active && !diagnosticsEdited
                ? "診斷記錄已到期，自動關閉。" : diagnosticsEdited ? "套用後停止記錄。" : "診斷記錄已關閉。";
    }
    private void UpdateSettingsChanged(object sender, RoutedEventArgs e)
    {
        if (!trackingUpdateChanges) return;
        // Phrase text/readings are saved by their own buttons. Selection, reading
        // lookup and tab navigation must not mark the general settings as edited.
        var source = e.OriginalSource;
        if (source == CandidateSelectionKeys || source == ComposingTextBufferSize ||
            source == CandidateScale || source == HighlightColor ||
            source == PhoneticLayout || source == CangjiePunctuation ||
            source is ToggleButton toggle && (toggle is CheckBox or RadioButton) && toggle != AutomaticUpdates &&
                toggle.DataContext is not CollectionRow)
            unsavedSettings = true;
        UpdateShutdownProtection();
    }

    private void CapturePhraseEditor()
    {
        savedPhraseText = PhraseText.Text;
        savedPhraseReading = PhraseReading.Text;
        UpdateShutdownProtection();
    }

    private void UpdateShutdownProtection() => App.Updater.SetUnsavedChanges(
        unsavedSettings || PhraseText.Text != savedPhraseText || PhraseReading.Text != savedPhraseReading);
    private void AutomaticUpdates_Changed(object sender, RoutedEventArgs e) =>
        App.Updater.SetAutomatic(AutomaticUpdates.IsChecked == true);

    private void LoadCollections()
    {
        collections.Clear();
        var enabled = SettingsStore.Read(SettingsStore.AssociatedPath,
            "EnabledCollections", "McBopomofo")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToHashSet(StringComparer.Ordinal);
        foreach (var row in NativeBackend.LoadCollections())
        {
            row.Enabled = enabled.Contains(row.Source);
            row.PropertyChanged += (_, _) =>
            {
                if (!trackingUpdateChanges) return;
                unsavedSettings = true;
                UpdateShutdownProtection();
            };
            collections.Add(row);
        }
        Collections.ItemsSource = collections;
        if (collections.Count == 0) Status.Text = "找不到 Databases\\KeyKey.db 或詞庫清單";
    }

    private void RefreshPhrases()
    {
        UserPhrases.ItemsSource = NativeBackend.LoadPhrases();
    }

    private static void SelectValue(ComboBox box, string[] values, string value)
    {
        var index = Array.IndexOf(values, value);
        box.SelectedIndex = index >= 0 ? index : 0;
    }

    private static bool ReadBool(string path, string key, bool fallback)
        => SettingsStore.Read(path, key, fallback ? "true" : "false") is "true" or "1" or "YES";

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var bufferSize = SmartMandarinSettings.Validate(CandidateSelectionKeys.Text, ComposingTextBufferSize.Text);
            var visible = new[] {
                ("SmartMandarin", ShowSmartMandarin.IsChecked == true),
                ("TraditionalMandarin", ShowTraditionalMandarin.IsChecked == true),
                ("Generic-cj-cin", ShowCangjie.IsChecked == true),
                ("Generic-simplex-cin", ShowSimplex.IsChecked == true),
            }.Where(item => item.Item2).Select(item => item.Item1).ToArray();
            var primary = InputMethodSettings.SelectVisible(SettingsStore.Read(
                SettingsStore.LoaderPath, "PrimaryInputMethod", "SmartMandarin"), visible);
            SettingsStore.Write(SettingsStore.LoaderPath, new Dictionary<string, string> {
                ["PrimaryInputMethod"] = primary,
                ["OneDimensionalCandidatePanelStyle"] = HorizontalCandidate.IsChecked == true ? "horizontal" : "vertical",
                ["HighlightColor"] = Colors[Math.Max(0, HighlightColor.SelectedIndex)],
                ["CandidateWindowScalePercent"] = Scales[Math.Max(0, CandidateScale.SelectedIndex)],
                ["ToggleInputMethodWithControlBackslash"] = ControlBackslash.IsChecked == true ? "true" : "false",
                ["ShouldPlaySoundOnTypingError"] = TypingBeep.IsChecked == true ? "true" : "false",
                ["SimplifiedChineseOutput"] = BoolValue(SimplifiedChineseOutput),
                ["DefaultInputMode"] = DefaultEnglishMode.IsChecked == true ? "English" : "Chinese",
            });
            var suppressed = SettingsStore.ReadArray(SettingsStore.LoaderPath,
                "ModulesSuppressedFromUI")
                .Where(id => !InputMethodSettings.Identifiers.Contains(id))
                .ToList();
            suppressed.AddRange(InputMethodSettings.Identifiers.Except(visible));
            SettingsStore.WriteArray(SettingsStore.LoaderPath,
                "ModulesSuppressedFromUI", suppressed);
            var layout = Layouts[Math.Max(0, PhoneticLayout.SelectedIndex)];
            var phoneticValues = new Dictionary<string, string> {
                ["KeyboardLayout"] = layout,
                ["UseCharactersSupportedByEncoding"] = RareCharacters.IsChecked == true ? "UTF-8" : "BIG-5",
            };
            SettingsStore.Write(SettingsStore.TraditionalPath, phoneticValues);
            var smartValues = new Dictionary<string, string>(phoneticValues) {
                ["ShowCandidateListWithSpace"] = BoolValue(ShowCandidateListWithSpace),
                ["CandidateCursorAtEndOfTargetBlock"] = BoolValue(CandidateCursorAtEndOfTargetBlock),
                ["CandidateSelectionKeys"] = CandidateSelectionKeys.Text,
                ["ComposingTextBufferSize"] = bufferSize.ToString(System.Globalization.CultureInfo.InvariantCulture),
                ["ClearComposingTextWithEscUserChoice"] = "true",
                ["ClearComposingTextWithEsc"] =
                    ClearSmartCompositionWithEsc.IsChecked == true ? "true" : "false",
            };
            SettingsStore.Write(SettingsStore.SmartPath, smartValues);
            SettingsStore.Write(SettingsStore.CangjiePath, new Dictionary<string, string> {
                ["MaximumRadicalLength"] = "5",
                ["ShouldCommitAtMaximumRadicalLength"] = BoolValue(CangjieCommitAtMaximum),
                ["UseDynamicFrequency"] = BoolValue(CangjieDynamicFrequency),
                ["ComposeWhileTyping"] = BoolValue(CangjieComposeWhileTyping),
                ["ComposeWhenTypingMigrated"] = "true",
                ["ClearReadingBufferAtCompositionError"] = BoolValue(CangjieClearOnError),
                ["UseCharactersSupportedByEncoding"] = CangjieRareCharacters.IsChecked == true ? "" : "BIG-5",
                ["UseOverrideTable"] = PunctuationTables[Math.Max(0, CangjiePunctuation.SelectedIndex)],
            });
            SettingsStore.Write(SettingsStore.SimplexPath, new Dictionary<string, string> {
                ["MaximumRadicalLength"] = "2",
                ["ShouldCommitAtMaximumRadicalLength"] = "true",
                ["ComposeWhileTyping"] = BoolValue(SimplexComposeWhileTyping),
                ["ComposeWhenTypingMigrated"] = "true",
                ["ClearReadingBufferAtCompositionError"] = BoolValue(SimplexClearOnError),
                ["UseCharactersSupportedByEncoding"] = SimplexRareCharacters.IsChecked == true ? "" : "BIG-5",
            });
            SettingsStore.Write(SettingsStore.AssociatedPath, new Dictionary<string, string> {
                ["EnabledCollections"] = string.Join(',', collections.Where(c => c.Enabled).Select(c => c.Source)),
            });
            // Other settings changes must not extend an existing deadline.
            if (diagnosticsEdited)
            {
                diagnosticSession = DiagnosticSettings.Save(DiagnosticLogging.IsChecked == true);
                diagnosticsEdited = false;
                UpdateDiagnosticStatus();
            }
            SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero,
                "chichi77 KeyKey", 0x0002, 250, out _);
            var outputSynced = NativeBackend.KeyKeyPublishSimplifiedOutput(SimplifiedChineseOutput.IsChecked == true ? 1 : 0) != 0;
            var startupSynced = NativeBackend.KeyKeyPublishDefaultChineseMode(DefaultEnglishMode.IsChecked == true ? 0 : 1) != 0;
            Status.Text = outputSynced && startupSynced
                ? "設定已套用" : "設定已儲存；跨程式狀態同步失敗，請重新開啟輸入法。";
            unsavedSettings = false;
            UpdateShutdownProtection();
        }
        catch (Exception ex) { Status.Text = $"設定儲存失敗：{ex.Message}"; }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
    private void UseNumericSelectionKeys_Click(object sender, RoutedEventArgs e) => CandidateSelectionKeys.Text = "12345678";

    private static string BoolValue(CheckBox box) => box.IsChecked == true ? "true" : "false";

    private void TableCompose_Checked(object sender, RoutedEventArgs e)
    {
        if (sender == CangjieComposeWhileTyping && CangjieClearOnError is not null)
            CangjieClearOnError.IsChecked = false;
        if (sender == SimplexComposeWhileTyping && SimplexClearOnError is not null)
            SimplexClearOnError.IsChecked = false;
    }

    private void TableClear_Checked(object sender, RoutedEventArgs e)
    {
        if (sender == CangjieClearOnError && CangjieComposeWhileTyping is not null)
            CangjieComposeWhileTyping.IsChecked = false;
        if (sender == SimplexClearOnError && SimplexComposeWhileTyping is not null)
            SimplexComposeWhileTyping.IsChecked = false;
    }

    private void EnableAll_Click(object sender, RoutedEventArgs e)
    {
        foreach (var row in collections) row.Enabled = true;
    }

    private void BaseOnly_Click(object sender, RoutedEventArgs e)
    {
        foreach (var row in collections) row.Enabled = row.Source == "McBopomofo";
    }

    private void UserPhrases_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UserPhrases.SelectedItem is PhraseRow row)
        {
            PhraseText.Text = row.Text;
            PhraseReading.Text = row.Reading;
            CapturePhraseEditor();
        }
    }

    private void PhraseText_Changed(object sender, TextChangedEventArgs e)
    {
        if (CharacterReadingPanel is null) return;
        updatingReadings = true;
        CharacterReadingPanel.Children.Clear();
        readingChoices.Clear();
        WholePhraseReadings.ItemsSource = null;
        WholePhraseReadings.Visibility = Visibility.Collapsed;
        ReadingStatus.Text = "";
        updatingReadings = false;
    }

    private void LookupReadings_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var result = NativeBackend.LookupReadings(PhraseText.Text.Trim());
            if (result.Status < 0) {
                ReadingStatus.Text = result.Status == -1 ? "請輸入 1 至 64 個字的詞語。" : "正式詞庫讀取失敗，請確認 Databases\\KeyKey.db。";
                return;
            }
            updatingReadings = true;
            CharacterReadingPanel.Children.Clear();
            readingChoices.Clear();
            WholePhraseReadings.ItemsSource = result.WholePhraseReadings;
            WholePhraseReadings.Visibility = result.WholePhraseReadings.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            WholePhraseReadings.SelectedIndex = result.WholePhraseReadings.Count > 0 ? 0 : -1;
            foreach (var character in result.Characters) {
                var panel = new StackPanel { Margin = new Thickness(0, 0, 12, 8) };
                panel.Children.Add(new TextBlock { Text = character.Text });
                var choice = new ComboBox { IsEditable = true, MinWidth = 100, ItemsSource = character.Readings,
                    SelectedIndex = character.Readings.Count > 0 ? 0 : -1 };
                System.Windows.Automation.AutomationProperties.SetName(choice, character.Text + "的讀音");
                choice.SelectionChanged += (_, _) => SynchronizeReadingChoices();
                choice.AddHandler(TextBox.TextChangedEvent, new TextChangedEventHandler((_, _) => SynchronizeReadingChoices()));
                panel.Children.Add(choice);
                if (character.Readings.Count == 0) panel.Children.Add(new TextBlock { Text = "缺少讀音，請手動補充" });
                readingChoices.Add(choice);
                CharacterReadingPanel.Children.Add(panel);
            }
            updatingReadings = false;
            if (result.WholePhraseReadings.Count > 0) SelectWholePhraseReading(result.WholePhraseReadings[0]);
            else SynchronizeReadingChoices();
            ReadingStatus.Text = result.Characters.Any(c => c.Readings.Count == 0)
                ? "部分字沒有讀音；請補齊後儲存。" : result.WholePhraseReadings.Count > 0
                ? "優先使用詞庫完整詞讀音；可逐字修正。" : "逐字候選僅供參考，請依語境確認破音字。";
        }
        catch (Exception ex) { updatingReadings = false; ReadingStatus.Text = "讀音查詢失敗：" + ex.Message; }
    }

    private void WholePhraseReadings_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!updatingReadings && WholePhraseReadings.SelectedItem is string reading) SelectWholePhraseReading(reading);
    }

    private void SelectWholePhraseReading(string reading)
    {
        updatingReadings = true;
        var syllables = reading.Split(',');
        for (int i = 0; i < readingChoices.Count && i < syllables.Length; ++i) readingChoices[i].Text = syllables[i];
        updatingReadings = false;
        PhraseReading.Text = reading;
    }

    private void SynchronizeReadingChoices()
    {
        if (!updatingReadings) PhraseReading.Text = string.Join(',', readingChoices.Select(c => c.Text.Trim()));
    }

    private void SavePhrase(long rowid)
    {
        try
        {
            var ok = NativeBackend.KeyKeySavePhrase(rowid,
                PhraseText.Text.Trim(), PhraseReading.Text.Trim()) != 0;
            if (ok)
            {
                RefreshPhrases();
                CapturePhraseEditor();
            }
            Status.Text = ok ? "自訂詞已儲存" : "儲存失敗：請檢查詞語、讀音數量與重複項目";
        }
        catch (Exception ex) { Status.Text = $"儲存失敗：{ex.Message}"; }
    }

    private void AddPhrase_Click(object sender, RoutedEventArgs e) => SavePhrase(0);

    private void UpdatePhrase_Click(object sender, RoutedEventArgs e)
    {
        if (UserPhrases.SelectedItem is PhraseRow row) SavePhrase(row.RowId);
        else Status.Text = "請先選取要修改的詞";
    }

    private void DeletePhrase_Click(object sender, RoutedEventArgs e)
    {
        if (UserPhrases.SelectedItem is not PhraseRow row) { Status.Text = "請先選取要刪除的詞"; return; }
        try
        {
            var ok = NativeBackend.KeyKeyDeletePhrase(row.RowId) != 0;
            if (ok) RefreshPhrases();
            Status.Text = ok ? "自訂詞已刪除" : "刪除自訂詞失敗";
        }
        catch (Exception ex) { Status.Text = $"刪除失敗：{ex.Message}"; }
    }

    private void ResetLearning_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "要清除好打注音的選字與前後文學習紀錄嗎？自訂詞與倉頡／簡易排序紀錄會保留。",
                "重設好打注音學習紀錄", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try { Status.Text = NativeBackend.KeyKeyResetLearning() != 0 ? "好打注音學習紀錄已重設" : "重設好打注音學習紀錄失敗"; }
        catch (Exception ex) { Status.Text = $"重設好打注音學習紀錄失敗：{ex.Message}"; }
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "SQLite 資料庫 (*.db)|*.db|所有檔案 (*.*)|*.*" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            var ok = NativeBackend.KeyKeyImportUserData(dialog.FileName) != 0;
            if (ok) RefreshPhrases();
            Status.Text = ok ? "使用者資料已匯入" : "匯入失敗：請確認資料庫格式";
        }
        catch (Exception ex) { Status.Text = $"匯入失敗：{ex.Message}"; }
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Filter = "SQLite 資料庫 (*.db)|*.db|所有檔案 (*.*)|*.*",
            DefaultExt = ".db", AddExtension = true };
        if (dialog.ShowDialog(this) != true) return;
        try { Status.Text = NativeBackend.KeyKeyExportUserData(dialog.FileName) != 0
            ? "使用者資料已匯出" : "匯出使用者資料失敗"; }
        catch (Exception ex) { Status.Text = $"匯出失敗：{ex.Message}"; }
    }
}
