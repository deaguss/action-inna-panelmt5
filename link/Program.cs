// ActionInnaLink: the link between the ActionInna browser panel (a Chrome extension) and the
// ActionInna EA in MT5. How they talk is in docs/protocol.md.
//
//   ActionInnaLink.exe chrome-extension://<id>/   Chrome starts it for the side panel
//   ActionInnaLink.exe --install [--dev] [--no-registry] [--quiet] [--extension-id <id>] [--mt5 <folder>]
//   ActionInnaLink.exe --uninstall [--no-registry] [--quiet]
//
// Written for the C# 5 compiler that comes with .NET Framework 4.x (csc.exe in Windows 10 and 11),
// so building it needs nothing installed. scripts\build-link.ps1 builds it.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;

static class Program
{
    static int Main(string[] args)
    {
        try
        {
            if (HasFlag(args, "--install"))
                return Installer.Install(args);
            if (HasFlag(args, "--uninstall"))
                return Installer.Uninstall(args);
            return new Host().Run(args);
        }
        catch (Exception e)
        {
            Paths.Log("stopped by an error: " + e);
            Console.Error.WriteLine(e.Message);
            return 1;
        }
    }

    internal static bool HasFlag(string[] args, string flag)
    {
        foreach (string a in args)
            if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    // Every value given after 'flag': --mt5 A --mt5 B gives A and B.
    internal static List<string> Values(string[] args, string flag)
    {
        List<string> values = new List<string>();
        for (int i = 0; i + 1 < args.Length; i++)
            if (string.Equals(args[i], flag, StringComparison.OrdinalIgnoreCase))
                values.Add(args[i + 1]);
        return values;
    }
}

// Where the link keeps its files. The tests move each of them with an environment variable.
static class Paths
{
    static string Env(string name, string fallback)
    {
        string v = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrEmpty(v) ? fallback : v;
    }

    static string AppData
    {
        get { return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData); }
    }

    // %LOCALAPPDATA%\ActionInna: the installed exe, its browser manifest, link.json, link.log.
    public static string Home
    {
        get { return Env("ACTIONINNA_HOME", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ActionInna")); }
    }

    // MT5's Common\Files\ActionInna, which every MT5 terminal of this Windows user reads: link.key.
    public static string Common
    {
        get { return Env("ACTIONINNA_COMMON", Path.Combine(AppData, "MetaQuotes", "Terminal", "Common", "Files", "ActionInna")); }
    }

    // MT5's data folders, one per installed terminal: %APPDATA%\MetaQuotes\Terminal\<id>.
    public static string Terminals
    {
        get { return Env("ACTIONINNA_TERMINALS", Path.Combine(AppData, "MetaQuotes", "Terminal")); }
    }

    public static string PipeName
    {
        get { return Env("ACTIONINNA_PIPE", "ActionInna.Link"); }
    }

    public static string KeyFile
    {
        get { return Path.Combine(Common, "link.key"); }
    }

    public static string ConfigFile
    {
        get { return Path.Combine(Home, "link.json"); }
    }

    public static string LogFile
    {
        get { return Path.Combine(Home, "link.log"); }
    }

    static readonly object logLock = new object();

    // link.log, cut to link.log.old at 1 MB. A log that can't be written never stops the link.
    public static void Log(string text)
    {
        lock (logLock)
        {
            try
            {
                Directory.CreateDirectory(Home);
                FileInfo fi = new FileInfo(LogFile);
                if (fi.Exists && fi.Length > 1024 * 1024)
                {
                    string old = LogFile + ".old";
                    if (File.Exists(old))
                        File.Delete(old);
                    File.Move(LogFile, old);
                }
                File.AppendAllText(LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + text + "\r\n",
                                   new UTF8Encoding(false));
            }
            catch (Exception)
            {
            }
        }
    }
}

// The link's key (docs/protocol.md, "The link's key"): 32 hex characters from the system's random
// source, made once, kept where only this Windows user can read it.
static class LinkKey
{
    public static string LoadOrCreate()
    {
        string path = Paths.KeyFile;
        try
        {
            if (File.Exists(path))
            {
                string k = File.ReadAllText(path).Trim();
                if (IsValid(k))
                    return k;
            }
        }
        catch (IOException)
        {
        }
        byte[] bytes = new byte[16];
        using (RNGCryptoServiceProvider rng = new RNGCryptoServiceProvider())
            rng.GetBytes(bytes);
        string key = BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();
        Directory.CreateDirectory(Paths.Common);
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, key + "\r\n", Encoding.ASCII);
        if (File.Exists(path))
            File.Delete(path);
        File.Move(tmp, path);
        Paths.Log("made a new link key: " + path);
        return key;
    }

    static bool IsValid(string k)
    {
        if (k.Length != 32)
            return false;
        foreach (char c in k)
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
                return false;
        return true;
    }
}

// The few JSON strings the link writes itself.
static class Json
{
    public static string Quote(string s)
    {
        if (s == null)
            return "\"\"";
        StringBuilder b = new StringBuilder("\"");
        foreach (char c in s)
        {
            if (c == '"')
                b.Append("\\\"");
            else if (c == '\\')
                b.Append("\\\\");
            else if (c == '\n')
                b.Append("\\n");
            else if (c == '\r')
                b.Append("\\r");
            else if (c == '\t')
                b.Append("\\t");
            else if (c < 0x20)
                b.Append("\\u").Append(((int)c).ToString("x4"));
            else
                b.Append(c);
        }
        return b.Append('"').ToString();
    }

    // One JSON value and nothing else (RFC 8259): no comments, single quotes, bare words, trailing
    // commas or lone surrogates, which the browser refuses.
    public static bool IsValid(string s)
    {
        int i = 0;
        return Value(s, ref i, 0) && Space(s, ref i) == s.Length;
    }

    static int Space(string s, ref int i)
    {
        while (i < s.Length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n'))
            i++;
        return i;
    }

    static bool Value(string s, ref int i, int depth)
    {
        if (depth > 200 || Space(s, ref i) >= s.Length)
            return false;
        char c = s[i];
        if (c == '{' || c == '[')
        {
            char end = (c == '{') ? '}' : ']';
            i++;
            if (Space(s, ref i) < s.Length && s[i] == end)
            {
                i++;
                return true;
            }
            while (true)
            {
                if (c == '{')
                {
                    if (Space(s, ref i) >= s.Length || s[i] != '"' || !StringAt(s, ref i) || Space(s, ref i) >= s.Length || s[i] != ':')
                        return false;
                    i++;
                }
                if (!Value(s, ref i, depth + 1) || Space(s, ref i) >= s.Length)
                    return false;
                if (s[i] == end)
                {
                    i++;
                    return true;
                }
                if (s[i] != ',')
                    return false;
                i++;
            }
        }
        if (c == '"')
            return StringAt(s, ref i);
        foreach (string word in new[] { "true", "false", "null" })
            if (string.CompareOrdinal(s, i, word, 0, word.Length) == 0)
            {
                i += word.Length;
                return true;
            }
        return Number(s, ref i);
    }

    static bool StringAt(string s, ref int i)
    {
        i++;
        while (i < s.Length)
        {
            char c = s[i++];
            if (c == '"')
                return true;
            if (c < 0x20)
                return false;
            if (char.IsHighSurrogate(c))
            {
                if (i >= s.Length || !char.IsLowSurrogate(s[i]))
                    return false;
                i++;
            }
            else if (char.IsLowSurrogate(c))
                return false;
            else if (c == '\\')
            {
                if (i >= s.Length)
                    return false;
                char e = s[i++];
                if (e == 'u')
                {
                    int unit;
                    if (!Hex4(s, i, out unit))
                        return false;
                    i += 4;
                    if (unit >= 0xDC00 && unit <= 0xDFFF)
                        return false;
                    if (unit >= 0xD800 && unit <= 0xDBFF)
                    {
                        int low;
                        if (i + 6 > s.Length || s[i] != '\\' || s[i + 1] != 'u' || !Hex4(s, i + 2, out low) || low < 0xDC00 || low > 0xDFFF)
                            return false;
                        i += 6;
                    }
                }
                else if ("\"\\/bfnrt".IndexOf(e) < 0)
                    return false;
            }
        }
        return false;
    }

    static bool Hex4(string s, int at, out int v)
    {
        v = 0;
        if (at + 4 > s.Length)
            return false;
        for (int k = at; k < at + 4; k++)
        {
            int d = "0123456789abcdef".IndexOf(char.ToLowerInvariant(s[k]));
            if (d < 0)
                return false;
            v = v * 16 + d;
        }
        return true;
    }

    static bool Number(string s, ref int i)
    {
        int start = i;
        if (i < s.Length && s[i] == '-')
            i++;
        if (i < s.Length && s[i] == '0')
            i++;
        else if (Digits(s, ref i) == 0)
            return false;
        if (i < s.Length && s[i] == '.')
        {
            i++;
            if (Digits(s, ref i) == 0)
                return false;
        }
        if (i < s.Length && (s[i] == 'e' || s[i] == 'E'))
        {
            i++;
            if (i < s.Length && (s[i] == '+' || s[i] == '-'))
                i++;
            if (Digits(s, ref i) == 0)
                return false;
        }
        double d;   // 1e400 is JSON, but not a number the browser takes
        return double.TryParse(s.Substring(start, i - start), NumberStyles.Float, CultureInfo.InvariantCulture, out d) && !double.IsInfinity(d);
    }

    static int Digits(string s, ref int i)
    {
        int n = 0;
        while (i < s.Length && s[i] >= '0' && s[i] <= '9')
        {
            i++;
            n++;
        }
        return n;
    }
}
