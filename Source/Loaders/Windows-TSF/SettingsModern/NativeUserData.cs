using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace KeyKeySettings;

// One immutable core binding per settings window; native row snapshots cannot
// accidentally redirect an edit to another core after a preference change.
internal sealed class NativeUserData : SafeHandleZeroOrMinusOneIsInvalid
{
    private const string Library = "KeyKeySettingsBackend.dll";
    private NativeUserData() : base(true) { }
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int KeyKeyGuanyinmaAvailable();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern NativeUserData KeyKeyOpenUserData(int core, string model);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern void KeyKeyCloseUserData(IntPtr handle);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern int KeyKeyUserDataLoad(NativeUserData handle);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyUserDataPhraseAt(NativeUserData handle, int index, out long row,
        StringBuilder text, int textCapacity, StringBuilder reading, int readingCapacity);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyUserDataSave(NativeUserData handle, long row, string text, string reading);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern int KeyKeyUserDataDelete(NativeUserData handle, long row);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    private static extern int KeyKeyUserDataReset(NativeUserData handle);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    private static extern int KeyKeyUserDataArchive(NativeUserData handle, string path, int exportData);
    protected override bool ReleaseHandle() { KeyKeyCloseUserData(handle); return true; }
    internal static NativeUserData Open(bool guanyinma)
    {
        var result = KeyKeyOpenUserData(guanyinma ? 1 : 0, Path.Combine(AppContext.BaseDirectory, "Databases", "KeyKey.db"));
        if (!result.IsInvalid) return result;
        result.Dispose();
        throw new IOException("無法開啟所選核心的使用者詞庫。");
    }
    internal IReadOnlyList<PhraseRow> Load()
    {
        var count = KeyKeyUserDataLoad(this);
        if (count < 0) throw new IOException("無法讀取使用者詞庫。");
        var rows = new List<PhraseRow>();
        for (var index = 0; index < count; ++index)
        {
            var text = new StringBuilder(4096); var reading = new StringBuilder(4096);
            if (KeyKeyUserDataPhraseAt(this, index, out var row, text, text.Capacity, reading, reading.Capacity) == 0)
                throw new IOException("詞庫快照已失效。");
            rows.Add(new(row, text.ToString(), reading.ToString()));
        }
        return rows;
    }
    internal bool Save(long row, string text, string reading) => KeyKeyUserDataSave(this, row, text, reading) != 0;
    internal bool Delete(long row) => KeyKeyUserDataDelete(this, row) != 0;
    internal bool Reset() => KeyKeyUserDataReset(this) != 0;
    internal bool Import(string path) => KeyKeyUserDataArchive(this, path, 0) != 0;
    internal bool Export(string path) => KeyKeyUserDataArchive(this, path, 1) != 0;
}
