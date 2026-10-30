// Keeps the passwords the server holds (sqlserver/connection) away from other processes
// running as the same user, as locksmith.nvim does for NeoVim. On Linux:
// - non-dumpable (prctl PR_SET_DUMPABLE 0): /proc/<pid>/fd (the stdin pipe), mem and environ
//   refuse them, ptrace too, and no core dump is written;
// - no .NET diagnostics server: its IPC socket would let them attach a profiler, which reads
//   memory. It can only be turned off before the runtime starts, so the process re-executes
//   itself with DOTNET_EnableDiagnostics=0 when that isn't already set.
// Both happen before the first message is read. Elsewhere (Windows) nothing is done.
using System.Runtime.InteropServices;
using System.Text;

namespace SqlServerAssist;

static class Hardening
{
    const int PR_SET_DUMPABLE = 4;
    const string Diagnostics = "DOTNET_EnableDiagnostics";

    [DllImport("libc", SetLastError = true)]
    static extern int prctl(int option, nuint arg2, nuint arg3, nuint arg4, nuint arg5);

    [DllImport("libc", SetLastError = true)]
    static extern int execve(string path, string?[] argv, string?[] envp);

    public static void Apply(string[] args)
    {
        if (!OperatingSystem.IsLinux()) return;
        if (Environment.GetEnvironmentVariable(Diagnostics) != "0") Reexecute();
        else RemoveStaleSocket();
        if (prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0)
            Console.Error.WriteLine($"sqlserver-assist: could not make the process non-dumpable (errno {Marshal.GetLastWin32Error()})");
    }

    // The socket the runtime opened before Reexecute stays as a file, closed (the PID is the
    // same across execve, so only this process's are named after it)
    static void RemoveStaleSocket()
    {
        try
        {
            foreach (var socket in Directory.EnumerateFiles(Path.GetTempPath(), $"dotnet-diagnostic-{Environment.ProcessId}-*-socket"))
                File.Delete(socket);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    // The same program and arguments (from /proc/self, which holds them whether it runs as
    // the apphost or as `dotnet SqlServerAssist.dll`), its environment plus the variable.
    // On failure it carries on with diagnostics on, and says so
    static void Reexecute()
    {
        try
        {
            var argv = File.ReadAllText("/proc/self/cmdline", Encoding.UTF8).TrimEnd('\0').Split('\0');
            var env = Environment.GetEnvironmentVariables().Keys.Cast<string>()
                .Where(k => k != Diagnostics)
                .Select(k => k + "=" + Environment.GetEnvironmentVariable(k))
                .Append(Diagnostics + "=0");
            execve("/proc/self/exe", argv.Cast<string?>().Append(null).ToArray(), env.Cast<string?>().Append(null).ToArray());
            Console.Error.WriteLine($"sqlserver-assist: could not restart without the diagnostics server (errno {Marshal.GetLastWin32Error()})");
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("sqlserver-assist: could not restart without the diagnostics server: " + e.Message);
        }
    }
}
