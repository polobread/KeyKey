using System.Globalization;
using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace KeyKeySettings;

internal readonly record struct DiagnosticSession(long StartedAtUtc, long ExpiresAtUtc)
{
    internal const long DurationSeconds = 3 * 24 * 60 * 60;
    internal bool ActiveAt(long now) => StartedAtUtc > 0 && ExpiresAtUtc > StartedAtUtc &&
        ExpiresAtUtc - StartedAtUtc == DurationSeconds && now >= StartedAtUtc && now < ExpiresAtUtc;
    internal bool Active => ActiveAt(DateTimeOffset.UtcNow.ToUnixTimeSeconds());
}

internal static class DiagnosticSettings
{
    internal static string Path => System.IO.Path.Combine(
        Environment.GetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR") is { Length: > 0 } testDirectory
            ? testDirectory : System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "chichi77 KeyKey"),
        "diagnostics.plist");

    internal static DiagnosticSession Read()
    {
        try
        {
            if (!File.Exists(Path) || new FileInfo(Path).Length > 16384) return default;
            using var reader = XmlReader.Create(Path, new XmlReaderSettings {
                DtdProcessing = DtdProcessing.Ignore, XmlResolver = null });
            var elements = XDocument.Load(reader).Root?.Element("dict")?.Elements().ToArray() ?? [];
            long Number(string key)
            {
                for (var i = 0; i + 1 < elements.Length; ++i)
                    if (elements[i].Name == "key" && elements[i].Value == key && elements[i + 1].Name == "string")
                        return long.TryParse(elements[i + 1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var value) ? value : 0;
                return 0;
            }
            return new(Number("StartedAtUtc"), Number("ExpiresAtUtc"));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or XmlException) { return default; }
    }

    internal static DiagnosticSession Save(bool enabled)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var session = enabled ? new DiagnosticSession(now, now + DiagnosticSession.DurationSeconds) : default;
        SettingsWrite(session);
        return session;
    }

    private static void SettingsWrite(DiagnosticSession session)
    {
        var document = new XDocument(new XElement("plist", new XAttribute("version", "1.0"),
            new XElement("dict", new XElement("key", "StartedAtUtc"),
                new XElement("string", session.StartedAtUtc.ToString(CultureInfo.InvariantCulture)),
                new XElement("key", "ExpiresAtUtc"),
                new XElement("string", session.ExpiresAtUtc.ToString(CultureInfo.InvariantCulture)))));
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var temporary = Path + ".tmp." + Environment.ProcessId;
        try { document.Save(temporary); File.Move(temporary, Path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    // Deployment operations already hold their global deployment mutex.
    internal static void AppendDeploymentLog(string path, string message)
    {
        if (!Read().Active) return;
        var line = $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}";
        const long limit = 1024 * 1024;
        if (System.Text.Encoding.UTF8.GetByteCount(line) > limit) return;
        if (File.Exists(path) && new FileInfo(path).Length + System.Text.Encoding.UTF8.GetByteCount(line) > limit)
            File.WriteAllText(path, "");
        File.AppendAllText(path, line);
    }
}
