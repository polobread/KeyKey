using System.Collections.ObjectModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace KeyKeySettings;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<CollectionRow> collections = new();
    private static readonly string[] Scales =
        ["system", "75", "90", "100", "125", "150", "175", "200", "225", "250", "300", "350"];
    private static readonly string[] Colors = ["Default", "Green", "Yellow", "Red"];
    private static readonly string[] Layouts = ["Standard", "ETen", "ETen26", "Hsu", "Hanyu Pinyin"];

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wparam,
        string lparam, uint flags, uint timeout, out IntPtr result);

    public MainWindow()
    {
        InitializeComponent();
        CandidateScale.ItemsSource = new[] { "跟隨 Windows（預設）" }
            .Concat(Scales.Skip(1).Select(s => s + "%")).ToArray();
        HighlightColor.ItemsSource = new[] { "紫色", "綠色", "黃色", "紅色" };
        PhoneticLayout.ItemsSource = new[] { "標準", "倚天", "倚天 26 鍵", "許氏鍵盤", "漢語拼音" };

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
    }

    private void LoadSettings()
    {
        var loader = SettingsStore.LoaderPath;
        VerticalCandidate.IsChecked = SettingsStore.Read(loader,
            "OneDimensionalCandidatePanelStyle", "vertical") != "horizontal";
        HorizontalCandidate.IsChecked = !VerticalCandidate.IsChecked;
        SelectValue(CandidateScale, Scales,
            SettingsStore.Read(loader, "CandidateWindowScalePercent", "system"));
        SelectValue(HighlightColor, Colors,
            SettingsStore.Read(loader, "HighlightColor", "Default"));
        ControlBackslash.IsChecked = ReadBool(loader, "ToggleInputMethodWithControlBackslash", true);
        TypingBeep.IsChecked = ReadBool(loader, "ShouldPlaySoundOnTypingError", true);
        var suppressed = SettingsStore.ReadArray(loader, "ModulesSuppressedFromUI")
            .ToHashSet(StringComparer.Ordinal);
        ShowSmartMandarin.IsChecked = !suppressed.Contains("SmartMandarin");
        ShowTraditionalMandarin.IsChecked = !suppressed.Contains("TraditionalMandarin");

        var phonetic = SettingsStore.TraditionalPath;
        SelectValue(PhoneticLayout, Layouts,
            SettingsStore.Read(phonetic, "KeyboardLayout", "Standard"));
        RareCharacters.IsChecked = SettingsStore.Read(phonetic,
            "UseCharactersSupportedByEncoding", "BIG-5") is "" or "UTF-8";
        ClearSmartCompositionWithEsc.IsChecked =
            SettingsStore.ReadSmartEscClearPreference(SettingsStore.SmartPath);
    }

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
            if (ShowSmartMandarin.IsChecked != true && ShowTraditionalMandarin.IsChecked != true)
            {
                Status.Text = "請至少顯示一種輸入法";
                return;
            }
            var primary = SettingsStore.Read(SettingsStore.LoaderPath,
                "PrimaryInputMethod", "SmartMandarin");
            if (primary == "SmartMandarin" && ShowSmartMandarin.IsChecked != true)
                primary = "TraditionalMandarin";
            else if (primary == "TraditionalMandarin" && ShowTraditionalMandarin.IsChecked != true)
                primary = "SmartMandarin";
            SettingsStore.Write(SettingsStore.LoaderPath, new Dictionary<string, string> {
                ["PrimaryInputMethod"] = primary,
                ["OneDimensionalCandidatePanelStyle"] = HorizontalCandidate.IsChecked == true ? "horizontal" : "vertical",
                ["HighlightColor"] = Colors[Math.Max(0, HighlightColor.SelectedIndex)],
                ["CandidateWindowScalePercent"] = Scales[Math.Max(0, CandidateScale.SelectedIndex)],
                ["ToggleInputMethodWithControlBackslash"] = ControlBackslash.IsChecked == true ? "true" : "false",
                ["ShouldPlaySoundOnTypingError"] = TypingBeep.IsChecked == true ? "true" : "false",
            });
            var suppressed = SettingsStore.ReadArray(SettingsStore.LoaderPath,
                "ModulesSuppressedFromUI")
                .Where(id => id is not ("SmartMandarin" or "TraditionalMandarin"))
                .ToList();
            if (ShowSmartMandarin.IsChecked != true) suppressed.Add("SmartMandarin");
            if (ShowTraditionalMandarin.IsChecked != true) suppressed.Add("TraditionalMandarin");
            SettingsStore.WriteArray(SettingsStore.LoaderPath,
                "ModulesSuppressedFromUI", suppressed);
            var layout = Layouts[Math.Max(0, PhoneticLayout.SelectedIndex)];
            var phoneticValues = new Dictionary<string, string> {
                ["KeyboardLayout"] = layout,
                ["UseCharactersSupportedByEncoding"] = RareCharacters.IsChecked == true ? "UTF-8" : "BIG-5",
            };
            SettingsStore.Write(SettingsStore.TraditionalPath, phoneticValues);
            var smartValues = new Dictionary<string, string>(phoneticValues) {
                ["ClearComposingTextWithEscUserChoice"] = "true",
                ["ClearComposingTextWithEsc"] =
                    ClearSmartCompositionWithEsc.IsChecked == true ? "true" : "false",
            };
            SettingsStore.Write(SettingsStore.SmartPath, smartValues);
            SettingsStore.Write(SettingsStore.AssociatedPath, new Dictionary<string, string> {
                ["EnabledCollections"] = string.Join(',', collections.Where(c => c.Enabled).Select(c => c.Source)),
            });
            SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero,
                "chichi77 KeyKey", 0x0002, 250, out _);
            Status.Text = "設定已套用";
        }
        catch (Exception ex) { Status.Text = $"設定儲存失敗：{ex.Message}"; }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

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
        }
    }

    private void SavePhrase(long rowid)
    {
        try
        {
            var ok = NativeBackend.KeyKeySavePhrase(rowid,
                PhraseText.Text.Trim(), PhraseReading.Text.Trim()) != 0;
            if (ok) RefreshPhrases();
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
        if (MessageBox.Show(this, "要清除選字與前後文學習紀錄嗎？自訂詞會保留。",
                "重設學習紀錄", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try { Status.Text = NativeBackend.KeyKeyResetLearning() != 0 ? "學習紀錄已重設" : "重設學習紀錄失敗"; }
        catch (Exception ex) { Status.Text = $"重設失敗：{ex.Message}"; }
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
