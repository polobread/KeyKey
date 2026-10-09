using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace KeyKey.Deployment;

public sealed record PackageFile(string Path, string Sha256);
public sealed class PackageManifest
{
    public int SchemaVersion { get; set; } = 1;
    public string Version { get; set; } = "";
    public string Architecture { get; set; } = "";
    public bool Signed { get; set; }
    public List<PackageFile> Files { get; set; } = [];
}
public sealed class Instance
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Directory { get; set; } = "";
    public string Version { get; set; } = "";
    public string Fingerprint { get; set; } = "";
    public string Architecture { get; set; } = "";
    public bool Legacy { get; set; }
    public List<PackageFile> Files { get; set; } = [];
}
public sealed class InstallationState
{
    public int SchemaVersion { get; set; } = 1;
    public Instance? Current { get; set; }
    public string ToolDirectory { get; set; } = "";
    public bool Removing { get; set; }
    public bool RemovalQueued { get; set; }
    public List<Instance> Retired { get; set; } = [];
    public List<PackageFile> MaintenanceFiles { get; set; } = [];
}
public sealed record RegistryValueData(string Name, int Kind, string Data);
public sealed record RegistryKeyData(string Path, int View, bool Exists, List<RegistryValueData> Values);
public sealed class SystemSnapshot
{
    public uint TsfMask { get; set; }
    public uint TsfMask32 { get; set; }
    public List<RegistryKeyData> Keys { get; set; } = [];
}
public sealed class Transaction
{
    public InstallationState Previous { get; set; } = new();
    public Instance Next { get; set; } = new();
    public SystemSnapshot Snapshot { get; set; } = new();
    public string Phase { get; set; } = "Prepared";
}
public interface IDeploymentSystem
{
    string Architecture { get; }
    void ValidateRoot(string path);
    void VerifyFile(string path, bool signed);
    void VerifyDatabase(string path);
    void PrepareDirectory(string path);
    InstallationState DiscoverLegacy(string root);
    SystemSnapshot Capture(string toolDirectory);
    void Register(Instance instance);
    void VerifyRegistration(Instance instance);
    string RetireLegacyProfiles(Instance instance);
    void Restore(SystemSnapshot snapshot, string toolDirectory);
    void Publish(Instance instance, string root);
    void TakeOverLegacyEntrypoints(string root, string toolDirectory, Action<PackageFile> record);
    void Unregister(Instance instance, string toolDirectory, bool retry);
    void RemoveProductEntry();
    void PublishCleanup(string root, bool retryRemoval = false);
    bool IsPendingDelete(string path);
    bool IsInUse(IEnumerable<string> files);
    void ScheduleDelete(string path);
}
public sealed class DeploymentException(string message, int code = 1) : Exception(message)
{
    public int Code { get; } = code;
}
public static class SafeFiles
{
    public static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    public static string Hash(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
                                           FileShare.ReadWrite | FileShare.Delete);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }
    public static string FullPath(string path) => System.IO.Path.GetFullPath(path).TrimEnd('\\', '/');
    public static void NoLinks(string path)
    {
        var current = FullPath(path);
        while (!string.IsNullOrEmpty(current))
        {
            if ((File.Exists(current) || System.IO.Directory.Exists(current)) &&
                (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new DeploymentException($"A reparse point is not allowed: {current}");
            current = System.IO.Path.GetDirectoryName(current);
        }
    }
    public static string Child(string root, string relative)
    {
        if (string.IsNullOrWhiteSpace(relative) || relative.Contains(':') ||
            relative.StartsWith('\\') || relative.StartsWith('/') ||
            relative.Split(['\\', '/']).Any(p => p is "" or "." or ".." ||
                p.EndsWith('.') || p.EndsWith(' ') || p.Any(c => c < 32) ||
                Regex.IsMatch(p, @"^(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)", RegexOptions.IgnoreCase) ||
                p.IndexOfAny(['*', '?', '"', '<', '>', '|']) >= 0))
            throw new DeploymentException($"Unsafe relative path: {relative}");
        var full = FullPath(System.IO.Path.Combine(root, relative));
        if (!full.StartsWith(FullPath(root) + System.IO.Path.DirectorySeparatorChar,
                             StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("Path escapes the product directory.");
        NoLinks(full);
        return full;
    }
    public static T Read<T>(string path)
    {
        NoLinks(path);
        if (new FileInfo(path).Length > 4 * 1024 * 1024)
            throw new DeploymentException("Installation metadata is too large.");
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path)) ??
            throw new DeploymentException("Invalid installation metadata.");
    }
    public static void Write<T>(string path, T value)
    {
        NoLinks(path);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                                          FileShare.None, 4096, FileOptions.WriteThrough))
        {
            JsonSerializer.Serialize(stream, value, Json);
            stream.Flush(true);
        }
        File.Move(temporary, path, true);
    }
    public static bool Matches(string root, IEnumerable<PackageFile> files) => files.All(f =>
    {
        var path = Child(root, f.Path);
        return File.Exists(path) && Hash(path) == f.Sha256;
    });
    public static void ValidateList(IEnumerable<PackageFile> files)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in files)
            if (!seen.Add(file.Path.Replace('/', '\\')) ||
                !Regex.IsMatch(file.Sha256, "^[0-9a-f]{64}$"))
                throw new DeploymentException("Invalid or duplicate manifest entry.");
        if (seen.Count == 0 || seen.Count > 256)
            throw new DeploymentException("Invalid manifest file count.");
    }
    public static void ValidatePayload(IEnumerable<PackageFile> files)
    {
        string[] names = ["KeyKeyTsf_x64.dll", "KeyKeyTsf_x86.dll", "KeyKeySettings.exe", "KeyKeyRegistration_x86.exe",
            "KeyKeySettingsBackend.dll", "KeyKeyDeployment.exe", "WinSparkle.dll", "Databases\\KeyKey.db"];
        foreach (var file in files)
        {
            var normalized = file.Path.Replace('/', '\\');
            if (!names.Contains(normalized, StringComparer.OrdinalIgnoreCase) &&
                !System.Text.RegularExpressions.Regex.IsMatch(normalized, @"^LICENSES\\[A-Za-z0-9_-]+\.(?:md|txt)$"))
                throw new DeploymentException($"Unrecognized package file: {file.Path}");
        }
    }
}
public sealed class DeploymentEngine(string root, IDeploymentSystem system, Action<string>? report = null)
{
    private readonly string root = SafeFiles.FullPath(root);
    private readonly Action<string> report = report ?? Console.WriteLine;
    private string StateFile => SafeFiles.Child(root, "InstallationState.json");
    private string TransactionFile => SafeFiles.Child(root, "InstallationTransaction.json");
    public InstallationState Inspect()
    {
        system.ValidateRoot(root);
        var state = File.Exists(StateFile) ? SafeFiles.Read<InstallationState>(StateFile) :
            system.DiscoverLegacy(root);
        ValidateState(state);
        return state;
    }
    private void ValidateInstance(Instance instance)
    {
        system.ValidateRoot(instance.Legacy ? instance.Directory : root);
        if (!instance.Legacy &&
            (!string.Equals(System.IO.Path.GetDirectoryName(SafeFiles.FullPath(instance.Directory)), root, StringComparison.OrdinalIgnoreCase) ||
             !Regex.IsMatch(System.IO.Path.GetFileName(instance.Directory), @"^\d+\.\d+\.\d+(?:\.\d+)?(?:-(?:(?:test|repair)-)?[0-9a-f]+)?$")))
            throw new DeploymentException("Invalid recorded payload directory.");
        SafeFiles.NoLinks(instance.Directory);
        SafeFiles.ValidateList(instance.Files);
        foreach (var file in instance.Files) SafeFiles.Child(instance.Directory, file.Path);
    }
    private void ValidateState(InstallationState state)
    {
        if (state.SchemaVersion != 1 || state.Retired.Count > 128)
            throw new DeploymentException("Unsupported installation state.");
        if (state.Current != null) ValidateInstance(state.Current);
        foreach (var instance in state.Retired) ValidateInstance(instance);
        foreach (var file in state.MaintenanceFiles)
        {
            if (!Regex.IsMatch(file.Path, @"^Uninstall\.(?:[0-9a-f]{32}\.exe|(?:exe|ps1)(?:\.[0-9a-f]{32}\.retired)?)$", RegexOptions.IgnoreCase) ||
                !Regex.IsMatch(file.Sha256, "^[0-9a-f]{64}$"))
                throw new DeploymentException("Invalid maintenance file record.");
            SafeFiles.Child(root, file.Path);
        }
        if (state.ToolDirectory != "" && !SafeFiles.FullPath(state.ToolDirectory)
                .StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("Invalid maintenance tool directory.");
    }
    public void Recover()
    {
        if (!File.Exists(TransactionFile)) return;
        var tx = SafeFiles.Read<Transaction>(TransactionFile);
        ValidateState(tx.Previous);
        ValidateInstance(tx.Next);
        VerifyTool(tx.Next);
        // Committed state is written before marking the journal committed.
        if (File.Exists(StateFile) && SafeFiles.Read<InstallationState>(StateFile).Current?.Id == tx.Next.Id)
        {
            system.VerifyRegistration(tx.Next);
            File.Delete(TransactionFile);
            return;
        }
        report("Recovering the interrupted installation.");
        system.Restore(tx.Snapshot, tx.Next.Directory);
        tx.Previous.ToolDirectory = tx.Next.Directory;
        tx.Previous.Retired.Add(tx.Next); // retain the tool used by compatibility entrypoints
        SafeFiles.Write(StateFile, tx.Previous);
        File.Delete(TransactionFile);
    }
    private static void VerifyTool(Instance instance)
    {
        foreach (var file in instance.Files.Where(f => new[] { "KeyKeyDeployment.exe", "KeyKeyTsf_x64.dll", "KeyKeyTsf_x86.dll", "KeyKeyRegistration_x86.exe" }
                                                       .Contains(f.Path, StringComparer.OrdinalIgnoreCase)))
            if (!File.Exists(SafeFiles.Child(instance.Directory, file.Path)) ||
                SafeFiles.Hash(SafeFiles.Child(instance.Directory, file.Path)) != file.Sha256)
                throw new DeploymentException("The maintenance tool or TSF DLL was modified. Restore it from a trusted package.");
    }
    private PackageManifest ReadPackage(string packageDirectory)
    {
        var manifest = SafeFiles.Read<PackageManifest>(SafeFiles.Child(packageDirectory, "PackageManifest.json"));
        if (manifest.SchemaVersion != 1 || !Regex.IsMatch(manifest.Version, @"^\d+\.\d+\.\d+(?:\.\d+)?$") ||
            !Version.TryParse(manifest.Version, out var version))
            throw new DeploymentException("Invalid package version.");
        if (manifest.Architecture != system.Architecture)
            throw new DeploymentException("The package does not match native Windows architecture.", 1633);
        SafeFiles.ValidateList(manifest.Files);
        SafeFiles.ValidatePayload(manifest.Files);
        var required = new List<string> { "KeyKeyTsf_x86.dll", "KeyKeySettings.exe", "KeyKeySettingsBackend.dll",
                                         "KeyKeyDeployment.exe", "KeyKeyRegistration_x86.exe", "Databases\\KeyKey.db" };
        if (manifest.Architecture == "x64") required.Add("KeyKeyTsf_x64.dll");
        if (required.Any(p => !manifest.Files.Any(f => f.Path.Equals(p, StringComparison.OrdinalIgnoreCase))))
            throw new DeploymentException("Incomplete installation payload.");
        foreach (var file in manifest.Files)
        {
            var path = SafeFiles.Child(System.IO.Path.Combine(packageDirectory, "Payload"), file.Path);
            if (!File.Exists(path) || SafeFiles.Hash(path) != file.Sha256)
                throw new DeploymentException($"Package checksum failed: {file.Path}");
            system.VerifyFile(path, manifest.Signed);
            if (file.Path.Replace('/', '\\').Equals("Databases\\KeyKey.db", StringComparison.OrdinalIgnoreCase))
                system.VerifyDatabase(path);
        }
        return manifest;
    }
    private static string Fingerprint(PackageManifest manifest) => Convert.ToHexStringLower(SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(manifest, SafeFiles.Json))));
    private Instance Stage(string packageDirectory, PackageManifest manifest)
    {
        var fingerprint = Fingerprint(manifest);
        var requiredBytes = manifest.Files.Sum(f => new FileInfo(SafeFiles.Child(
            System.IO.Path.Combine(packageDirectory, "Payload"), f.Path)).Length) +
            new FileInfo(SafeFiles.Child(System.IO.Path.Combine(packageDirectory, "Payload"), "KeyKeyDeployment.exe")).Length +
            5L * 1024 * 1024;
        if (new DriveInfo(System.IO.Path.GetPathRoot(root)!).AvailableFreeSpace < requiredBytes)
            throw new DeploymentException("Not enough free space to stage a complete installation.");
        var name = manifest.Version + "-" + fingerprint[..12];
        var directory = SafeFiles.Child(root, name);
        if (Directory.Exists(directory) || system.IsPendingDelete(directory))
            directory = SafeFiles.Child(root, manifest.Version + "-" + Guid.NewGuid().ToString("N"));
        var next = new Instance { Directory = directory, Version = manifest.Version,
            Architecture = manifest.Architecture, Fingerprint = fingerprint, Files = manifest.Files };
        system.PrepareDirectory(directory);
        foreach (var file in next.Files)
        {
            var destination = SafeFiles.Child(directory, file.Path);
            system.PrepareDirectory(System.IO.Path.GetDirectoryName(destination)!);
            File.Copy(SafeFiles.Child(System.IO.Path.Combine(packageDirectory, "Payload"), file.Path), destination, false);
        }
        if (!SafeFiles.Matches(directory, next.Files)) throw new DeploymentException("Staged payload verification failed.");
        return next;
    }
    public void PrepareLegacyRemoval(string packageDirectory)
    {
        system.ValidateRoot(root);
        var state = Inspect();
        if (state.Current == null || !state.Current.Legacy) return;
        Instance tool;
        if (state.ToolDirectory == "")
        {
            var package = ReadPackage(packageDirectory);
            system.PrepareDirectory(root);
            tool = Stage(packageDirectory, package);
            state.Retired.Add(tool);
            state.ToolDirectory = tool.Directory;
            SafeFiles.Write(StateFile, state);
        }
        else
        {
            tool = state.Retired.FirstOrDefault(p => p.Directory.Equals(state.ToolDirectory, StringComparison.OrdinalIgnoreCase))
                ?? throw new DeploymentException("The legacy maintenance payload is not recorded.");
            VerifyTool(tool);
        }
        // Retry takeover after an interruption; a recorded tool alone does
        // not prove the compatibility entrypoints were successfully replaced.
        system.TakeOverLegacyEntrypoints(root, tool.Directory, file =>
        {
            state.MaintenanceFiles = MergeMaintenance(state.MaintenanceFiles, [file]);
            SafeFiles.Write(StateFile, state);
        });
        // Keep a usable entry even if removal is interrupted. No registration
        // or keyboard selection is changed by preparing maintenance alone.
        system.PublishCleanup(root, true);
    }
    public int Install(string packageDirectory, bool repair = false)
    {
        system.ValidateRoot(root);
        system.PrepareDirectory(root);
        Recover();
        var previous = Inspect();
        // Reboot may have removed every queued payload. Drop only absent,
        // no-longer-pending records before a new instance can reuse its path.
        previous.Retired.RemoveAll(p => !Directory.Exists(p.Directory) && !system.IsPendingDelete(p.Directory));
        if (previous.Removing && !repair) throw new DeploymentException("Finish the pending removal or use repair before installing.");
        var manifest = ReadPackage(packageDirectory);
        var version = Version.Parse(manifest.Version);
        var fingerprint = Fingerprint(manifest);
        if (previous.Current != null && Version.TryParse(previous.Current.Version, out var oldVersion))
        {
            if (oldVersion > version) throw new DeploymentException("A newer version is already installed.", 1638);
            if (oldVersion == version && previous.Current.Fingerprint == fingerprint &&
                SafeFiles.Matches(previous.Current.Directory, previous.Current.Files))
            {
                try
                {
                    system.VerifyRegistration(previous.Current);
                    RetireProfiles(previous.Current);
                    system.Publish(previous.Current, root);
                    system.TakeOverLegacyEntrypoints(root, previous.ToolDirectory, file =>
                    {
                        previous.MaintenanceFiles = MergeMaintenance(previous.MaintenanceFiles, [file]);
                        SafeFiles.Write(StateFile, previous);
                    });
                    report("This build is already installed.");
                    return 0;
                }
                catch (DeploymentException) { repair = true; }
            }
            if (oldVersion == version && manifest.Signed && previous.Current.Fingerprint != fingerprint &&
                !previous.Current.Legacy && !repair)
                throw new DeploymentException("A different official build has the same version.", 1638);
        }
        var next = Stage(packageDirectory, manifest);
        var tx = new Transaction { Previous = previous, Next = next, Snapshot = system.Capture(next.Directory) };
        SafeFiles.Write(TransactionFile, tx);
        try
        {
            tx.Phase = "Registering";
            SafeFiles.Write(TransactionFile, tx);
            system.Register(next);
            system.VerifyRegistration(next);
            system.Publish(next, root);
            system.TakeOverLegacyEntrypoints(root, next.Directory, file =>
            {
                previous.MaintenanceFiles = MergeMaintenance(previous.MaintenanceFiles, [file]);
                SafeFiles.Write(TransactionFile, tx);
            });
            var state = new InstallationState { Current = next, ToolDirectory = next.Directory, Retired = previous.Retired,
                MaintenanceFiles = previous.MaintenanceFiles };
            if (previous.Current != null) state.Retired.Add(previous.Current);
            SafeFiles.Write(StateFile, state);
            File.Delete(TransactionFile);
        }
        catch (Exception failure)
        {
            try { Recover(); }
            catch (Exception rollback) { throw new DeploymentException(
                $"Installation failed ({failure.Message}); recovery also failed ({rollback.Message}). Re-run this installer to recover."); }
            throw new DeploymentException($"Installation failed and registration was restored: {failure.Message}");
        }
        RetireProfiles(next);
        report(previous.Current == null
            ? "Installed. Add chichi77 KeyKey yourself in Windows Settings > Time & language > Language options > Add a keyboard."
            : "Upgraded. Sign out and back in to load the new input method. The shared entry is preserved; if you used an old regional entry, add the shared KeyKey keyboard in Windows Settings.");
        return 0;
    }
    private void RetireProfiles(Instance instance)
    {
        try { report(system.RetireLegacyProfiles(instance)); }
        catch (Exception error) { report("Installed, but legacy profile cleanup needs a retry: " + error.Message); }
    }
    public int Uninstall(string? owner = null)
    {
        Recover();
        var state = Inspect();
        if (state.Current == null) return Cleanup(state);
        if (owner != null && owner != state.Current.Id)
            throw new DeploymentException("This is an old uninstall entry. Use the current entry in Windows Settings.", 1638);
        if (state.ToolDirectory == "")
            throw new DeploymentException("Install the new maintenance tool before removing this legacy installation.");
        var toolInstance = state.Current.Directory.Equals(state.ToolDirectory, StringComparison.OrdinalIgnoreCase)
            ? state.Current : state.Retired.FirstOrDefault(p => p.Directory.Equals(state.ToolDirectory, StringComparison.OrdinalIgnoreCase));
        if (toolInstance == null) throw new DeploymentException("Maintenance payload is not recorded.");
        VerifyTool(toolInstance);
        ValidateInstance(state.Current);
        // Persist retry state before TSF calls. ARP remains until all work is arranged.
        bool retry = state.Removing;
        state.Removing = true;
        SafeFiles.Write(StateFile, state);
        system.Unregister(state.Current, state.ToolDirectory, retry);
        state.Retired.Add(state.Current);
        state.Current = null;
        state.Removing = false;
        SafeFiles.Write(StateFile, state);
        return Cleanup(state);
    }
    private static List<PackageFile> MergeMaintenance(IEnumerable<PackageFile> old, IEnumerable<PackageFile> added) =>
        old.Concat(added).GroupBy(f => f.Path, StringComparer.OrdinalIgnoreCase).Select(g => g.Last()).ToList();
    public int Cleanup(InstallationState? state = null)
    {
        if (state == null) { Recover(); state = Inspect(); }
        if (state.Current != null)
        {
            throw new DeploymentException("An installation is active. Use its current uninstall entry in Windows Settings; an old cleanup entry cannot remove it.", 1638);
        }
        try { return CleanupFiles(state); }
        catch
        {
            // Keep a verified retry entry if cleanup fails. Do not replace the
            // original failure with an error while trying to publish recovery.
            try { system.PublishCleanup(root); }
            catch (Exception error) { report("Could not refresh the cleanup retry entry: " + error.Message); }
            throw;
        }
    }
    private int CleanupFiles(InstallationState state)
    {
        state.RemovalQueued = false;
        SafeFiles.Write(StateFile, state);
        var remaining = new List<Instance>();
        bool reboot = false;
        foreach (var instance in state.Retired)
        {
            ValidateInstance(instance);
            var known = instance.Files.Where(f =>
            {
                var path = SafeFiles.Child(instance.Directory, f.Path);
                if (!File.Exists(path)) return false;
                if (SafeFiles.Hash(path) == f.Sha256) return true;
                report($"Keeping a modified file: {path}");
                return false;
            }).ToList();
            if (known.Count > 0 && system.IsInUse(known.Select(f => SafeFiles.Child(instance.Directory, f.Path))))
            {
                foreach (var file in known) system.ScheduleDelete(SafeFiles.Child(instance.Directory, file.Path));
                remaining.Add(instance);
                reboot = true;
            }
            else foreach (var file in known)
            {
                var path = SafeFiles.Child(instance.Directory, file.Path);
                try { File.Delete(path); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    // Mapped EXE/DLL images can return access denied rather than
                    // sharing violation. Defer only the verified product file;
                    // failure to arrange deletion must still abort cleanup.
                    system.ScheduleDelete(path); reboot = true;
                }
            }
            // Remove only empty directories, or queue them after all their
            // remaining children. Never queue the shared installation root.
            var queuedDirectories = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var directory in instance.Files.Select(f => System.IO.Path.GetDirectoryName(
                         SafeFiles.Child(instance.Directory, f.Path))!).Append(instance.Directory)
                         .Where(p => !p.Equals(root, StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase)
                         .OrderByDescending(p => p.Length))
            {
                if (!Directory.Exists(directory)) continue;
                var children = Directory.GetFileSystemEntries(directory);
                if (children.Length == 0)
                {
                    try { Directory.Delete(directory); }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                    { system.ScheduleDelete(directory); queuedDirectories.Add(directory); reboot = true; }
                }
                else if (children.All(p => Directory.Exists(p) ? queuedDirectories.Contains(p) : system.IsPendingDelete(p)))
                { system.ScheduleDelete(directory); queuedDirectories.Add(directory); reboot = true; }
            }
            if (!remaining.Contains(instance) && known.Any(f => File.Exists(SafeFiles.Child(instance.Directory, f.Path)))) remaining.Add(instance);
        }
        state.Retired = remaining;
        // Include maintenance in the SAME removal pass. Leaving it until after
        // reboot caused a second uninstall and self-deletion access denied.
        {
            var keep = new List<PackageFile>();
            foreach (var file in state.MaintenanceFiles.OrderBy(f => f.Path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)))
            {
                var path = SafeFiles.Child(root, file.Path);
                if (!File.Exists(path)) continue;
                if (SafeFiles.Hash(path) != file.Sha256) { report($"Keeping modified maintenance file: {path}"); continue; }
                try { File.Delete(path); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    system.ScheduleDelete(path); reboot = true; keep.Add(file);
                }
            }
            state.MaintenanceFiles = keep;
        }
        state.RemovalQueued = true;
        SafeFiles.Write(StateFile, state);
        system.RemoveProductEntry();
        report(reboot ? "解除安裝已完成，使用中的程式檔案已排定於重新開機時刪除。請儲存工作後重新開機，不需要再次解除安裝。個人資料保留。 / Uninstall complete. Restart Windows to delete in-use files; no second uninstall is needed. Personal data is kept."
                      : "Input method removed. User preferences and learning data were kept.");
        return reboot ? 3010 : 0;
    }
}
