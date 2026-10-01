using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json;
using System.Runtime.InteropServices;

namespace KeyKey.Deployment;
internal static class Program
{
    private static string? logPath;
    private static string operation = "";
    private static bool quiet;
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBox(IntPtr window, string text, string title, uint type);
    private static int Completed(int code)
    {
        if (!quiet && operation is "uninstall" or "cleanup")
            MessageBox(IntPtr.Zero, code == 3010
                ? "琦琦輸入法已解除安裝。\n\n部分程式檔案仍在使用中，Windows 已接受於重新開機時刪除的排程。請儲存工作後重新開機，不需要再次解除安裝。\n\n個人設定、自訂詞及學習資料保留。\n\nKeyKey is uninstalled. Restart Windows to delete in-use files. No second uninstall is needed. Personal data is kept."
                : "琦琦輸入法已移除，檔案清理已完成；不需要再次解除安裝。\n個人設定、自訂詞及學習資料保留。\n\nKeyKey removal and file cleanup are complete. Personal data was kept.",
                code == 3010 ? "琦琦輸入法：請重新開機完成移除" : "琦琦輸入法：移除完成", 0x40);
        return code;
    }
    private static void Report(string message)
    {
        Console.WriteLine(message);
        if (logPath == null) return;
        SafeFiles.NoLinks(logPath);
        File.AppendAllText(logPath, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
    }
    private static int Failure(string message, int code)
    {
        Console.Error.WriteLine(message);
        try { Report($"FAILED ({code}): {message}"); } catch { /* preserve the original error */ }
        if (!quiet && operation is "uninstall" or "cleanup")
            MessageBox(IntPtr.Zero, $"操作未完成（{code}）。請保留安裝包並查閱 Deployment.log。\n{message}", "chichi77 KeyKey", 0x10);
        return code;
    }
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            operation = args.Length == 0 ? "uninstall" : args[0];
            quiet = args.Contains("--quiet");
            if (!OperatingSystem.IsWindowsVersionAtLeast(10) ||
                Environment.Is64BitOperatingSystem != Environment.Is64BitProcess)
                throw new DeploymentException("Use the package matching native Windows 10 or later architecture.", 1633);
            string? Option(string name)
            {
                var index = Array.IndexOf(args, name);
                if (index < 0) return null;
                if (index + 1 == args.Length || args[index + 1].StartsWith("--"))
                    throw new DeploymentException($"Missing argument for {name}.");
                return args[index + 1];
            }
            if (operation is not ("inspect" or "install" or "repair" or "uninstall" or "cleanup"))
                throw new DeploymentException("Expected inspect, install, repair, uninstall, or cleanup.");
            if (operation != "inspect")
            {
                using var identity = WindowsIdentity.GetCurrent();
                if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
                {
                    if (args.Contains("--quiet")) throw new DeploymentException("Administrator permission is required.", 5);
                    var start = new ProcessStartInfo(Environment.ProcessPath!)
                        { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
                    foreach (var arg in args.Length == 0 ? new[] { "uninstall" } : args) start.ArgumentList.Add(arg);
                    using var elevated = Process.Start(start)!;
                    elevated.WaitForExit();
                    return elevated.ExitCode;
                }
            }
            if (operation == "inspect")
            {
                var readSystem = new WindowsSystem();
                var state = new DeploymentEngine(WindowsSystem.DefaultRoot, readSystem).Inspect();
                Console.WriteLine(JsonSerializer.Serialize(new { State = state,
                    System = readSystem.InspectRegistration(state) }, SafeFiles.Json));
                return 0;
            }
            using var mutex = new Mutex(false, @"Global\chichi77KeyKeyDeployment");
            bool acquired;
            try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) return 1618;
            try
            {
                var system = new WindowsSystem();
                if (operation != "inspect")
                {
                    system.ValidateRoot(WindowsSystem.DefaultRoot);
                    system.PrepareDirectory(WindowsSystem.DefaultRoot);
                    logPath = SafeFiles.Child(WindowsSystem.DefaultRoot, "Deployment.log");
                    if (File.Exists(logPath) && new FileInfo(logPath).Length > 1024 * 1024)
                        File.WriteAllText(logPath, "");
                    Report("Starting " + operation);
                }
                var engine = new DeploymentEngine(WindowsSystem.DefaultRoot, system, Report);
                switch (operation)
                {
                    case "install": case "repair":
                        return engine.Install(Option("--package") ?? throw new DeploymentException("--package is required."), operation == "repair");
                    case "uninstall":
                        var package = Option("--package");
                        if (package != null) engine.PrepareLegacyRemoval(package);
                        return Completed(engine.Uninstall(Option("--owner")));
                    case "cleanup": return Completed(engine.Cleanup());
                    default: return 1;
                }
            }
            finally { mutex.ReleaseMutex(); }
        }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223) { return 1602; }
        catch (DeploymentException error) { return Failure(error.Message, error.Code); }
        catch (Exception error) { return Failure(error.Message, 1); }
    }
}
