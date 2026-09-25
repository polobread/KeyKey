using KeyKeySettings;

var file = Path.Combine(Path.GetTempPath(), "keykey-settings-test-" + Guid.NewGuid().ToString("N") + ".plist");
try
{
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
    File.WriteAllText(legacy, "existing preferences");
    File.WriteAllText(Path.Combine(migrationDirectory,
        "org.openvanilla.chichi77-keykey.windows.TraditionalMandarin.plist"),
        "traditional preferences");
    SettingsStore.MigrateLegacyPreferences(migrationDirectory);
    if (File.ReadAllText(current) != "existing preferences" ||
        File.ReadAllText(Path.Combine(migrationDirectory,
            "com.polobread.chichi77-keykey.windows.TraditionalMandarin.plist"))
            != "traditional preferences" ||
        !File.Exists(legacy))
        throw new Exception("舊設定搬移測試失敗");
    File.WriteAllText(current, "new preferences");
    SettingsStore.MigrateLegacyPreferences(migrationDirectory);
    if (File.ReadAllText(current) != "new preferences")
        throw new Exception("新設定不應被舊設定覆寫");
    Console.WriteLine("Settings migration passed");
}
finally { Directory.Delete(migrationDirectory, true); }
