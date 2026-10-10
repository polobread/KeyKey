using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace KeyKeySettings;

internal static class SharedSettingsFile
{
    internal static string LockName(string path)
    {
        ulong hash=14695981039346656037;
        foreach (var original in System.IO.Path.GetFullPath(path))
        {
            var value=original=='/' ? '\\' : original;
            if (value is >= 'A' and <= 'Z') value=(char)(value+'a'-'A');
            hash=unchecked((hash^value)*1099511628211);
        }
        return @"Local\chichi77.KeyKey.Settings."+hash.ToString(CultureInfo.InvariantCulture);
    }
    internal sealed class Lease : IDisposable
    {
        private readonly Mutex mutex;
        private bool acquired;
        internal Lease(string path)
        {
            mutex=new Mutex(false,LockName(path));
            try { acquired=mutex.WaitOne(TimeSpan.FromSeconds(5)); }
            catch (AbandonedMutexException) { acquired=true; }
            if (!acquired) { mutex.Dispose(); throw new IOException("另一個程式正在儲存設定，請稍後重試。"); }
        }
        public void Dispose() { if (acquired) { acquired=false; mutex.ReleaseMutex(); mutex.Dispose(); } }
    }
    internal static Lease Lock(string path) => new(path);
    internal static FileStream OpenRead(string path) => new(path,FileMode.Open,FileAccess.Read,
        FileShare.ReadWrite|FileShare.Delete);

    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileEx(string source,string target,uint flags);

    // Caller holds the shared lock through reading and editing the latest file.
    internal static void Write(string path,string text)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path))!);
        var previous=File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
        var temporary=path+".tmp."+Environment.ProcessId+"."+Guid.NewGuid().ToString("N");
        try
        {
            using (var stream=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {
                var bytes=new UTF8Encoding(false).GetBytes(text);
                stream.Write(bytes); stream.Flush(true);
            }
            var now=DateTime.UtcNow;
            File.SetLastWriteTimeUtc(temporary,now>previous.AddSeconds(1) ? now : previous.AddSeconds(1));
            if (OperatingSystem.IsWindows())
            {
                if (!MoveFileEx(temporary,path,1|8)) throw new IOException("無法替換設定檔。",new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()));
            }
            else File.Move(temporary,path,true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
