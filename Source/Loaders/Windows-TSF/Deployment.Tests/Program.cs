using KeyKey.Deployment;
using System.Runtime.InteropServices;

int passed = 0;
void Test(string name, Action<Fixture> test)
{
    using var fixture = new Fixture();
    test(fixture);
    Console.WriteLine("PASS " + name);
    ++passed;
}
void Check(bool condition) { if (!condition) throw new Exception("Assertion failed."); }
void Reject(Action operation)
{
    try { operation(); } catch (DeploymentException) { return; }
    throw new Exception("Unsafe operation was accepted.");
}
Test("deployment diagnostic logging follows the default-off three-day setting", f =>
{
    Directory.CreateDirectory(f.Root);
    var path = Path.Combine(f.Root, "Deployment.log");
    var program = typeof(DeploymentEngine).Assembly.GetType("KeyKey.Deployment.Program", true)!;
    const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static;
    var logPath = program.GetField("logPath", flags);
    var previous = Environment.GetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR");
    Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", f.Root);
    var settings = Path.Combine(f.Root, "diagnostics.plist");
    var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
    void Session(long start, long end) => File.WriteAllText(settings,
        $"<plist><dict><key>StartedAtUtc</key><string>{start}</string><key>ExpiresAtUtc</key><string>{end}</string></dict></plist>");
    try
    {
        logPath?.SetValue(null, path);
        program.GetMethod("Report", flags)!.Invoke(null, ["diagnostics-switch-test"]);
        Check(!File.Exists(path));
        Session(now, now + 3 * 86400);
        program.GetMethod("Report", flags)!.Invoke(null, ["enabled"]);
        Check(File.ReadAllText(path).Contains("enabled"));
        File.WriteAllText(path, "existing record");
        foreach (var session in new[] { (0L, 0L), (now - 3 * 86400, now), (now, now + 4 * 86400) }) {
            Session(session.Item1, session.Item2);
            program.GetMethod("Report", flags)!.Invoke(null, ["must not append"]);
            Check(File.ReadAllText(path) == "existing record");
        }
        Session(now, now + 3 * 86400);
        using (var stream = File.Create(path)) stream.SetLength(1024 * 1024);
        program.GetMethod("Report", flags)!.Invoke(null, ["bounded deployment log"]);
        Check(new FileInfo(path).Length < 1024 * 1024);
    }
    finally { logPath?.SetValue(null, null); Environment.SetEnvironmentVariable("KEYKEY_TSF_TEST_PROFILE_DIR", previous); }
});
Test("updater sidecar is validated and retained with its versioned payload", f =>
{
    var package = f.Package("1.3.2");
    var updater = Path.Combine(package, "Payload", "WinSparkle.dll");
    File.WriteAllText(updater, "isolated updater test fixture");
    var manifestPath = Path.Combine(package, "PackageManifest.json");
    var manifest = SafeFiles.Read<PackageManifest>(manifestPath);
    manifest.Files.Add(new PackageFile("WinSparkle.dll", SafeFiles.Hash(updater)));
    SafeFiles.Write(manifestPath, manifest);
    f.Engine.Install(package);
    var old = f.Engine.Inspect().Current!;
    Check(File.Exists(Path.Combine(old.Directory, "WinSparkle.dll")));
    f.Engine.Install(f.Package("1.3.3"));
    Check(f.Engine.Inspect().Retired.Any(p => p.Id == old.Id));
    Check(SafeFiles.Matches(old.Directory, old.Files));
    Reject(() => SafeFiles.ValidatePayload([new PackageFile("UnexpectedUpdater.dll", new string('a', 64))]));
});
Test("upgrade keeps the complete previous payload and switches both registrations", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    var old = f.Engine.Inspect().Current!;
    f.Engine.Install(f.Package("1.3.1"));
    Check(f.Engine.Inspect().Retired.Any(p => p.Id == old.Id));
    Check(SafeFiles.Matches(old.Directory, old.Files));
    Check(f.System.Current == f.Engine.Inspect().Current!.Directory);
});
Test("registration requires the main profile and categories without the unsupported hidden flag", f =>
{
    WindowsSystem.VerifyProfilePolicy(0x1f01); // fresh installation
    WindowsSystem.VerifyProfilePolicy(0x1f07); // legacy definitions cleaned after commit
    WindowsSystem.VerifyProfilePolicy(0x1f03); // only Hong Kong existed
    Reject(() => WindowsSystem.VerifyProfilePolicy(0x1f06)); // main entry missing
    Reject(() => WindowsSystem.VerifyProfilePolicy(0x21e03)); // missing category
});
Test("failed upgrade restores both views and does not retire existing profiles", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    f.System.Mask = 0x1f07;
    f.System.Mask32 = 0x1f03;
    var retired = f.System.RetireCalls;
    f.System.FailPublish = true;
    Reject(() => f.Engine.Install(f.Package("1.3.1")));
    Check(f.System.Mask == 0x1f07 && f.System.Mask32 == 0x1f03 && f.System.RetireCalls == retired);
});
Test("cleanup verification requires the shared entry and rejects either legacy entry", f =>
{
    WindowsSystem.VerifyRetiredProfiles(0x1f01);
    Reject(() => WindowsSystem.VerifyRetiredProfiles(0x1f03));
    Reject(() => WindowsSystem.VerifyRetiredProfiles(0x1f05));
    Reject(() => WindowsSystem.VerifyRetiredProfiles(0x1f00));
});
Test("optional legacy cleanup failure does not undo a successful installation", f =>
{
    var package = f.Package("1.3.1");
    f.System.FailRetire = true;
    Check(f.Engine.Install(package) == 0);
    Check(f.Engine.Inspect().Current!.Directory == f.System.Current);
    Check(f.System.Restores == 0);
    var retired = f.System.RetireCalls;
    f.System.FailRetire = false;
    Check(f.Engine.Install(package) == 0);
    Check(f.System.RetireCalls == retired + 1 && f.System.Registers == 1);
});
Test("x86 registration failure restores the previous installation", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    var old = f.System.Current;
    f.System.FailRegister = true;
    Reject(() => f.Engine.Install(f.Package("1.3.1")));
    Check(f.System.Current == old && f.System.Restores == 1);
    Check(f.Engine.Inspect().Current!.Directory == old);
});
Test("publish failure restores registration and preserves the retry entry", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    var old = f.System.Current;
    f.System.FailPublish = true;
    Reject(() => f.Engine.Install(f.Package("1.3.1")));
    Check(f.System.Current == old && f.Engine.Inspect().Current!.Directory == old);
});
Test("interrupted transaction recovers before installing", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    var state = f.Engine.Inspect();
    var next = new Instance { Directory = Path.Combine(f.Root, "1.3.1"), Version = "1.3.1",
        Files = state.Current!.Files, Architecture = "x64" };
    Directory.CreateDirectory(next.Directory);
    foreach (var file in next.Files)
    {
        var target = SafeFiles.Child(next.Directory, file.Path);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        File.Copy(SafeFiles.Child(state.Current.Directory, file.Path), target);
    }
    SafeFiles.Write(Path.Combine(f.Root, "InstallationTransaction.json"), new Transaction
        { Previous = state, Next = next, Snapshot = f.System.Capture(next.Directory) });
    f.System.Current = next.Directory;
    f.Engine.Recover();
    Check(f.System.Current == state.Current.Directory && !File.Exists(Path.Combine(f.Root, "InstallationTransaction.json")));
});
Test("same package rerun does not replace payload", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var directory = f.Engine.Inspect().Current!.Directory;
    f.Engine.Install(package);
    Check(f.Engine.Inspect().Current!.Directory == directory && f.System.Registers == 1);
});
Test("new payload names use version and fingerprint without test or repair labels", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var current = f.Engine.Inspect().Current!;
    Check(Path.GetFileName(current.Directory) == "1.3.1-" + current.Fingerprint[..12]);
    File.WriteAllText(Path.Combine(current.Directory, "KeyKeyTsf_x64.dll"), "damaged");
    f.Engine.Install(package, true);
    var repaired = Path.GetFileName(f.Engine.Inspect().Current!.Directory);
    Check(repaired.StartsWith("1.3.1-") && !repaired.Contains("test") && !repaired.Contains("repair"));
});
Test("repair uses a new directory instead of overwriting a damaged loaded DLL", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var old = f.Engine.Inspect().Current!.Directory;
    File.WriteAllText(Path.Combine(old, "KeyKeyTsf_x64.dll"), "damaged");
    f.Engine.Install(package, true);
    Check(f.Engine.Inspect().Current!.Directory != old);
    Check(File.ReadAllText(Path.Combine(old, "KeyKeyTsf_x64.dll")) == "damaged");
});
Test("downgrade is rejected before changing registration", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var current = f.System.Current;
    Reject(() => f.Engine.Install(f.Package("1.3.0")));
    Check(f.System.Current == current);
});
Test("stale owner cannot uninstall the new version", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    var owner = f.Engine.Inspect().Current!.Id;
    f.Engine.Install(f.Package("1.3.1"));
    Reject(() => f.Engine.Uninstall(owner));
    Check(f.Engine.Inspect().Current != null && f.System.Unregisters == 0);
});
Test("stale cleanup entry cannot claim removal or delete an active installation", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var current = f.Engine.Inspect().Current!;
    Reject(() => f.Engine.Cleanup());
    Check(!f.System.EntryRemoved && f.System.Unregisters == 0);
    Check(SafeFiles.Matches(current.Directory, current.Files));
});
Test("uninstall preserves extra files and changed product files", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var directory = f.Engine.Inspect().Current!.Directory;
    File.WriteAllText(Path.Combine(directory, "personal.txt"), "keep");
    File.WriteAllText(Path.Combine(directory, "Databases", "KeyKey.db"), "modified");
    f.Engine.Uninstall();
    Check(File.ReadAllText(Path.Combine(directory, "personal.txt")) == "keep");
    Check(File.ReadAllText(Path.Combine(directory, "Databases", "KeyKey.db")) == "modified");
    Check(f.System.EntryRemoved);
});
Test("occupied payload is retained and all known files are scheduled", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var current = f.Engine.Inspect().Current!;
    f.System.Occupied = true;
    Check(f.Engine.Uninstall() == 3010);
    Check(SafeFiles.Matches(current.Directory, current.Files));
    Check(current.Files.All(file => f.System.Pending.Contains(SafeFiles.Child(current.Directory, file.Path))));
    Check(f.System.EntryRemoved && f.Engine.Inspect().RemovalQueued);
    Check(f.System.Pending.Contains(current.Directory) && !f.System.Pending.Contains(f.Root));
});
Test("reinstall before reboot avoids pending payload paths", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var old = f.Engine.Inspect().Current!.Directory;
    f.System.Occupied = true;
    f.Engine.Uninstall();
    f.Engine.Install(package);
    Check(f.Engine.Inspect().Current!.Directory != old);
    Check(!f.Engine.Inspect().RemovalQueued);
});
Test("one uninstall queues payload and mapped maintenance together and reboot finishes without another cleanup", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var state = f.Engine.Inspect();
    var old = state.Current!;
    var helper = Path.Combine(f.Root, "Uninstall.exe");
    File.Copy(Environment.ProcessPath!, helper);
    state.MaintenanceFiles.Add(new("Uninstall.exe", SafeFiles.Hash(helper)));
    SafeFiles.Write(Path.Combine(f.Root, "InstallationState.json"), state);
    using (var image = new MappedImage(helper))
    {
        f.System.Occupied = true;
        Check(f.Engine.Uninstall() == 3010);
        Check(f.System.EntryRemoved && f.System.Pending.Contains(helper));
        Check(f.Engine.Inspect().RemovalQueued && f.System.CleanupEntries == 0);
    }
    f.SimulateReboot();
    Check(!Directory.Exists(old.Directory) && !File.Exists(helper) && f.System.EntryRemoved);
    f.Engine.Install(package); // no call to Cleanup between reboot and reinstall
    var installed = f.Engine.Inspect();
    Check(installed.Current != null && !installed.RemovalQueued);
    Check(!installed.Retired.Any(p => p.Directory == installed.Current!.Directory));
});
Test("queued old files cannot delete a reinstall during reboot", f =>
{
    var package = f.Package("1.3.1");
    f.Engine.Install(package);
    var old = f.Engine.Inspect().Current!;
    f.System.Occupied = true;
    f.Engine.Uninstall();
    f.Engine.Install(package);
    var next = f.Engine.Inspect().Current!;
    f.SimulateReboot();
    Check(!Directory.Exists(old.Directory));
    Check(SafeFiles.Matches(next.Directory, next.Files) && f.System.Current == next.Directory);
});
Test("unknown files keep their directories while known files are queued", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var current = f.Engine.Inspect().Current!;
    var personal = Path.Combine(current.Directory, "Databases", "personal.txt");
    File.WriteAllText(personal, "keep");
    f.System.Occupied = true;
    f.Engine.Uninstall();
    Check(!f.System.Pending.Contains(Path.GetDirectoryName(personal)!));
    Check(!f.System.Pending.Contains(current.Directory));
    f.SimulateReboot();
    Check(File.ReadAllText(personal) == "keep");
});
Test("mapped uninstaller access denied schedules cleanup and removes the application entry", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var path = Path.Combine(f.Root, "Uninstall.exe");
    File.Copy(Environment.ProcessPath!, path);
    var state = f.Engine.Inspect();
    state.MaintenanceFiles.Add(new("Uninstall.exe", SafeFiles.Hash(path)));
    SafeFiles.Write(Path.Combine(f.Root, "InstallationState.json"), state);
    using (var image = new MappedImage(path))
    {
        bool accessDenied = false;
        try { File.Delete(path); } catch (UnauthorizedAccessException) { accessDenied = true; }
        Check(accessDenied); // actual Windows image-section lock, not an injected exception
        Check(f.Engine.Uninstall() == 3010);
        Check(f.System.Pending.Contains(path) && f.System.EntryRemoved);
        Check(f.Engine.Inspect().Current == null && File.Exists(path));
    }
    f.System.Pending.Clear(); // simulate image unload/reboot, without a real reboot
    Check(f.Engine.Cleanup() == 0 && !File.Exists(path));
});
Test("failure to schedule a mapped maintenance file keeps removal retryable", f =>
{
    f.Engine.Install(f.Package("1.3.1"));
    var path = Path.Combine(f.Root, "Uninstall.exe");
    File.Copy(Environment.ProcessPath!, path);
    var state = f.Engine.Inspect();
    state.MaintenanceFiles.Add(new("Uninstall.exe", SafeFiles.Hash(path)));
    SafeFiles.Write(Path.Combine(f.Root, "InstallationState.json"), state);
    using (var image = new MappedImage(path))
    {
        f.System.FailSchedule = true;
        Reject(() => f.Engine.Uninstall());
        Check(!f.System.EntryRemoved && File.Exists(path));
        Check(f.Engine.Inspect().MaintenanceFiles.Count == 1);
    }
    f.System.FailSchedule = false;
    Check(f.Engine.Cleanup() == 0 && f.System.EntryRemoved);
});
Test("checksum failure leaves registration untouched", f =>
{
    var package = f.Package("1.3.1");
    File.WriteAllText(Path.Combine(package, "Payload", "KeyKeyTsf_x64.dll"), "tampered");
    Reject(() => f.Engine.Install(package));
    Check(f.System.Registers == 0);
});
Test("legacy removal can be prepared without registering a new IME", f =>
{
    var package = f.Package("1.3.0");
    var payload = Path.Combine(package, "Payload");
    var legacy = new Instance { Directory = payload, Version = "1.3.0", Legacy = true,
        Files = SafeFiles.Read<PackageManifest>(Path.Combine(package, "PackageManifest.json")).Files };
    f.System.Legacy = new InstallationState { Current = legacy };
    f.System.Current = payload;
    f.Engine.PrepareLegacyRemoval(f.Package("1.3.1"));
    Check(f.System.Registers == 0 && f.Engine.Inspect().Current!.Legacy);
    f.Engine.Uninstall();
    Check(f.System.Unregisters == 1);
});
Test("an unrecognized package file is rejected before registration", f =>
{
    var package = f.Package("1.3.1");
    var path = Path.Combine(package, "Payload", "unknown.exe");
    File.WriteAllText(path, "unexpected");
    var manifest = SafeFiles.Read<PackageManifest>(Path.Combine(package, "PackageManifest.json"));
    manifest.Files.Add(new("unknown.exe", SafeFiles.Hash(path)));
    SafeFiles.Write(Path.Combine(package, "PackageManifest.json"), manifest);
    Reject(() => f.Engine.Install(package));
    Check(f.System.Registers == 0);
});
Test("interrupted legacy entrypoint takeover is retried before removing the old IME", f =>
{
    var oldPackage = f.Package("1.3.0");
    var payload = Path.Combine(oldPackage, "Payload");
    f.System.Legacy = new InstallationState { Current = new Instance { Directory = payload,
        Version = "1.3.0", Legacy = true,
        Files = SafeFiles.Read<PackageManifest>(Path.Combine(oldPackage, "PackageManifest.json")).Files } };
    f.System.Current = payload;
    var package = f.Package("1.3.1");
    f.System.FailEntrypoints = true;
    Reject(() => f.Engine.PrepareLegacyRemoval(package));
    var tool = f.Engine.Inspect().ToolDirectory;
    f.System.FailEntrypoints = false;
    f.Engine.PrepareLegacyRemoval(package);
    Check(f.System.EntrypointCalls == 2 && f.Engine.Inspect().ToolDirectory == tool && f.System.Registers == 0);
    f.Engine.Uninstall();
    Check(f.System.Unregisters == 1);
});
Test("rollback failure keeps the journal for the next recovery attempt", f =>
{
    f.Engine.Install(f.Package("1.3.0"));
    f.System.FailRegister = f.System.FailRestore = true;
    Reject(() => f.Engine.Install(f.Package("1.3.1")));
    Check(File.Exists(Path.Combine(f.Root, "InstallationTransaction.json")));
    f.System.FailRestore = false;
    f.Engine.Recover();
    Check(f.System.Current == f.Engine.Inspect().Current!.Directory);
});
Test("path traversal and sibling-prefix escape are rejected", f =>
{
    foreach (var path in new[] { @"..\outside", @"..\root-sibling\file", @"Databases\..\file", @"C:\Windows\file", @"a:stream", @"a.\file" })
        Reject(() => SafeFiles.Child(f.Root, path));
});
Test("compatibility entrypoints record ownership before moving files and rerun without extra backups", f =>
{
    var package = f.Package("1.3.1");
    var payload = Path.Combine(package, "Payload");
    var oldExe = Path.Combine(f.Root, "Uninstall.exe");
    Directory.CreateDirectory(f.Root);
    File.WriteAllText(oldExe, "old uninstaller");
    File.WriteAllText(Path.Combine(f.Root, "Uninstall.ps1"), "old script");
    var records = new Dictionary<string, PackageFile>();
    var windows = new WindowsSystem(); // only temp files and read-only pending-delete query
    windows.TakeOverLegacyEntrypoints(f.Root, payload, file =>
    {
        if (file.Path.EndsWith(".retired")) Check(!File.Exists(Path.Combine(f.Root, file.Path)));
        records[file.Path] = file;
    });
    Check(records.Count == 4 && records.Keys.Count(p => p.EndsWith(".retired")) == 2);
    Check(SafeFiles.Hash(oldExe) == SafeFiles.Hash(Path.Combine(payload, "KeyKeyDeployment.exe")));
    windows.TakeOverLegacyEntrypoints(f.Root, payload, file => records[file.Path] = file);
    Check(records.Count == 4 && Directory.GetFiles(f.Root, "*.retired").Length == 2);
});
Console.WriteLine($"{passed} deployment tests passed. No machine registration was modified.");

sealed class MappedImage : IDisposable
{
    private readonly IntPtr mapping;
    public MappedImage(string path)
    {
        using var file = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        mapping = CreateFileMapping(file, IntPtr.Zero, 0x1000002, 0, 0, null); // SEC_IMAGE | PAGE_READONLY
        if (mapping == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    public void Dispose() => CloseHandle(mapping);
    [DllImport("kernel32.dll", EntryPoint = "CreateFileMappingW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFileMapping(Microsoft.Win32.SafeHandles.SafeFileHandle file, IntPtr security,
        uint protection, uint maximumHigh, uint maximumLow, string? name);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
}

sealed class FakeSystem : IDeploymentSystem
{
    public string Architecture => "x64";
    public string Current = "";
    public bool FailRegister, FailPublish, FailRestore, FailEntrypoints, FailRetire, FailSchedule, Occupied, EntryRemoved;
    public InstallationState Legacy = new();
    public int Registers, Restores, Unregisters, EntrypointCalls, CleanupEntries;
    public readonly HashSet<string> Pending = new(StringComparer.OrdinalIgnoreCase);
    public readonly List<string> PendingOrder = [];
    public void ValidateRoot(string path) => SafeFiles.NoLinks(path);
    public void VerifyFile(string path, bool signed) { }
    public void VerifyDatabase(string path) { }
    public void PrepareDirectory(string path) => Directory.CreateDirectory(path);
    public InstallationState DiscoverLegacy(string root) => Legacy;
    public uint Mask = 0x1f01, Mask32 = 0x1f01;
    public int RetireCalls;
    public string RetireLegacyProfiles(Instance instance)
    {
        ++RetireCalls;
        if (FailRetire) throw new DeploymentException("Injected optional cleanup failure.");
        return "Legacy profiles checked.";
    }
    public SystemSnapshot Capture(string toolDirectory) => new() { TsfMask = Mask, TsfMask32 = Mask32, Keys = [new(Current, 0, true, [])] };
    public void Register(Instance instance)
    {
        ++Registers; Current = instance.Directory;
        if (FailRegister) throw new DeploymentException("Injected x86 failure.");
    }
    public void VerifyRegistration(Instance instance) { if (Current != instance.Directory) throw new DeploymentException("Wrong registration."); }
    public void Restore(SystemSnapshot snapshot, string toolDirectory) { ++Restores; if (FailRestore) throw new DeploymentException("Injected rollback failure."); Current = snapshot.Keys[0].Path; Mask = snapshot.TsfMask; Mask32 = snapshot.TsfMask32; }
    public void Publish(Instance instance, string root) { if (FailPublish) throw new DeploymentException("Injected ARP failure."); EntryRemoved = false; }
    public void TakeOverLegacyEntrypoints(string root, string toolDirectory, Action<PackageFile> record)
    {
        ++EntrypointCalls;
        if (FailEntrypoints) throw new DeploymentException("Injected compatibility entrypoint failure.");
    }
    public void Unregister(Instance instance, string toolDirectory, bool retry) { ++Unregisters; Current = ""; }
    public void RemoveProductEntry() => EntryRemoved = true;
    public void PublishCleanup(string root, bool retryRemoval = false) { ++CleanupEntries; }
    public bool IsPendingDelete(string path) => Pending.Any(p => p == path || p.StartsWith(path + "\\", StringComparison.OrdinalIgnoreCase));
    public bool IsInUse(IEnumerable<string> files) => Occupied;
    public void ScheduleDelete(string path)
    {
        if (FailSchedule) throw new DeploymentException("Injected pending-delete scheduling failure.");
        if (Pending.Add(path)) PendingOrder.Add(path);
    }
}
sealed class Fixture : IDisposable
{
    private readonly string temporary = Path.Combine(Path.GetTempPath(), "keykey-deployment-test-" + Guid.NewGuid().ToString("N"));
    public string Root { get; }
    public FakeSystem System { get; } = new();
    public DeploymentEngine Engine { get; }
    public Fixture() { Root = Path.Combine(temporary, "chichi77 KeyKey"); Engine = new(Root, System, _ => { }); }
    public string Package(string version)
    {
        var package = Path.Combine(temporary, "packages", version);
        var files = new[] { "KeyKeyTsf_x64.dll", "KeyKeyTsf_x86.dll", "KeyKeySettings.exe",
            "KeyKeySettingsBackend.dll", "KeyKeyDeployment.exe", "KeyKeyRegistration_x86.exe", "Databases\\KeyKey.db" };
        foreach (var file in files)
        {
            var path = SafeFiles.Child(Path.Combine(package, "Payload"), file);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, version + file);
        }
        SafeFiles.Write(Path.Combine(package, "PackageManifest.json"), new PackageManifest
        {
            Version = version, Architecture = "x64", Files = files.Select(f =>
                new PackageFile(f, SafeFiles.Hash(SafeFiles.Child(Path.Combine(package, "Payload"), f)))).ToList()
        });
        return package;
    }
    public void SimulateReboot()
    {
        foreach (var path in System.PendingOrder)
        {
            var full = Path.GetFullPath(path);
            if (!full.StartsWith(Path.GetFullPath(Root) + "\\", StringComparison.OrdinalIgnoreCase))
                throw new Exception("Test queue escaped fixture root.");
            SafeFiles.NoLinks(full);
            if (File.Exists(full)) File.Delete(full);
            else if (Directory.Exists(full) && !Directory.EnumerateFileSystemEntries(full).Any())
                Directory.Delete(full); // never recursive; preserves extra files
        }
        System.Pending.Clear(); System.PendingOrder.Clear(); System.Occupied = false;
    }
    public void Dispose()
    {
        // The resolved temporary directory is generated by this fixture and is
        // never taken from a manifest or registry. Tests create no reparse points.
        if (Directory.Exists(temporary) && Path.GetFileName(temporary).StartsWith("keykey-deployment-test-"))
            Directory.Delete(temporary, true);
    }
}
