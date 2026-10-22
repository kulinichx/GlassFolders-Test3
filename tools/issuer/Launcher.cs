using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

// GUI subsystem executable: no cmd.exe, terminal window or console flash.
internal static class GlassFoldersLauncher {
    private static string Quote(string argument) {
        // Paths passed here are filenames, which cannot contain a quote.
        // Trim trailing separators so the closing quote cannot be escaped.
        return "\"" + argument.TrimEnd('\\', '/') + "\"";
    }

    [STAThread]
    private static int Main(string[] args) {
        bool check = args.Length == 1 && args[0] == "--check";
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        try {
            string script = Path.Combine(directory, "GlassFoldersIssuer.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("找不到签发程序，请把启动器和签发器文件放在同一文件夹。", script);
            string siblingData = Path.GetFullPath(Path.Combine(directory, "..", "GlassFolders-Issuer-Private"));
            string data = File.Exists(Path.Combine(siblingData, "issuer-key.dpapi"))
                ? siblingData : Path.Combine(directory, "private");
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            var start = new ProcessStartInfo {
                FileName = powershell,
                Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " + Quote(script)
                    + " -DataDirectory " + Quote(data) + (check ? " -UISmokeTest" : ""),
                WorkingDirectory = directory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var process = Process.Start(start)) {
                var output = process.StandardOutput.ReadToEndAsync();
                var error = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                string details = output.Result + error.Result;
                if (check) File.WriteAllText(Path.Combine(directory, "launcher-check.log"),
                    "ExitCode: " + process.ExitCode + Environment.NewLine + details, Encoding.UTF8);
                else if (process.ExitCode != 0) MessageBox.Show(
                    "签发器启动或运行失败。请确认文件完整、私钥目录正确，并关闭已打开的签发器。\n\n" + details,
                    "GlassFolders 签发器", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return process.ExitCode;
            }
        } catch (Exception error) {
            if (check) File.WriteAllText(Path.Combine(directory, "launcher-check.log"), error.ToString(), Encoding.UTF8);
            else MessageBox.Show(error.Message, "GlassFolders 签发器", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
    }
}
