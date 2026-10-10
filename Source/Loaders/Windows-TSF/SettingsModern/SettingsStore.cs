using System.IO;
using System.Xml;
using System.Xml.Linq;

namespace KeyKeySettings;

internal static class SettingsStore
{
    private const string CurrentPrefix = "com.polobread.chichi77-keykey.windows";
    private const string LegacyPrefix = "org.openvanilla.chichi77-keykey.windows";
    private static readonly string DirectoryPath =
        Environment.GetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR") is { Length: > 0 } testDirectory
            ? testDirectory : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "chichi77 KeyKey");
    private static readonly Lazy<bool> Migrated = new(() => {
        MigrateLegacyPreferences(DirectoryPath);
        return true;
    });

    public static string LoaderPath => PreferencePath("");
    public static string TraditionalPath => PreferencePath(".TraditionalMandarin");
    public static string SmartPath => PreferencePath(".SmartMandarin");
    public static string AssociatedPath => PreferencePath(".AssociatedPhrase");
    public static string CangjiePath => PreferencePath(".Generic-cj-cin");
    public static string SimplexPath => PreferencePath(".Generic-simplex-cin");

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
                     ".AssociatedPhrase", ".Generic-cj-cin", ".Generic-simplex-cin" })
        {
            var current = Path.Combine(directory, CurrentPrefix + suffix + ".plist");
            var legacy = Path.Combine(directory, LegacyPrefix + suffix + ".plist");
            if (File.Exists(legacy) && !File.Exists(current))
            {
                using var lease=SharedSettingsFile.Lock(current);
                if (File.Exists(current)) continue;
                using var stream=SharedSettingsFile.OpenRead(legacy);
                using var reader=new StreamReader(stream);
                var source=reader.ReadToEnd();
                try {
                    if (XDocument.Parse(source).Root?.Element("dict") is not null) SharedSettingsFile.Write(current,source);
                } catch (XmlException) { /* Keep malformed legacy files for recovery. */ }
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
        using var lease=SharedSettingsFile.Lock(path);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
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
        using var lease=SharedSettingsFile.Lock(path);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
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
        SharedSettingsFile.Write(path,document.ToString());
    }

    private static XDocument Open(string path)
    {
        using var stream=SharedSettingsFile.OpenRead(path);
        using var reader = XmlReader.Create(stream, new XmlReaderSettings {
            DtdProcessing = DtdProcessing.Ignore, XmlResolver = null });
        return XDocument.Load(reader);
    }
}
