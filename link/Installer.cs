// --install and --uninstall: everything the link needs for this Windows user, and nothing for any
// other. No administrator rights.
//   - the link itself, copied to %LOCALAPPDATA%\ActionInna (--dev keeps it where it was built)
//   - its manifest for the browsers, and the registry keys that point Chrome, Edge, Brave and
//     Chromium at it (HKEY_CURRENT_USER)
//   - the link's key in MT5's Common\Files\ActionInna
//   - ActionInna.ex5 copied into every MT5 found (or the ones named with --mt5), unless that
//     terminal's Experts\ActionInna is linked to a repository (the development set-up)
//   - link.json: the terminals the link starts when the panel opens
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using Microsoft.Win32;

static class Installer
{
    const string HostName = "com.actioninna.link";

    // The extension's ids in the stores, once it is published. --extension-id adds more.
    static readonly string[] ExtensionIds = { };

    // The unpacked panel's id, from the key in extension/manifest.json, allowed with --dev only. That
    // key is public, so any unpacked extension can carry it and have this id.
    const string DevExtensionId = "knlcnmdecbojpcoggfahghifkbalkpdk";

    static readonly string[] Browsers =
    {
        "Software\\Google\\Chrome\\NativeMessagingHosts\\",
        "Software\\Microsoft\\Edge\\NativeMessagingHosts\\",
        "Software\\BraveSoftware\\Brave-Browser\\NativeMessagingHosts\\",
        "Software\\Chromium\\NativeMessagingHosts\\"
    };

    static string Manifest
    {
        get { return Path.Combine(Paths.Home, HostName + ".json"); }
    }

    public static int Install(string[] args)
    {
        bool dev = Program.HasFlag(args, "--dev");
        bool registry = !Program.HasFlag(args, "--no-registry");
        string self = Assembly.GetExecutingAssembly().Location;
        Directory.CreateDirectory(Paths.Home);
        string exe = dev ? self : Path.Combine(Paths.Home, "ActionInnaLink.exe");
        if (!SamePath(self, exe))
            File.Copy(self, exe, true);
        Console.WriteLine("ActionInna link: " + exe);

        List<string> ids = new List<string>(ExtensionIds);
        if (dev)
            ids.Add(DevExtensionId);
        ids.AddRange(Program.Values(args, "--extension-id"));
        if (ids.Count == 0)
            Console.WriteLine("No extension may start the link yet: run this again with --extension-id <the panel's id>.");
        File.WriteAllText(Manifest, ManifestJson(exe, ids), new UTF8Encoding(false));
        if (registry)
        {
            foreach (string b in Browsers)
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(b + HostName))
                    k.SetValue("", Manifest);
            Console.WriteLine("Chrome, Edge, Brave and Chromium may start it (this Windows user only).");
        }
        LinkKey.LoadOrCreate();

        string ex5 = Path.Combine(Path.GetDirectoryName(self), "ActionInna.ex5");
        LinkConfig config = new LinkConfig();
        List<Mt5Terminal> found = FindTerminals(Program.Values(args, "--mt5"));
        if (found.Count == 0)
            Console.WriteLine("No MT5 found. Run this again with --mt5 \"<MT5 folder>\" (in MT5: File > Open Data Folder).");
        foreach (Mt5Terminal t in found)
        {
            string experts = Path.Combine(t.DataFolder, "MQL5", "Experts", "ActionInna");
            string what;
            if (IsJunction(experts))
                what = "linked to a repository (development set-up), left as it is";
            else if (File.Exists(ex5))
            {
                Directory.CreateDirectory(experts);
                File.Copy(ex5, Path.Combine(experts, "ActionInna.ex5"), true);
                what = "ActionInna.ex5 copied";
            }
            else
                what = "found";
            Console.WriteLine("MT5 " + t.Name + " (" + t.DataFolder + "): " + what);
            config.Terminals.Add(t);
        }
        config.Save();
        Paths.Log("installed: " + exe + ", " + found.Count + " MT5 terminal(s)");

        Console.WriteLine();
        Console.WriteLine("Left to do:");
        Console.WriteLine("  1. In MT5: Navigator > Refresh, put ActionInna on one chart, and turn on Algo Trading.");
        Console.WriteLine("  2. In Chrome: add the ActionInna extension, then open its side panel.");
        Pause(args);
        return 0;
    }

    public static int Uninstall(string[] args)
    {
        if (!Program.HasFlag(args, "--no-registry"))
            foreach (string b in Browsers)
                Registry.CurrentUser.DeleteSubKeyTree(b + HostName, false);
        Delete(Manifest);
        Delete(Paths.ConfigFile);
        Delete(Paths.KeyFile);
        string installed = Path.Combine(Paths.Home, "ActionInnaLink.exe");
        string self = Assembly.GetExecutingAssembly().Location;
        if (SamePath(self, installed))
            Console.WriteLine("Delete " + installed + " once this window is closed.");
        else
            Delete(installed);
        Paths.Log("uninstalled");
        Console.WriteLine("The ActionInna link is removed. ActionInna.ex5 stays in MT5: remove it there if you no longer want it.");
        Pause(args);
        return 0;
    }

    // Every MT5 data folder under %APPDATA%\MetaQuotes\Terminal, or the folders given with --mt5:
    // a data folder (with origin.txt) or a portable install (terminal64.exe next to MQL5).
    static List<Mt5Terminal> FindTerminals(List<string> chosen)
    {
        List<Mt5Terminal> list = new List<Mt5Terminal>();
        if (chosen.Count > 0)
        {
            foreach (string folder in chosen)
            {
                Mt5Terminal t = FromFolder(folder);
                if (t != null)
                    list.Add(t);
                else
                    Console.WriteLine("Not an MT5 folder: " + folder);
            }
            return list;
        }
        if (!Directory.Exists(Paths.Terminals))
            return list;
        foreach (string d in Directory.GetDirectories(Paths.Terminals))
        {
            Mt5Terminal t = FromFolder(d);
            if (t != null)
                list.Add(t);
        }
        return list;
    }

    static Mt5Terminal FromFolder(string folder)
    {
        if (!Directory.Exists(Path.Combine(folder, "MQL5")))
            return null;
        Mt5Terminal t = new Mt5Terminal();
        t.DataFolder = Path.GetFullPath(folder);
        string portableExe = Path.Combine(folder, "terminal64.exe");
        string origin = Path.Combine(folder, "origin.txt");
        if (File.Exists(portableExe))
        {
            t.Exe = Path.GetFullPath(portableExe);
            t.Portable = true;
        }
        else if (File.Exists(origin))
        {
            string install = ReadOrigin(origin);
            string exe = Path.Combine(install, "terminal64.exe");
            if (!File.Exists(exe))
                return null;
            t.Exe = exe;
        }
        else
            return null;
        t.Name = Path.GetFileName(Path.GetDirectoryName(t.Exe));
        return t;
    }

    // origin.txt names the install folder; MT5 writes it as UTF-16LE.
    static string ReadOrigin(string path)
    {
        byte[] b = File.ReadAllBytes(path);
        string s;
        if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE)
            s = Encoding.Unicode.GetString(b, 2, b.Length - 2);
        else if (b.Length >= 2 && b[1] == 0)
            s = Encoding.Unicode.GetString(b);
        else
            s = Encoding.Default.GetString(b);
        return s.Trim().Trim('\0').Trim();
    }

    static string ManifestJson(string exe, List<string> ids)
    {
        StringBuilder origins = new StringBuilder();
        foreach (string id in ids)
        {
            if (origins.Length > 0)
                origins.Append(", ");
            origins.Append(Json.Quote("chrome-extension://" + id.Trim() + "/"));
        }
        return "{\r\n  \"name\": " + Json.Quote(HostName) + ",\r\n  \"description\": \"ActionInna link to MetaTrader 5\",\r\n  \"path\": " +
               Json.Quote(exe) + ",\r\n  \"type\": \"stdio\",\r\n  \"allowed_origins\": [" + origins + "]\r\n}\r\n";
    }

    static bool IsJunction(string dir)
    {
        return Directory.Exists(dir) && (File.GetAttributes(dir) & FileAttributes.ReparsePoint) != 0;
    }

    static bool SamePath(string a, string b)
    {
        return string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
    }

    static void Delete(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch (IOException e)
        {
            Console.WriteLine("Could not delete " + path + ": " + e.Message);
        }
    }

    // A double-clicked installer closes its window at once; wait so the trader can read it.
    static void Pause(string[] args)
    {
        if (Program.HasFlag(args, "--quiet") || Console.IsInputRedirected)
            return;
        Console.Write("Press Enter to close.");
        Console.ReadLine();
    }
}
