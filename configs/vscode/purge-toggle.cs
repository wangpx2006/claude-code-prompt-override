// VS Code 模式切换：建/删 ~/.claude/purge-off，双击一下换模式
//
// 编译：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -codepage:65001 ^
//     -target:winexe -optimize+ -win32icon:"%USERPROFILE%\.claude\purge-toggle.ico" ^
//     -out:"%USERPROFILE%\Desktop\VS Code 模式切换.exe" "%USERPROFILE%\.claude\purge-toggle.cs"
//
// 带 /silent 参数时不弹窗，只切换（给脚本和自测用）。

using System;
using System.IO;
using System.Windows.Forms;

class PurgeToggle
{
    [STAThread]
    static void Main(string[] args)
    {
        string flag = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".claude\purge-off");
        bool silent = Array.IndexOf(args, "/silent") >= 0;

        bool nowNormal;
        try
        {
            if (File.Exists(flag))
            {
                File.Delete(flag);
                nowNormal = false;
            }
            else
            {
                Directory.CreateDirectory(Path.GetDirectoryName(flag));
                File.WriteAllText(flag, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " normal mode\r\n");
                nowNormal = true;
            }
        }
        catch (Exception ex)
        {
            if (!silent) MessageBox.Show("切换失败：" + ex.Message, "Claude Code 模式切换", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.ExitCode = 1;
            return;
        }

        if (silent) return;

        string title = nowNormal ? "已切到：正常模式" : "已切到：破甲模式";
        string body = nowNormal
            ? "VS Code 里新建一个 Claude 对话，走原版 prompt。\n\n再双击这个图标就切回来。"
            : "VS Code 里新建一个 Claude 对话，走自定义 prompt。\n\n再双击这个图标就切回原版。";
        MessageBox.Show(body, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
}
