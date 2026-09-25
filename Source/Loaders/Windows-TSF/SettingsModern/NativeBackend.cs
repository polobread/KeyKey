using System.Runtime.InteropServices;
using System.Text;
using System.IO;

namespace KeyKeySettings;

internal static class NativeBackend
{
    private const string Library = "KeyKeySettingsBackend.dll";

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
