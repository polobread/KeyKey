namespace KeyKeySettings;

internal static class InputMethodSettings
{
    internal static readonly string[] Identifiers =
        ["SmartMandarin", "TraditionalMandarin", "Generic-cj-cin", "Generic-simplex-cin"];

    internal static string SelectVisible(string primary, IEnumerable<string> visible)
    {
        var enabled = visible.Where(Identifiers.Contains).ToHashSet(StringComparer.Ordinal);
        if (enabled.Count == 0) throw new InvalidOperationException("請至少顯示一種輸入法");
        return enabled.Contains(primary) ? primary : Identifiers.First(enabled.Contains);
    }

    internal static bool ReadComposeWhileTyping(string path)
    {
        if (SettingsStore.Read(path, "ComposeWhenTypingMigrated", "false") != "true")
        {
            var legacy = SettingsStore.Read(path, "ComposeWhenTyping", "");
            if (legacy.Length > 0) return legacy is "true" or "1" or "YES";
        }
        return SettingsStore.Read(path, "ComposeWhileTyping", "false") is "true" or "1" or "YES";
    }
}
