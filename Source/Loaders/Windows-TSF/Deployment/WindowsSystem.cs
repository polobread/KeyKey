using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace KeyKey.Deployment;

public sealed class WindowsSystem : IDeploymentSystem
{
    public const string ProductKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\chichi77KeyKey";
    private const string ClassKey = @"Software\Classes\CLSID\{828E3CF0-11E9-45FC-A5DB-394991AD0093}";
    private RegistryView ProductView => Environment.Is64BitOperatingSystem ? RegistryView.Registry64 : RegistryView.Registry32;
    private RegistryView[] Views => Environment.Is64BitOperatingSystem
        ? [RegistryView.Registry64, RegistryView.Registry32] : [RegistryView.Registry32];
    public string Architecture => RuntimeInformation.OSArchitecture switch
    {
        System.Runtime.InteropServices.Architecture.X64 => "x64",
        System.Runtime.InteropServices.Architecture.X86 => "x86", _ => "unsupported"
    };
    public static string DefaultRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "chichi77 KeyKey");
    public void ValidateRoot(string path)
    {
        path = SafeFiles.FullPath(path);
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\") ||
            path.Equals(Path.GetPathRoot(path), StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("A local product directory is required.");
        SafeFiles.NoLinks(path);
        // New installations always use Program Files. Legacy directories must
        // also be dedicated, protected product directories, never a shared root.
        var productRoot = Path.GetFileName(path).Equals("chichi77 KeyKey", StringComparison.OrdinalIgnoreCase)
            ? path : Path.GetDirectoryName(path)!;
        if (!Path.GetFileName(productRoot).Equals("chichi77 KeyKey", StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException($"Unrecognized legacy product directory: {path}");
        var programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!productRoot.StartsWith(SafeFiles.FullPath(programs) + "\\", StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("Legacy installations outside protected Program Files need manual migration.");
        var existing = path;
        while (!Directory.Exists(existing)) existing = Path.GetDirectoryName(existing)!;
        var acl = new DirectoryInfo(existing).GetAccessControl();
        foreach (FileSystemAccessRule rule in acl.GetAccessRules(true, true, typeof(SecurityIdentifier)))
        {
            if (rule.AccessControlType != AccessControlType.Allow ||
                (rule.PropagationFlags & PropagationFlags.InheritOnly) != 0) continue;
            const FileSystemRights write = FileSystemRights.Write | FileSystemRights.Delete |
                FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            if ((rule.FileSystemRights & write) == 0) continue;
            var sid = rule.IdentityReference.Value;
            if (sid != "S-1-5-18" && sid != "S-1-5-32-544" &&
                sid != "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464")
                throw new DeploymentException($"Untrusted write access to installation directory: {existing}");
        }
    }
    public void PrepareDirectory(string path)
    {
        SafeFiles.NoLinks(path);
        Directory.CreateDirectory(path);
        ValidateRoot(path.Contains(@"\LICENSES", StringComparison.OrdinalIgnoreCase) ||
                     path.Contains(@"\Databases", StringComparison.OrdinalIgnoreCase)
            ? Path.GetDirectoryName(path)! : path);
        var info = new DirectoryInfo(path);
        var acl = info.GetAccessControl();
        acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier("S-1-15-2-1"),
            FileSystemRights.ReadAndExecute, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
            PropagationFlags.None, AccessControlType.Allow));
        info.SetAccessControl(acl);
    }
    public void VerifyFile(string path, bool signed)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        if (extension is not (".exe" or ".dll")) return;
        using var reader = new BinaryReader(File.OpenRead(path));
        if (reader.ReadUInt16() != 0x5a4d) throw new DeploymentException("Invalid PE file.");
        reader.BaseStream.Position = 0x3c;
        var offset = reader.ReadInt32();
        if (offset < 64 || offset > reader.BaseStream.Length - 6) throw new DeploymentException("Invalid PE header.");
        reader.BaseStream.Position = offset;
        if (reader.ReadUInt32() != 0x4550) throw new DeploymentException("Invalid PE signature.");
        var expected = Path.GetFileName(path).Contains("_x86", StringComparison.OrdinalIgnoreCase) || Architecture == "x86"
            ? 0x014c : 0x8664;
        if (reader.ReadUInt16() != expected) throw new DeploymentException($"Incorrect PE architecture: {path}");
        if (signed) VerifySignature(path);
    }
    public void VerifyDatabase(string path)
    {
        using var stream = typeof(WindowsSystem).Assembly.GetManifestResourceStream("KeyKey.ModelManifest.json")!;
        using var model = JsonDocument.Parse(stream);
        if (SafeFiles.Hash(path) != model.RootElement.GetProperty("canonical_database_sha256").GetString())
            throw new DeploymentException("The database does not match this release's canonical model.");
    }
    private static List<RegistryValueData> ReadValues(RegistryKey key) => key.GetValueNames().Select(name =>
        new RegistryValueData(name, (int)key.GetValueKind(name), JsonSerializer.Serialize(
            key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames)))).ToList();
    private static object Decode(RegistryValueData value) => (RegistryValueKind)value.Kind switch
    {
        RegistryValueKind.DWord => JsonSerializer.Deserialize<int>(value.Data),
        RegistryValueKind.QWord => JsonSerializer.Deserialize<long>(value.Data),
        RegistryValueKind.Binary => JsonSerializer.Deserialize<byte[]>(value.Data)!,
        RegistryValueKind.MultiString => JsonSerializer.Deserialize<string[]>(value.Data)!,
        _ => JsonSerializer.Deserialize<string>(value.Data)!
    };
    private static string Value(RegistryKey? key, string name) => key?.GetValue(name) as string ?? "";
    private string ComPath(RegistryView view)
    {
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
        using var key = machine.OpenSubKey(ClassKey + @"\InprocServer32");
        return Value(key, "");
    }
    public object InspectRegistration(InstallationState state) => new
    {
        Architecture,
        RegistryViews = Views.Select(view =>
        {
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            using var product = machine.OpenSubKey(ProductKey);
            return new { View = view.ToString(), ComServer = ComPath(view),
                Product = product == null ? new List<RegistryValueData>() : ReadValues(product) };
        }).ToArray(),
        PendingFiles = state.Retired.Concat(state.Current == null ? [] : new[] { state.Current })
            .SelectMany(p => p.Files.Select(f => SafeFiles.Child(p.Directory, f.Path)))
            .Concat(state.MaintenanceFiles.Select(f => SafeFiles.Child(DefaultRoot, f.Path)))
            .Where(IsPendingDelete).ToArray()
    };
    public InstallationState DiscoverLegacy(string root)
    {
        var entryView = ProductView;
        // Old 32-bit ZIP launchers on x64 sometimes published only Registry32.
        using (var native = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, ProductView))
        using (var nativeEntry = native.OpenSubKey(ProductKey))
            if (nativeEntry == null && Environment.Is64BitOperatingSystem) entryView = RegistryView.Registry32;
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, entryView);
        using var entry = machine.OpenSubKey(ProductKey);
        if (entry == null)
        {
            if (Views.Any(v => ComPath(v) != ""))
                throw new DeploymentException("TSF registration exists without product metadata. Use diagnostic repair.");
            return new();
        }
        var location = Value(entry, "InstallLocation");
        var directory = Value(entry, "VersionLocation");
        if (directory == "") directory = location;
        ValidateRoot(location);
        ValidateRoot(directory);
        if (!SafeFiles.FullPath(directory).Equals(SafeFiles.FullPath(location), StringComparison.OrdinalIgnoreCase) &&
            !SafeFiles.FullPath(directory).StartsWith(SafeFiles.FullPath(location) + "\\", StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("Legacy VersionLocation escapes InstallLocation.");
        var paths = Views.Select(ComPath).Where(p => p != "").ToList();
        if (paths.Count == 0 || paths.Any(p => !SafeFiles.FullPath(Path.GetDirectoryName(p)!).Equals(
                    SafeFiles.FullPath(directory), StringComparison.OrdinalIgnoreCase) || !File.Exists(p)))
            throw new DeploymentException("Legacy registry views and payload disagree.");
        var current = InventoryLegacy(directory, Value(entry, "DisplayVersion"));
        var state = new InstallationState { Current = current };
        // Older NSIS upgrades left version directories and ZIP root files.
        foreach (var candidate in Directory.EnumerateDirectories(location))
        {
            if (!Regex.IsMatch(Path.GetFileName(candidate), @"^\d+\.\d+\.\d+(?:\.\d+)?(?:-(?:(?:test|repair)-)?[0-9a-f]+)?$") ||
                candidate.Equals(directory, StringComparison.OrdinalIgnoreCase)) continue;
            SafeFiles.NoLinks(candidate);
            if (File.Exists(Path.Combine(candidate, "KeyKeyTsf_x64.dll")) ||
                File.Exists(Path.Combine(candidate, "KeyKeyTsf_x86.dll")))
                state.Retired.Add(InventoryLegacy(candidate, Path.GetFileName(candidate).Split('-')[0]));
        }
        if (!location.Equals(directory, StringComparison.OrdinalIgnoreCase) &&
            new[] { "KeyKeyTsf.dll", "KeyKeyTsf_x64.dll", "KeyKeyTsf_x86.dll" }.Any(f => File.Exists(Path.Combine(location, f))))
            state.Retired.Add(InventoryLegacy(location, "0.0.0"));
        return state;
    }
    private Instance InventoryLegacy(string directory, string version)
    {
        ValidateRoot(directory);
        var known = new List<string> { "KeyKeyTsf.dll", "KeyKeyTsf_x64.dll", "KeyKeyTsf_x86.dll",
            "KeyKeySettings.exe", "KeyKeySettingsBackend.dll", "Databases\\KeyKey.db", "README.md", "README.txt",
            "PackageInfo.json", "Install.cmd", "Install.ps1", "Uninstall.cmd" };
        // Only names actually shipped by the old package templates. Extra files
        // in Databases/LICENSES are never made installer-owned by location alone.
        foreach (var name in new[] { "KeyKey-README.md", "KeyKey-LICENSE.txt", "LICENSING.md", "MIT-Chui-Ping-Cheng.txt",
            "Windows-TSF-LICENSE.txt", "Windows-Frontend-MIT.txt", "chichi77Collection-LICENSE.txt", "THIRD-PARTY-NOTICES.md" })
            known.Add("LICENSES\\" + name);
        var files = known.Where(p => File.Exists(SafeFiles.Child(directory, p)))
            .Select(p => new PackageFile(p, SafeFiles.Hash(SafeFiles.Child(directory, p)))).ToList();
        return new Instance { Directory = directory, Version = version, Architecture = Architecture, Legacy = true, Files = files };
    }
    public SystemSnapshot Capture(string toolDirectory)
    {
        var snapshot = new SystemSnapshot { TsfMask = NativeTsf.Query(toolDirectory),
            TsfMask32 = Environment.Is64BitOperatingSystem ? NativeTsf.Query32(toolDirectory) : 0 };
        foreach (var view in Views)
        {
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            foreach (var path in new[] { ClassKey, ClassKey + @"\InprocServer32", ProductKey })
            {
                using var key = machine.OpenSubKey(path);
                snapshot.Keys.Add(new(path, (int)view, key != null, key == null ? [] : ReadValues(key)));
            }
        }
        return snapshot;
    }
    public void Register(Instance instance)
    {
        foreach (var view in Views)
        {
            var dll = Path.Combine(instance.Directory, view == RegistryView.Registry64 ? "KeyKeyTsf_x64.dll" : "KeyKeyTsf_x86.dll");
            VerifyFile(dll, false);
            if (Environment.Is64BitOperatingSystem && view == RegistryView.Registry32)
                NativeTsf.Register32(instance.Directory);
            else NativeTsf.Register(instance.Directory);
        }
    }
    public void VerifyRegistration(Instance instance)
    {
        foreach (var view in Views)
        {
            var expected = Path.Combine(instance.Directory, view == RegistryView.Registry64 ? "KeyKeyTsf_x64.dll" : "KeyKeyTsf_x86.dll");
            if (!ComPath(view).Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new DeploymentException("The COM registration does not point to this payload.");
        }
        VerifyProfilePolicy(NativeTsf.Query(instance.Directory), Environment.Is64BitProcess ? "x64" : "x86");
        if (Environment.Is64BitOperatingSystem) VerifyProfilePolicy(NativeTsf.Query32(instance.Directory), "x86");
    }
    public static void VerifyProfilePolicy(uint mask, string architecture = "native")
    {
        const uint required = 0x1f01; // one selectable profile and five categories
        if ((mask & required) != required)
            throw new DeploymentException($"The main TSF profile or required categories are missing ({architecture}: actual 0x{mask:x}, required 0x{required:x}, missing 0x{required & ~mask:x}).");
    }
    public string RetireLegacyProfiles(Instance instance)
    {
        VerifyRetiredProfiles(NativeTsf.Retire(instance.Directory));
        if (Environment.Is64BitOperatingSystem) VerifyRetiredProfiles(NativeTsf.Retire32(instance.Directory));
        return "One shared KeyKey entry remains. Former Hong Kong/Macao entry users must select the shared entry in Windows Settings. Personal data is preserved.";
    }
    public static void VerifyRetiredProfiles(uint mask)
    {
        VerifyProfilePolicy(mask);
        if ((mask & 6) != 0) throw new DeploymentException("Legacy regional TSF entries remain registered.");
    }
    public void Restore(SystemSnapshot snapshot, string toolDirectory)
    {
        NativeTsf.Restore(toolDirectory, snapshot.TsfMask);
        if (Environment.Is64BitOperatingSystem) NativeTsf.Restore32(toolDirectory, snapshot.TsfMask32);
        foreach (var saved in snapshot.Keys.AsEnumerable().Reverse())
        {
            if (saved.Path != ClassKey && saved.Path != ClassKey + @"\InprocServer32" && saved.Path != ProductKey)
                throw new DeploymentException("Invalid transaction registry path.");
            if (!Views.Contains((RegistryView)saved.View)) throw new DeploymentException("Invalid registry view.");
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, (RegistryView)saved.View);
            if (!saved.Exists) { machine.DeleteSubKeyTree(saved.Path, false); continue; }
            using var key = machine.CreateSubKey(saved.Path, true);
            foreach (var name in key.GetValueNames()) key.DeleteValue(name);
            foreach (var value in saved.Values) key.SetValue(value.Name, Decode(value), (RegistryValueKind)value.Kind);
        }
    }
    public void Publish(Instance instance, string root)
    {
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, ProductView);
        using var key = machine.CreateSubKey(ProductKey, true);
        var tool = Path.Combine(instance.Directory, "KeyKeyDeployment.exe");
        var command = $"\"{tool}\" uninstall --owner {instance.Id}";
        foreach (var pair in new Dictionary<string, string>
        {
            ["DisplayName"] = "chichi77 KeyKey", ["DisplayVersion"] = instance.Version,
            ["Publisher"] = "polobread", ["InstallLocation"] = root,
            ["VersionLocation"] = instance.Directory, ["PayloadFingerprint"] = instance.Fingerprint,
            ["InstallationId"] = instance.Id, ["UninstallString"] = command,
            ["QuietUninstallString"] = command + " --quiet",
            ["DisplayIcon"] = $"\"{Path.Combine(instance.Directory, "KeyKeySettings.exe")}\",0",
            ["URLInfoAbout"] = "https://github.com/polobread/KeyKey"
        }) key.SetValue(pair.Key, pair.Value, RegistryValueKind.String);
        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        // A 32-bit launcher used to leave a duplicate product entry on x64.
        if (Environment.Is64BitOperatingSystem)
        {
            using var other = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32);
            other.DeleteSubKeyTree(ProductKey, false);
        }
        // Remove the old, now inaccurate shortcut; Settings is available from
        // the language-bar menu and the packaged executable.
        var shortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
            "chichi77 KeyKey", "chichi77 KeyKey Settings.lnk");
        SafeFiles.NoLinks(shortcut);
        if (File.Exists(shortcut)) File.Delete(shortcut);
    }
    public void TakeOverLegacyEntrypoints(string root, string toolDirectory, Action<PackageFile> record)
    {
        var exe = SafeFiles.Child(root, "Uninstall.exe");
        var source = SafeFiles.Child(toolDirectory, "KeyKeyDeployment.exe");
        var hash = SafeFiles.Hash(source);
        // Never reuse a filename Windows will delete at the next restart.
        if (IsPendingDelete(exe))
            exe = SafeFiles.Child(root, "Uninstall." + Guid.NewGuid().ToString("N") + ".exe");
        if (!File.Exists(exe) || SafeFiles.Hash(exe) != hash)
        {
            // Rename before replacement so a running old uninstaller cannot
            // force an in-place overwrite. Preserve it as a non-executable backup.
            if (File.Exists(exe))
            {
                var backup = exe + "." + Guid.NewGuid().ToString("N") + ".retired";
                record(new(Path.GetFileName(backup), SafeFiles.Hash(exe)));
                File.Move(exe, backup);
            }
            record(new(Path.GetFileName(exe), hash));
            File.Copy(source, exe);
        }
        else record(new(Path.GetFileName(exe), hash));
        var script = SafeFiles.Child(root, "Uninstall.ps1");
        var text = "$ErrorActionPreference = 'Stop'\r\n" +
            $"& (Join-Path $PSScriptRoot '{Path.GetFileName(exe)}') uninstall\r\nexit $LASTEXITCODE\r\n";
        var bytes = System.Text.Encoding.ASCII.GetBytes(text);
        var scriptHash = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(bytes));
        if (IsPendingDelete(script)) return; // current ARP uses the versioned helper directly
        if (File.Exists(script) && SafeFiles.Hash(script) != scriptHash)
        {
            var backup = script + "." + Guid.NewGuid().ToString("N") + ".retired";
            record(new(Path.GetFileName(backup), SafeFiles.Hash(script)));
            File.Move(script, backup);
        }
        record(new("Uninstall.ps1", scriptHash));
        File.WriteAllBytes(script, bytes);
    }
    public void Unregister(Instance instance, string toolDirectory, bool retry)
    {
        // Compare both views before touching TSF; no stale payload can remove
        // registration that belongs to a different installation.
        foreach (var view in Views)
        {
            var registered = ComPath(view);
            if (registered == "") continue;
            if (!instance.Files.Any(f => Path.Combine(instance.Directory, f.Path).Equals(registered, StringComparison.OrdinalIgnoreCase)))
                throw new DeploymentException("Registration ownership changed. Use repair before uninstalling.");
        }
        NativeTsf.Restore(toolDirectory, 0);
        if (Environment.Is64BitOperatingSystem) NativeTsf.Restore32(toolDirectory, 0);
        var remaining = NativeTsf.Query(toolDirectory);
        var remaining32 = Environment.Is64BitOperatingSystem ? NativeTsf.Query32(toolDirectory) : 0;
        if (remaining != 0 || remaining32 != 0)
            throw new DeploymentException($"TSF removal is incomplete (native 0x{remaining:x}, x86 0x{remaining32:x}); retry removal.");
        foreach (var view in Views)
        {
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            machine.DeleteSubKeyTree(ClassKey, false);
        }
    }
    public void RemoveProductEntry()
    {
        foreach (var view in Views)
        {
            using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view);
            machine.DeleteSubKeyTree(ProductKey, false);
        }
    }
    public void PublishCleanup(string root, bool retryRemoval = false)
    {
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, ProductView);
        using var key = machine.CreateSubKey(ProductKey, true);
        var state = SafeFiles.Read<InstallationState>(SafeFiles.Child(root, "InstallationState.json"));
        var helper = state.MaintenanceFiles.LastOrDefault(f => f.Path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) &&
            File.Exists(SafeFiles.Child(root, f.Path)) && !IsPendingDelete(SafeFiles.Child(root, f.Path)) &&
            SafeFiles.Hash(SafeFiles.Child(root, f.Path)) == f.Sha256)
            ?? throw new DeploymentException("No safe cleanup entrypoint remains. Re-run the downloaded package.");
        var command = $"\"{SafeFiles.Child(root, helper.Path)}\" " + (retryRemoval ? "uninstall" : "cleanup");
        key.SetValue("DisplayName", "chichi77 KeyKey（解除安裝未完成，請重試）");
        key.SetValue("UninstallString", command);
        key.SetValue("QuietUninstallString", command + " --quiet");
        if (!retryRemoval) key.DeleteValue("VersionLocation", false);
    }
    public bool IsPendingDelete(string path)
    {
        using var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, ProductView);
        using var key = machine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Session Manager");
        var operations = key?.GetValue("PendingFileRenameOperations") as string[] ?? [];
        var full = SafeFiles.FullPath(path);
        return operations.Where((_, i) => i % 2 == 0).Any(p =>
        {
            p = p.StartsWith(@"\??\") ? p[4..] : p;
            return p.Equals(full, StringComparison.OrdinalIgnoreCase) ||
                   p.StartsWith(full + "\\", StringComparison.OrdinalIgnoreCase);
        });
    }
    public bool IsInUse(IEnumerable<string> files)
    {
        foreach (var file in files)
        {
            if (IsPendingDelete(file)) return true;
            try
            {
                using (var handle = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None)) { }
                // A mapped DLL can be opened read-only exclusively while still
                // rejecting delete access. Probe delete sharing as well.
                var native = CreateFile(file, 0x10000, 0, IntPtr.Zero, 3, 0, IntPtr.Zero);
                if (native == new IntPtr(-1)) return true;
                CloseHandle(native);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return true; }
        }
        return false;
    }
    public void ScheduleDelete(string path)
    {
        SafeFiles.NoLinks(path);
        if (IsPendingDelete(path)) return;
        if (!MoveFileEx(path, null, 4)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    private static void VerifySignature(string path)
    {
        var file = new TrustFile { Size = (uint)Marshal.SizeOf<TrustFile>(), Path = path };
        var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<TrustFile>());
        Marshal.StructureToPtr(file, pointer, false);
        try
        {
            var data = new TrustData { Size = (uint)Marshal.SizeOf<TrustData>(), UiChoice = 2,
                UnionChoice = 1, File = pointer, ProviderFlags = 0x1000 };
            var action = new Guid("00aac56b-cd44-11d0-8cc2-00c04fc295ee");
            if (WinVerifyTrust(new IntPtr(-1), ref action, ref data) != 0)
                throw new DeploymentException($"Signature verification failed: {path}");
        }
        finally { Marshal.DestroyStructure<TrustFile>(pointer); Marshal.FreeHGlobal(pointer); }
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct TrustFile { public uint Size; [MarshalAs(UnmanagedType.LPWStr)] public string Path; public IntPtr Handle, Subject; }
    [StructLayout(LayoutKind.Sequential)]
    private struct TrustData { public uint Size; public IntPtr Policy, Sip; public uint UiChoice, Revocation, UnionChoice;
        public IntPtr File; public uint StateAction; public IntPtr State, Url; public uint ProviderFlags, UiContext; public IntPtr Signature; }
    [DllImport("wintrust.dll", ExactSpelling = true)] private static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "MoveFileExW")]
    private static extern bool MoveFileEx(string source, string? destination, uint flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern IntPtr CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
}
internal static class NativeTsf
{
    private static string Bridge(string directory, string operation, uint? mask = null)
    {
        var start = new ProcessStartInfo(SafeFiles.Child(directory, "KeyKeyRegistration_x86.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add(operation);
        start.ArgumentList.Add(SafeFiles.Child(directory, "KeyKeyTsf_x86.dll"));
        if (mask != null) start.ArgumentList.Add(mask.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new DeploymentException("x86 TSF transaction failed: " + error);
        return output.Trim();
    }
    public static uint Query32(string directory) => uint.Parse(Bridge(directory, "query"), System.Globalization.CultureInfo.InvariantCulture);
    public static void Register32(string directory) => Bridge(directory, "register");
    public static uint Retire32(string directory) => uint.Parse(Bridge(directory, "retire"), System.Globalization.CultureInfo.InvariantCulture);
    public static void Restore32(string directory, uint mask) => Bridge(directory, "restore", mask);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int QueryState(out uint mask);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int RestoreState(uint mask);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int RegisterState(out uint stage);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int RetireProfiles(out uint remaining);
    private static IntPtr Open(string directory)
    {
        var dll = SafeFiles.Child(directory, Environment.Is64BitProcess ? "KeyKeyTsf_x64.dll" : "KeyKeyTsf_x86.dll");
        var module = LoadLibraryEx(dll, IntPtr.Zero, 0x100 | 0x800); // DLL directory and System32 only
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        return module;
    }
    public static uint Query(string directory)
    {
        var module = Open(directory);
        try
        {
            var query = Marshal.GetDelegateForFunctionPointer<QueryState>(NativeLibrary.GetExport(module, "KeyKeyQueryTsfState"));
            Marshal.ThrowExceptionForHR(query(out var mask));
            return mask;
        }
        finally { NativeLibrary.Free(module); }
    }
    public static void Register(string directory)
    {
        var module = Open(directory);
        try
        {
            var registration = Marshal.GetDelegateForFunctionPointer<RegisterState>(NativeLibrary.GetExport(module, "KeyKeyRegisterTsfState"));
            var result = registration(out var stage);
            if (result < 0) throw new DeploymentException($"TSF registration failed: native stage {stage}, HRESULT 0x{result:x8}.");
        }
        finally { NativeLibrary.Free(module); }
    }
    public static uint Retire(string directory)
    {
        var module = Open(directory);
        try
        {
            var retire = Marshal.GetDelegateForFunctionPointer<RetireProfiles>(NativeLibrary.GetExport(module, "KeyKeyRetireLegacyProfiles"));
            Marshal.ThrowExceptionForHR(retire(out var remaining));
            return remaining;
        }
        finally { NativeLibrary.Free(module); }
    }
    public static void Restore(string directory, uint mask)
    {
        var module = Open(directory);
        try
        {
            var restore = Marshal.GetDelegateForFunctionPointer<RestoreState>(NativeLibrary.GetExport(module, "KeyKeyRestoreTsfState"));
            Marshal.ThrowExceptionForHR(restore(mask));
        }
        finally { NativeLibrary.Free(module); }
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "LoadLibraryExW")]
    private static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
}
