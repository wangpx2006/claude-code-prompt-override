// Claude Code (Purge) 的 VS Code 入口包装器
//
// VS Code 扩展在设置 claudeCode.claudeProcessWrapper 之后，会用这个 exe 当作
// 启动器：命令变成 purge-wrapper.exe <扩展自带的 claude.exe> <原来的所有参数>。
// 所以这里把 arg[0] 当真正的目标程序，给它补上 --system-prompt-file 再启动。
//
// 只在「会话类」调用时注入（带 --input-format 或 --output-format），
// auth status / --version / mcp 这类子命令原样透传，避免解析报错。
//
// 编译（Windows 自带 .NET Framework 的 csc 就够，不用装 VS）：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -codepage:65001 ^
//     -optimize+ -target:exe -out:"%USERPROFILE%\.claude\purge-wrapper.exe" ^
//     "%USERPROFILE%\.claude\purge-wrapper.cs"
//
// 注意 csc 在 Git Bash 里要用 - 开头，写成 /nologo 会被 MSYS 当成路径转掉。

using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;

class PurgeWrapper
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpInfo, uint cbInfoLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    const int JobObjectExtendedLimitInformation = 9;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    static string HomeDir()
    {
        string h = Environment.GetEnvironmentVariable("USERPROFILE");
        if (string.IsNullOrEmpty(h)) h = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return h;
    }

    static void Log(string line)
    {
        try
        {
            string p = Path.Combine(HomeDir(), @".claude\purge-wrapper.log");
            FileInfo fi = new FileInfo(p);
            if (fi.Exists && fi.Length > 200 * 1024) File.WriteAllText(p, "");
            File.AppendAllText(p, DateTime.Now.ToString("HH:mm:ss") + " " + line + Environment.NewLine, Encoding.UTF8);
        }
        catch { }
    }

    // 按 CommandLineToArgvW 的规则加引号，参数里带空格/引号也不会被拆坏
    static string Quote(string s)
    {
        if (s.Length > 0 && s.IndexOfAny(new char[] { ' ', '\t', '"', '\n', '\v' }) < 0) return s;
        StringBuilder sb = new StringBuilder();
        sb.Append('"');
        int bs = 0;
        foreach (char c in s)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"')
            {
                sb.Append('\\', bs * 2 + 1);
                sb.Append('"');
                bs = 0;
                continue;
            }
            if (bs > 0) { sb.Append('\\', bs); bs = 0; }
            sb.Append(c);
        }
        if (bs > 0) sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("purge-wrapper: 缺少目标程序路径");
            return 2;
        }

        string target = args[0];
        if (!File.Exists(target))
        {
            Console.Error.WriteLine("purge-wrapper: 目标程序不存在: " + target);
            return 3;
        }

        bool isSession = false;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i] == "--input-format" || args[i] == "--output-format") { isSession = true; break; }
        }

        string promptFile = Path.Combine(HomeDir(), @".claude\purge-system-prompt.md");

        StringBuilder cmd = new StringBuilder();
        if (isSession && File.Exists(promptFile))
        {
            cmd.Append("--system-prompt-file ");
            cmd.Append(Quote(promptFile));
        }
        for (int i = 1; i < args.Length; i++)
        {
            if (cmd.Length > 0) cmd.Append(' ');
            cmd.Append(Quote(args[i]));
        }

        Log((isSession ? "inject " : "pass   ") + target + " " + cmd.ToString());

        ProcessStartInfo psi = new ProcessStartInfo(target, cmd.ToString());
        psi.UseShellExecute = false;
        psi.WorkingDirectory = Directory.GetCurrentDirectory();

        IntPtr job = IntPtr.Zero;
        try
        {
            if (Environment.GetEnvironmentVariable("CLAUDE_PURGE_NO_JOB") != "1")
            {
                job = CreateJobObject(IntPtr.Zero, null);
                if (job != IntPtr.Zero)
                {
                    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                    int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
                    IntPtr buf = Marshal.AllocHGlobal(len);
                    try
                    {
                        Marshal.StructureToPtr(info, buf, false);
                        if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, buf, (uint)len))
                        {
                            CloseHandle(job); job = IntPtr.Zero;
                        }
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
            }

            Process p = Process.Start(psi);
            if (p == null) { Console.Error.WriteLine("purge-wrapper: 启动失败"); return 4; }

            if (job != IntPtr.Zero) AssignProcessToJobObject(job, p.Handle);

            p.WaitForExit();
            return p.ExitCode;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("purge-wrapper: " + ex.Message);
            Log("error  " + ex.Message);
            return 5;
        }
        finally
        {
            if (job != IntPtr.Zero) CloseHandle(job);
        }
    }
}
