// Host mode: Chrome started the link for the side panel. The link serves the named pipe the
// ActionInna EAs connect to (one per MT5 terminal), passes messages between them and the panel, and
// starts MT5 when none is connected. docs/protocol.md has the messages.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// One MT5 terminal whose ActionInna EA is connected through the pipe.
sealed class Term
{
    public string Id;
    public NamedPipeServerStream Pipe;
    public readonly object WriteLock = new object();
    public string Account = "";   // "login@server", from the EA's first terminal message
}

sealed class Host
{
    const int MaxFrame = 1024 * 1024;   // Chrome refuses larger messages from a host, and the EA larger requests

    readonly object browserLock = new object();
    readonly object termsLock = new object();
    readonly List<Term> terms = new List<Term>();
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly ManualResetEvent pipeReady = new ManualResetEvent(false);
    Stream browserOut;
    string key;
    int termSeq;
    volatile bool introduced;   // an EA has sent its terminal message
    volatile bool stopping;

    public bool Introduced
    {
        get { return introduced; }
    }

    public bool Stopping
    {
        get { return stopping; }
    }

    public int Run(string[] args)
    {
        Paths.Log("start " + string.Join(" ", args));
        browserOut = Console.OpenStandardOutput();
        bool first;
        using (Mutex single = new Mutex(true, "Local\\" + Paths.PipeName, out first))
        {
            if (!first)
            {
                Status("busy", null, "The panel is already open in another browser window. Close it there first");
                Thread.Sleep(300);
                return 2;
            }
            key = LinkKey.LoadOrCreate();
            Thread accept = new Thread(AcceptLoop);
            accept.IsBackground = true;
            accept.Start();
            Thread mt5 = new Thread(() => Mt5Starter.WhenNeeded(this));
            mt5.IsBackground = true;
            mt5.Start();
            pipeReady.WaitOne(2000);   // "listening" once an EA could connect
            Status("listening", null, "");
            FromBrowserLoop();
            stopping = true;
            Paths.Log("the browser closed the link");
            lock (termsLock)
                foreach (Term t in terms)
                    CloseTerm(t);
            single.ReleaseMutex();
        }
        return 0;
    }

    //--- the browser side ----------------------------------------------------------
    void FromBrowserLoop()
    {
        Stream input = Console.OpenStandardInput();
        byte[] head = new byte[4];
        while (ReadExactly(input, head, 4))
        {
            int length = BitConverter.ToInt32(head, 0);
            if (length < 0 || length > MaxFrame)
            {
                Paths.Log("the browser sent a frame of " + length + " bytes");
                return;
            }
            byte[] body = new byte[length];
            if (!ReadExactly(input, body, length))
                return;
            FromBrowser(body);
        }
    }

    void FromBrowser(byte[] body)
    {
        Dictionary<string, object> msg = null;
        try
        {
            msg = json.DeserializeObject(Encoding.UTF8.GetString(body)) as Dictionary<string, object>;
        }
        catch (Exception)
        {
        }
        if (msg == null)
        {
            ToBrowser("{\"t\":\"error\",\"err\":\"Not a JSON object\"}");
            return;
        }
        string type = Text(msg, "t");
        if (type == "link.status")
        {
            SendStatus();
            return;
        }
        if (type == "link.start")
        {
            Mt5Starter.Start(this, true);
            return;
        }
        Term target = FindTerm(Text(msg, "term"));
        if (target == null)
        {
            // A request waits for its reply: answer it here.
            object id;
            if (msg.TryGetValue("id", out id) && id != null)
            {
                long n;
                if (long.TryParse(Convert.ToString(id, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out n))
                    ToBrowser("{\"t\":\"reply\",\"id\":" + n.ToString(CultureInfo.InvariantCulture) + ",\"ok\":false,\"err\":\"MT5 is not connected\"}");
            }
            return;
        }
        ToTerm(target, body);
    }

    static string Text(Dictionary<string, object> msg, string k)
    {
        object v;
        if (!msg.TryGetValue(k, out v) || v == null)
            return "";
        return Convert.ToString(v, CultureInfo.InvariantCulture);
    }

    // The terminal a request names; with none named, the only one connected.
    Term FindTerm(string id)
    {
        lock (termsLock)
        {
            if (id == "")
                return (terms.Count == 1) ? terms[0] : null;
            foreach (Term t in terms)
                if (t.Id == id)
                    return t;
        }
        return null;
    }

    public void Status(string state, string term, string text)
    {
        ToBrowser("{\"t\":\"link\",\"state\":" + Json.Quote(state) + (term != null ? ",\"term\":" + Json.Quote(term) : "") +
                  ",\"text\":" + Json.Quote(text) + "}");
    }

    void SendStatus()
    {
        Status("listening", null, "");
        lock (termsLock)
            foreach (Term t in terms)
                if (t.Account != "")
                    Status("terminal-connected", t.Id, t.Account);
    }

    void ToBrowser(string jsonText)
    {
        ToBrowser(Encoding.UTF8.GetBytes(jsonText));
    }

    void ToBrowser(byte[] body)
    {
        byte[] frame = Frame(body);
        lock (browserLock)
        {
            try
            {
                browserOut.Write(frame, 0, frame.Length);
                browserOut.Flush();
            }
            catch (IOException e)
            {
                Paths.Log("the browser is gone: " + e.Message);
                Environment.Exit(0);
            }
        }
    }

    //--- the MT5 side -------------------------------------------------------------
    // Only this Windows user may open the pipe, and only on this PC: a pipe is reachable from other
    // PCs over file sharing, where the same account signs in with the NETWORK group, which is denied.
    // Overlapped, so a read waiting for an EA never holds up a write to it.
    NamedPipeServerStream NewPipe()
    {
        PipeSecurity security = new PipeSecurity();
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
        security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
        NamedPipeServerStream pipe = new NamedPipeServerStream(Paths.PipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                                                               PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 65536, 65536, security);
        // A pipe keeps the security of its first instance, whoever made it. If another Windows user
        // made it first and let everyone in, they could connect to this instance and be sent the key.
        SecurityIdentifier owner = null;
        try
        {
            owner = pipe.GetAccessControl().GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
        }
        catch (Exception)
        {
        }
        if (owner == null || !owner.Equals(WindowsIdentity.GetCurrent().Owner))
        {
            pipe.Dispose();
            throw new IOException("another Windows user made the pipe first");
        }
        return pipe;
    }

    void AcceptLoop()
    {
        int failures = 0;
        while (!stopping)
        {
            NamedPipeServerStream pipe;
            try
            {
                pipe = NewPipe();
                failures = 0;
                pipeReady.Set();
                pipe.WaitForConnection();
            }
            catch (Exception e)
            {
                Paths.Log("pipe failed: " + e.Message);
                if (++failures == 3)
                    Status("pipe-failed", null, "Could not open the pipe " + Paths.PipeName + ": " + e.Message);
                Thread.Sleep(1000);
                continue;
            }
            Term t = new Term();
            t.Pipe = pipe;
            lock (termsLock)
            {
                termSeq++;
                t.Id = termSeq.ToString(CultureInfo.InvariantCulture);
                terms.Add(t);
            }
            Paths.Log("terminal " + t.Id + " connected");
            // The key comes first: without it the EA serves nothing.
            ToTerm(t, Encoding.ASCII.GetBytes("{\"t\":\"link\",\"key\":\"" + key + "\"}"));
            Thread reader = new Thread(() => FromTermLoop(t));
            reader.IsBackground = true;
            reader.Start();
        }
    }

    void FromTermLoop(Term t)
    {
        byte[] head = new byte[4];
        try
        {
            while (ReadExactly(t.Pipe, head, 4))
            {
                int length = BitConverter.ToInt32(head, 0);
                if (length < 0 || length > MaxFrame)
                {
                    Paths.Log("terminal " + t.Id + " sent a frame of " + length + " bytes");
                    break;
                }
                byte[] body = new byte[length];
                if (!ReadExactly(t.Pipe, body, length))
                    break;
                if (length == 0)
                    continue;
                // Chrome ends the whole connection on a message that isn't JSON or is over 1 MiB, so
                // one bad frame from an EA is dropped rather than passed on.
                byte[] tagged = IsJsonObject(body) ? Tag(body, t.Id) : null;
                if (tagged == null || tagged.Length > MaxFrame)
                {
                    Paths.Log("terminal " + t.Id + " sent a frame that is not a JSON object of at most 1 MiB; dropped");
                    continue;
                }
                if (StartsWith(body, "{\"t\":\"terminal\""))
                    Introduce(t, body);
                ToBrowser(tagged);
            }
        }
        catch (Exception e)
        {
            Paths.Log("terminal " + t.Id + ": " + e.Message);
        }
        Gone(t);
    }

    // The EA's terminal message names its account. A newer connection for the same account (another
    // chart took over) replaces the older one.
    void Introduce(Term t, byte[] body)
    {
        string account = "";
        try
        {
            Dictionary<string, object> msg = json.DeserializeObject(Encoding.UTF8.GetString(body)) as Dictionary<string, object>;
            if (msg != null)
                account = Text(msg, "login") + "@" + Text(msg, "server");
        }
        catch (Exception)
        {
        }
        bool firstTime = (t.Account == "");
        List<Term> older = new List<Term>();
        lock (termsLock)
        {
            t.Account = account;
            if (firstTime)
                foreach (Term o in terms)
                    if (o != t && o.Account == account)
                        older.Add(o);
        }
        foreach (Term o in older)
        {
            Paths.Log("terminal " + o.Id + " replaced by " + t.Id + " (" + account + ")");
            CloseTerm(o);
        }
        introduced = true;
        if (firstTime)
            Status("terminal-connected", t.Id, account);
    }

    void Gone(Term t)
    {
        bool was;
        lock (termsLock)
            was = terms.Remove(t);
        CloseTerm(t);
        if (was && !stopping)
        {
            Paths.Log("terminal " + t.Id + " gone");
            Status("terminal-gone", t.Id, t.Account);
        }
    }

    void ToTerm(Term t, byte[] body)
    {
        byte[] frame = Frame(body);
        lock (t.WriteLock)
        {
            try
            {
                t.Pipe.Write(frame, 0, frame.Length);
                t.Pipe.Flush();
            }
            catch (Exception e)
            {
                Paths.Log("write to terminal " + t.Id + " failed: " + e.Message);
                CloseTerm(t);
            }
        }
    }

    static void CloseTerm(Term t)
    {
        try
        {
            t.Pipe.Dispose();
        }
        catch (Exception)
        {
        }
    }

    //--- frames -------------------------------------------------------------------
    // A frame: the length in native byte order, as Chrome expects it and as MQL5 writes it, then the JSON.
    static byte[] Frame(byte[] body)
    {
        byte[] frame = new byte[body.Length + 4];
        Buffer.BlockCopy(BitConverter.GetBytes(body.Length), 0, frame, 0, 4);
        Buffer.BlockCopy(body, 0, frame, 4, body.Length);
        return frame;
    }

    static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);

    // Valid UTF-8 holding one JSON object, as strict as Chrome reads it.
    static bool IsJsonObject(byte[] body)
    {
        string text;
        try
        {
            text = StrictUtf8.GetString(body);
        }
        catch (ArgumentException)
        {
            return false;
        }
        return body[0] == (byte)'{' && Json.IsValid(text);
    }

    // Adds "term" to a message from an EA (a JSON object starting with '{'), so the panel knows which
    // MT5 sent it.
    static byte[] Tag(byte[] body, string id)
    {
        int next = 1;
        while (next < body.Length && (body[next] == (byte)' ' || body[next] == (byte)'\t' || body[next] == (byte)'\r' || body[next] == (byte)'\n'))
            next++;
        bool empty = (next < body.Length && body[next] == (byte)'}');
        byte[] tag = Encoding.ASCII.GetBytes("\"term\":\"" + id + "\"" + (empty ? "" : ","));
        byte[] r = new byte[body.Length + tag.Length];
        r[0] = body[0];
        Buffer.BlockCopy(tag, 0, r, 1, tag.Length);
        Buffer.BlockCopy(body, 1, r, 1 + tag.Length, body.Length - 1);
        return r;
    }

    static bool StartsWith(byte[] body, string prefix)
    {
        if (body.Length < prefix.Length)
            return false;
        for (int i = 0; i < prefix.Length; i++)
            if (body[i] != (byte)prefix[i])
                return false;
        return true;
    }

    static bool ReadExactly(Stream s, byte[] buf, int count)
    {
        int done = 0;
        while (done < count)
        {
            int n = s.Read(buf, done, count - done);
            if (n <= 0)
                return false;
            done += n;
        }
        return true;
    }
}

// The MT5 terminals the installer recorded in link.json, and whether to start them.
sealed class LinkConfig
{
    public bool StartMt5 = true;
    public readonly List<Mt5Terminal> Terminals = new List<Mt5Terminal>();

    public static LinkConfig Load()
    {
        LinkConfig c = new LinkConfig();
        try
        {
            if (!File.Exists(Paths.ConfigFile))
                return c;
            Dictionary<string, object> root = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(Paths.ConfigFile)) as Dictionary<string, object>;
            if (root == null)
                return c;
            object v;
            if (root.TryGetValue("startMt5", out v) && v is bool)
                c.StartMt5 = (bool)v;
            if (root.TryGetValue("terminals", out v) && v is IEnumerable)
                foreach (object item in (IEnumerable)v)
                {
                    Dictionary<string, object> d = item as Dictionary<string, object>;
                    if (d == null)
                        continue;
                    Mt5Terminal t = new Mt5Terminal();
                    object x;
                    if (d.TryGetValue("name", out x))
                        t.Name = Convert.ToString(x, CultureInfo.InvariantCulture);
                    if (d.TryGetValue("exe", out x))
                        t.Exe = Convert.ToString(x, CultureInfo.InvariantCulture);
                    if (d.TryGetValue("dataFolder", out x))
                        t.DataFolder = Convert.ToString(x, CultureInfo.InvariantCulture);
                    if (d.TryGetValue("portable", out x) && x is bool)
                        t.Portable = (bool)x;
                    if (!string.IsNullOrEmpty(t.Exe))
                        c.Terminals.Add(t);
                }
        }
        catch (Exception e)
        {
            Paths.Log("link.json could not be read: " + e.Message);
        }
        return c;
    }

    public void Save()
    {
        List<object> list = new List<object>();
        foreach (Mt5Terminal t in Terminals)
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            d["name"] = t.Name;
            d["exe"] = t.Exe;
            d["dataFolder"] = t.DataFolder;
            d["portable"] = t.Portable;
            list.Add(d);
        }
        Dictionary<string, object> root = new Dictionary<string, object>();
        root["startMt5"] = StartMt5;
        root["terminals"] = list;
        Directory.CreateDirectory(Paths.Home);
        File.WriteAllText(Paths.ConfigFile, new JavaScriptSerializer().Serialize(root), new UTF8Encoding(false));
    }
}

sealed class Mt5Terminal
{
    public string Name = "";
    public string Exe = "";          // terminal64.exe
    public string DataFolder = "";   // where its MQL5 folder is
    public bool Portable;            // started with /portable: its data folder is its install folder
}

// Starts the recorded MT5 terminals, minimised, when the panel opens and none is connected. MT5
// reopens its charts, and with them the ActionInna EA that serves the panel.
static class Mt5Starter
{
    public static void WhenNeeded(Host host)
    {
        Thread.Sleep(3000);
        if (host.Introduced || host.Stopping)
            return;
        Start(host, false);
    }

    // force: the panel asked for it (its "Start MT5" button), even when link.json says not to.
    public static void Start(Host host, bool force)
    {
        LinkConfig c = LinkConfig.Load();
        if (c.Terminals.Count == 0)
        {
            host.Status("no-mt5", null, "No MT5 is set up for the panel: run ActionInnaLink.exe --install");
            return;
        }
        if (!c.StartMt5 && !force)
            return;
        int started = 0;
        int running = 0;
        foreach (Mt5Terminal t in c.Terminals)
        {
            if (!File.Exists(t.Exe))
            {
                host.Status("mt5-missing", null, "MT5 is no longer at " + t.Exe + ": run ActionInnaLink.exe --install again");
                continue;
            }
            if (IsRunning(t.Exe))
            {
                running++;
                continue;
            }
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(t.Exe);
                psi.Arguments = t.Portable ? "/portable" : "";
                psi.WorkingDirectory = Path.GetDirectoryName(t.Exe);
                psi.UseShellExecute = true;
                psi.WindowStyle = ProcessWindowStyle.Minimized;
                Process.Start(psi);
                started++;
                Paths.Log("started " + t.Exe);
            }
            catch (Exception e)
            {
                Paths.Log("could not start " + t.Exe + ": " + e.Message);
                host.Status("mt5-failed", null, "Could not start MT5: " + e.Message);
            }
        }
        if (started > 0)
        {
            host.Status("starting-mt5", null, (started == 1) ? "Starting MT5" : "Starting " + started + " MT5 terminals");
            Thread watch = new Thread(() => NoEaAfter(host, 90000));
            watch.IsBackground = true;
            watch.Start();
        }
        else if (running > 0)
            host.Status("no-ea", null, "MT5 is running, but no chart serves the panel: put ActionInna on a chart, with Algo Trading on");
    }

    static void NoEaAfter(Host host, int ms)
    {
        Thread.Sleep(ms);
        if (!host.Introduced && !host.Stopping)
            host.Status("no-ea", null, "MT5 started, but no chart serves the panel: log in, and put ActionInna on a chart with Algo Trading on");
    }

    // A terminal64.exe already runs from that path. When MT5 runs as another user or elevated, its
    // path can't be read: it counts as running, so no second one is started.
    static bool IsRunning(string exe)
    {
        string want = Path.GetFullPath(exe);
        foreach (Process p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe)))
        {
            try
            {
                if (string.Equals(p.MainModule.FileName, want, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch (Exception)
            {
                return true;
            }
        }
        return false;
    }
}
