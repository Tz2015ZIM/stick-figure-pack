// stickhost.cs
// The process he runs in. stickman.ps1 compiles one of these for each name he
// goes by (see Get-Body), because Task Manager lists a process under the name
// baked into its exe: 'Stick figure' for his plain self, or whatever you named
// the symbol when you converted him.
//
// All it holds is a PowerShell runspace running stickman.ps1 from the folder
// above it, so there is no console window and no powershell.exe.

using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;

[assembly: AssemblyTitle(Body.Name)]        // the name Task Manager shows
[assembly: AssemblyProduct("Desktop Stickman")]
[assembly: AssemblyVersion("1.0.0.0")]

static class Body {
    public const string Name = "Stick figure";

    [STAThread]     // WinForms and the tray menu want a single-threaded apartment
    static int Main(string[] args) {
        string log = Path.Combine(Path.GetTempPath(), "stickman-error.log");
        try {
            string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            string ps1 = Path.Combine(dir, "stickman.ps1");
            if (!File.Exists(ps1)) ps1 = Path.Combine(Path.GetDirectoryName(dir), "stickman.ps1");

            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            // lets the script know which exe it is in, so it does not move again
            iss.Variables.Add(new SessionStateVariableEntry("StickBody", Name, "the process name he runs under"));

            using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (PowerShell ps = PowerShell.Create()) {
                    ps.Runspace = rs;
                    ps.AddCommand(ps1);
                    // -Name value pairs go straight through as the script's parameters
                    for (int i = 0; i + 1 < args.Length; i += 2)
                        ps.AddParameter(args[i].TrimStart('-'), args[i + 1]);
                    ps.Invoke();
                    foreach (ErrorRecord e in ps.Streams.Error)
                        Trail(log, e.ToString() + (e.InvocationInfo != null ? "  @ " + e.InvocationInfo.ScriptLineNumber : ""));
                }
            }
            return 0;
        } catch (Exception e) {
            Trail(log, e.Message);
            return 1;
        }
    }

    static void Trail(string log, string msg) {
        try { File.AppendAllText(log, DateTime.Now.ToString("s") + "  [" + Name + "] " + msg + Environment.NewLine); }
        catch { }
    }
}
