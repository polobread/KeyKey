using System.Runtime.InteropServices;
using System.Text;
using System.IO;

namespace KeyKeySettings;

internal static class NativeBackend
{
    private const string Library = "KeyKeySettingsBackend.dll";
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int KeyKeyReadSimplifiedOutput();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int KeyKeyPublishSimplifiedOutput(int enabled);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int KeyKeyPublishDefaultChineseMode(int enabled);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern IntPtr KeyKeyLookupReadings(string path, string phrase, out int status);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern void KeyKeyFreeReadings(IntPtr handle);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern int KeyKeyReadingCount(IntPtr handle, int character);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyReadingAt(IntPtr handle, int character, int index, StringBuilder? target, int capacity);

    public static ReadingLookup LookupReadings(string phrase)
    {
        var handle = KeyKeyLookupReadings(Path.Combine(AppContext.BaseDirectory, "Databases", "KeyKey.db"), phrase, out var status);
        try
        {
            if (handle == IntPtr.Zero) return new(status, [], []);
            string Read(int character, int index)
            {
                int required = KeyKeyReadingAt(handle, character, index, null, 0);
                if (required <= 0 || required > 4096) throw new InvalidDataException("讀音資料長度無效。");
                var buffer = new StringBuilder(required);
                if (KeyKeyReadingAt(handle, character, index, buffer, required) != required)
                    throw new InvalidDataException("讀音查詢資料已變更。");
                return buffer.ToString();
            }
            var whole = new List<string>();
            for (int i = 0; i < KeyKeyReadingCount(handle, -1); ++i) whole.Add(Read(-1, i));
            var characters = new List<CharacterReadings>();
            for (int i = 0; i < KeyKeyReadingCount(handle, -2); ++i)
            {
                var choices = new List<string>();
                for (int j = 0; j < KeyKeyReadingCount(handle, i); ++j) choices.Add(Read(i, j));
                characters.Add(new(Read(i, -1), choices));
            }
            return new(status, whole, characters);
        }
        finally { if (handle != IntPtr.Zero) KeyKeyFreeReadings(handle); }
    }

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern int KeyKeyLoadPhrases();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyPhraseAt(int index, out long rowid,
        StringBuilder text, int textCapacity, StringBuilder reading, int readingCapacity);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    public static extern int KeyKeySavePhrase(long rowid, string text, string reading);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int KeyKeyDeletePhrase(long rowid);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int KeyKeyResetLearning();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    public static extern int KeyKeyImportUserData(string path);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    public static extern int KeyKeyExportUserData(string path);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyLoadCollections(string path);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyCollectionAt(int index,
        StringBuilder source, int sourceCapacity, StringBuilder display, int displayCapacity);

    public static IReadOnlyList<PhraseRow> LoadPhrases()
    {
        var rows = new List<PhraseRow>();
        var count = KeyKeyLoadPhrases();
        for (var i = 0; i < count; i++)
        {
            var text = new StringBuilder(4096);
            var reading = new StringBuilder(4096);
            if (KeyKeyPhraseAt(i, out var rowid, text, text.Capacity, reading, reading.Capacity) != 0)
                rows.Add(new PhraseRow(rowid, text.ToString(), reading.ToString()));
        }
        return rows;
    }

    public static IReadOnlyList<CollectionRow> LoadCollections()
    {
        var rows = new List<CollectionRow>();
        var path = Path.Combine(AppContext.BaseDirectory, "Databases", "KeyKey.db");
        var count = KeyKeyLoadCollections(path);
        for (var i = 0; i < count; i++)
        {
            var source = new StringBuilder(512);
            var display = new StringBuilder(512);
            if (KeyKeyCollectionAt(i, source, source.Capacity, display, display.Capacity) != 0)
                rows.Add(new CollectionRow(source.ToString(), display.ToString()));
        }
        return rows;
    }
}

internal sealed record PhraseRow(long RowId, string Text, string Reading);
internal sealed record CharacterReadings(string Text, IReadOnlyList<string> Readings);
internal sealed record ReadingLookup(int Status, IReadOnlyList<string> WholePhraseReadings, IReadOnlyList<CharacterReadings> Characters);

internal sealed class CollectionRow : System.ComponentModel.INotifyPropertyChanged
{
    private bool enabled;
    public CollectionRow(string source, string display) { Source = source; Display = display; }
    public string Source { get; }
    public string Display { get; }
    public bool Enabled
    {
        get => enabled;
        set { if (enabled == value) return; enabled = value;
            PropertyChanged?.Invoke(this, new(nameof(Enabled))); }
    }
    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
}
