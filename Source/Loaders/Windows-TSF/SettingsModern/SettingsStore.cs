using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace KeyKeySettings;

internal static class SettingsStore
{
    private const string CurrentPrefix = "com.polobread.chichi77-keykey.windows";
    private const string LegacyPrefix = "org.openvanilla.chichi77-keykey.windows";
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "chichi77 KeyKey");
    private static readonly Lazy<bool> Migrated = new(() => {
        MigrateLegacyPreferences(DirectoryPath);
        return true;
    });

    public static string LoaderPath => PreferencePath("");
    public static string TraditionalPath => PreferencePath(".TraditionalMandarin");
    public static string SmartPath => PreferencePath(".SmartMandarin");
    public static string AssociatedPath => PreferencePath(".AssociatedPhrase");

    internal static bool ReadSmartEscClearPreference(string path)
        => Read(path, "ClearComposingTextWithEscUserChoice", "false") == "true"
           && Read(path, "ClearComposingTextWithEsc", "false") == "true";

    private static string PreferencePath(string suffix)
    {
        _ = Migrated.Value;
        return Path.Combine(DirectoryPath, CurrentPrefix + suffix + ".plist");
    }

    internal static void MigrateLegacyPreferences(string directory)
    {
        Directory.CreateDirectory(directory);
        foreach (var suffix in new[] { "", ".TraditionalMandarin", ".SmartMandarin",
                     ".AssociatedPhrase" })
        {
            var current = Path.Combine(directory, CurrentPrefix + suffix + ".plist");
            var legacy = Path.Combine(directory, LegacyPrefix + suffix + ".plist");
            if (File.Exists(legacy) && !File.Exists(current))
            {
                try { File.Copy(legacy, current, false); }
                catch (IOException) when (File.Exists(current)) { }
            }
        }
    }

    public static string Read(string path, string key, string fallback)
    {
        if (!File.Exists(path)) return fallback;
        var dict = Open(path).Root?.Element("dict");
        if (dict is null) return fallback;
        var elements = dict.Elements().ToArray();
        for (var i = 0; i + 1 < elements.Length; i++)
        {
            if (elements[i].Name.LocalName == "key" && elements[i].Value == key)
                return elements[i + 1].Value;
        }
        return fallback;
    }

    public static IReadOnlyList<string> ReadArray(string path, string key)
    {
        if (!File.Exists(path)) return Array.Empty<string>();
        var dict = Open(path).Root?.Element("dict");
        if (dict is null) return Array.Empty<string>();
        var elements = dict.Elements().ToArray();
        for (var i = 0; i + 1 < elements.Length; i++)
        {
            if (elements[i].Name.LocalName == "key" && elements[i].Value == key &&
                elements[i + 1].Name.LocalName == "array")
                return elements[i + 1].Elements("string").Select(e => e.Value).ToArray();
        }
        return Array.Empty<string>();
    }

    public static void Write(string path, IReadOnlyDictionary<string, string> values)
    {
        Directory.CreateDirectory(DirectoryPath);
        var document = File.Exists(path) ? Open(path) : NewDocument();
        var dict = document.Root?.Element("dict")
            ?? throw new InvalidDataException($"無效的設定檔：{path}");
        foreach (var (key, value) in values)
        {
            SetValue(dict, key, new XElement("string", value));
        }

        Save(path, document);
    }

    public static void WriteArray(string path, string key, IEnumerable<string> values)
    {
        Directory.CreateDirectory(DirectoryPath);
        var document = File.Exists(path) ? Open(path) : NewDocument();
        var dict = document.Root?.Element("dict")
            ?? throw new InvalidDataException($"無效的設定檔：{path}");
        SetValue(dict, key, new XElement("array", values.Select(v => new XElement("string", v))));
        Save(path, document);
    }

    private static void SetValue(XElement dict, string key, XElement value)
    {
        var keyElement = dict.Elements("key").FirstOrDefault(e => e.Value == key);
        if (keyElement is null) dict.Add(new XElement("key", key), value);
        else
        {
            var valueElement = keyElement.ElementsAfterSelf().FirstOrDefault();
            if (valueElement is null) keyElement.AddAfterSelf(value);
            else valueElement.ReplaceWith(value);
        }
    }

    private static XDocument NewDocument() => new(
        new XElement("plist", new XAttribute("version", "1.0"), new XElement("dict")));

    private static void Save(string path, XDocument document)
    {
        var previousTime = File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
        var temporary = path + ".tmp." + Environment.ProcessId;
        try
        {
            using (var stream = File.Create(temporary))
            using (var writer = XmlWriter.Create(stream, new XmlWriterSettings {
                Encoding = new System.Text.UTF8Encoding(false), Indent = true,
                NewLineChars = "\r\n", NewLineHandling = NewLineHandling.Replace }))
                document.Save(writer);
            File.Move(temporary, path, true);
            var now = DateTime.UtcNow;
            if (now <= previousTime.AddSeconds(1)) now = previousTime.AddSeconds(1);
            File.SetLastWriteTimeUtc(path, now);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static XDocument Open(string path)
    {
        using var reader = XmlReader.Create(path, new XmlReaderSettings {
            DtdProcessing = DtdProcessing.Ignore, XmlResolver = null });
        return XDocument.Load(reader);
    }
}
