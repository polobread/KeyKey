using KeyKeySettings;

if (args.Length==4 && args[0]=="--hold-lock")
{
    using var lease=SharedSettingsFile.Lock(args[1]);
    File.WriteAllText(args[2],"ready");
    var timeout=DateTime.UtcNow.AddSeconds(10);
    while (!File.Exists(args[3]) && DateTime.UtcNow<timeout) Thread.Sleep(10);
    if (!File.Exists(args[3])) throw new Exception("共享設定鎖測試逾時");
    return;
}
if (args.Length==4 && args[0]=="--writer")
{
    for (var i=1;i<=int.Parse(args[3]);++i)
        SettingsStore.Write(args[1],new Dictionary<string,string> { [args[2]]=i.ToString(System.Globalization.CultureInfo.InvariantCulture) });
    return;
}

var file = Path.Combine(Path.GetTempPath(), "keykey-settings-test-" + Guid.NewGuid().ToString("N") + ".plist");
try
{
    var previousProfile = Environment.GetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR");
    var diagnosticDirectory = file + "-diagnostics";
    Directory.CreateDirectory(diagnosticDirectory);
    Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", diagnosticDirectory);
    try
    {
        if (DiagnosticSettings.Read().Active) throw new Exception("診斷記錄應預設關閉");
        var session = DiagnosticSettings.Save(true);
        if (!DiagnosticSettings.Read().Active || session.ExpiresAtUtc - session.StartedAtUtc != 3 * 86400 ||
            session.ActiveAt(session.ExpiresAtUtc) || session.ActiveAt(session.StartedAtUtc - 1) ||
            !session.ActiveAt(session.ExpiresAtUtc - 1)) throw new Exception("診斷記錄期限不正確");
        if (new DiagnosticSession(session.StartedAtUtc, session.StartedAtUtc + 4 * 86400).Active)
            throw new Exception("診斷記錄不應接受超過 3 天的期限");
        if (DiagnosticSettings.Save(true) != session)
            throw new Exception("其他設定程序不應延長現有診斷期限");
        DiagnosticSettings.Save(false);
        if (DiagnosticSettings.Read().Active) throw new Exception("手動關閉診斷記錄失敗");
        File.WriteAllText(DiagnosticSettings.Path, "invalid XML");
        if (DiagnosticSettings.Read().Active) throw new Exception("無效診斷設定應視為關閉");
        Console.WriteLine("Diagnostics default-off, manual toggle and three-day expiry passed");
    }
    finally
    {
        Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", previousProfile);
        File.Delete(Path.Combine(diagnosticDirectory, "diagnostics.plist"));
        Directory.Delete(diagnosticDirectory);
    }
    if (SmartMandarinSettings.Validate("asdfjkl;", "20") != 20) throw new Exception("自訂選字鍵／長度驗證失敗");
    if (SmartMandarinSettings.Validate("", "10") != 10) throw new Exception("鍵盤配置自動選字鍵未保留");
    foreach (var invalid in new[] { ("12345677", "10"), ("1234567 ", "10"), ("12345678", "9"), ("12345678", "21"), ("12345678", "10.0"), ("１２３４５６７８", "10") }) {
        bool rejected = false;
        try { SmartMandarinSettings.Validate(invalid.Item1, invalid.Item2); }
        catch (ArgumentException) { rejected = true; }
        if (!rejected) throw new Exception("無效進階設定未拒絕");
    }
    File.WriteAllText(file, """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>PrimaryInputMethod</key><string>TraditionalMandarin</string>
          <key>ActivatedAroundFilters</key><array><string>ExistingFilter</string></array>
        </dict></plist>
        """);
    var before = File.GetLastWriteTimeUtc(file);
    SettingsStore.Write(file, new Dictionary<string, string> {
        ["PrimaryInputMethod"] = "SmartMandarin",
        ["UseCharactersSupportedByEncoding"] = "",
    });
    SettingsStore.WriteArray(file, "ModulesSuppressedFromUI", ["TraditionalMandarin"]);
    var text = File.ReadAllText(file);
    if (SettingsStore.Read(file, "PrimaryInputMethod", "") != "SmartMandarin" ||
        SettingsStore.Read(file, "UseCharactersSupportedByEncoding", "missing") != "" ||
        !text.Contains("<array>") || !text.Contains("ExistingFilter") ||
        !SettingsStore.ReadArray(file, "ModulesSuppressedFromUI")
            .SequenceEqual(["TraditionalMandarin"]) ||
        !text.Contains("<string></string>") || text.Contains("DOCTYPE") ||
        File.GetLastWriteTimeUtc(file) <= before)
        throw new Exception("設定檔往返測試失敗");
    Console.WriteLine("Settings plist round-trip passed");

    SettingsStore.Write(file, new Dictionary<string, string> {
        ["ClearComposingTextWithEsc"] = "true",
    });
    if (SettingsStore.ReadSmartEscClearPreference(file))
        throw new Exception("舊版自動儲存的 Esc=true 不應清除整句");
    SettingsStore.Write(file, new Dictionary<string, string> {
        ["ClearComposingTextWithEscUserChoice"] = "true",
    });
    if (!SettingsStore.ReadSmartEscClearPreference(file))
        throw new Exception("使用者明確選擇 Esc 清句未生效");
    SettingsStore.Write(file, new Dictionary<string, string> {
        ["ClearComposingTextWithEsc"] = "false",
    });
    if (SettingsStore.ReadSmartEscClearPreference(file))
        throw new Exception("使用者關閉 Esc 清句未生效");
    Console.WriteLine("Smart Mandarin Esc preference migration passed");

    SettingsStore.Write(file, new Dictionary<string, string> {
        ["ComposeWhileTyping"] = "false",
        ["ComposeWhenTyping"] = "true",
    });
    if (!InputMethodSettings.ReadComposeWhileTyping(file))
        throw new Exception("簡易舊鍵名未覆蓋舊版自動產生的預設值");
    SettingsStore.Write(file, new Dictionary<string, string> {
        ["ComposeWhenTypingMigrated"] = "true",
        ["ComposeWhileTyping"] = "false",
    });
    if (InputMethodSettings.ReadComposeWhileTyping(file))
        throw new Exception("舊鍵名覆蓋了新版明確選擇");
    Console.WriteLine("Simplex legacy compose alias passed");

    // All non-empty subsets must keep an enabled selection. Unknown modules
    // cannot satisfy the requirement to retain one of our four input methods.
    for (var mask = 1; mask < 16; mask++)
    {
        var visible = InputMethodSettings.Identifiers.Where((_, index) =>
            (mask & (1 << index)) != 0).ToArray();
        foreach (var primary in InputMethodSettings.Identifiers.Append("Unknown"))
        {
            var selected = InputMethodSettings.SelectVisible(primary, visible);
            if (!visible.Contains(selected) || (visible.Contains(primary) && selected != primary))
                throw new Exception("顯示模式與目前模式不一致");
        }
    }
    try {
        InputMethodSettings.SelectVisible("Generic-cj-cin", ["Unknown"]);
        throw new Exception("允許隱藏全部輸入法");
    } catch (InvalidOperationException) { }
    Console.WriteLine("All four-mode visibility combinations passed");
}
finally { if (File.Exists(file)) File.Delete(file); }

var migrationDirectory = Path.Combine(Path.GetTempPath(),
    "keykey-settings-migration-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(migrationDirectory);
try
{
    var legacy = Path.Combine(migrationDirectory,
        "org.openvanilla.chichi77-keykey.windows.plist");
    var current = Path.Combine(migrationDirectory,
        "com.polobread.chichi77-keykey.windows.plist");
    string Preference(string value) => $"<plist><dict><key>Value</key><string>{value}</string></dict></plist>";
    File.WriteAllText(legacy, Preference("existing preferences"));
    File.WriteAllText(Path.Combine(migrationDirectory,
        "org.openvanilla.chichi77-keykey.windows.TraditionalMandarin.plist"),
        Preference("traditional preferences"));
    foreach (var suffix in new[] { "Generic-cj-cin", "Generic-simplex-cin" })
        File.WriteAllText(Path.Combine(migrationDirectory,
            $"org.openvanilla.chichi77-keykey.windows.{suffix}.plist"), Preference(suffix));
    var malformedLegacy=Path.Combine(migrationDirectory, "org.openvanilla.chichi77-keykey.windows.SmartMandarin.plist");
    File.WriteAllText(malformedLegacy,"<plist><dict><key>unfinished");
    SettingsStore.MigrateLegacyPreferences(migrationDirectory);
    if (File.ReadAllText(current) != Preference("existing preferences") ||
        File.ReadAllText(Path.Combine(migrationDirectory,
            "com.polobread.chichi77-keykey.windows.TraditionalMandarin.plist"))
            != Preference("traditional preferences") ||
        !File.Exists(legacy))
        throw new Exception("舊設定搬移測試失敗");
    if (File.Exists(Path.Combine(migrationDirectory,"com.polobread.chichi77-keykey.windows.SmartMandarin.plist")) ||
        File.ReadAllText(malformedLegacy)!="<plist><dict><key>unfinished")
        throw new Exception("損壞的舊設定應保留且不遷移");
    File.WriteAllText(current, "new preferences");
    SettingsStore.MigrateLegacyPreferences(migrationDirectory);
    if (File.ReadAllText(current) != "new preferences")
        throw new Exception("新設定不應被舊設定覆寫");
    Console.WriteLine("Settings migration passed");
    foreach (var suffix in new[] { "Generic-cj-cin", "Generic-simplex-cin" })
    {
        var migrated = Path.Combine(migrationDirectory,
            $"com.polobread.chichi77-keykey.windows.{suffix}.plist");
        if (File.ReadAllText(migrated) != Preference(suffix))
            throw new Exception("倉頡／簡易設定未遷移");
        File.WriteAllText(migrated, "current");
        SettingsStore.MigrateLegacyPreferences(migrationDirectory);
        if (File.ReadAllText(migrated) != "current")
            throw new Exception("倉頡／簡易新版設定被覆寫");
    }
    Console.WriteLine("Cangjie and Simplex preference migration passed");
}
finally { Directory.Delete(migrationDirectory, true); }
