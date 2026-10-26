//+------------------------------------------------------------------+
//| ActionInna - the link to the browser panel                       |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_LINK_MQH
#define ACTIONINNA_LINK_MQH

#include "Defines.mqh"
#include "Util.mqh"
#include "Bridge.mqh"

// The ActionInna EA on one chart per MT5 terminal serves the browser panel: it opens the named pipe
// that the link program (ActionInnaLink.exe, started by Chrome) serves, and passes the panel's
// requests to CAiBridge. The other charts' EAs wait, and one takes over within seconds when the
// serving chart closes. The pipe needs no MT5 setting: MQL5 opens it like a file.

#define AI_LINK_PIPE      "\\\\.\\pipe\\ActionInna.Link"
#define AI_LINK_KEY_FILE  "ActionInna\\link.key"
#define AI_LINK_GV_HOST   "ActionInna.Link.Host"
#define AI_LINK_GV_BEAT   "ActionInna.Link.Beat"
#define AI_LINK_MAX_FRAME 1048576
#define AI_LINK_FAST_MS   25
#define AI_LINK_SLOW_MS   200

// The link's key, from Common\Files\ActionInna\link.key: the link program writes it there for this
// Windows user and sends it first. Pipe names are shared by every user of the PC, so another user
// could serve a pipe of the same name; without the key the EA serves nothing. "" when missing.
string AiLinkKey()
  {
   if(!FileIsExist(AI_LINK_KEY_FILE, FILE_COMMON))
      return "";
   int h = FileOpen(AI_LINK_KEY_FILE, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
   if(h == INVALID_HANDLE)
      return "";
   string key = FileReadString(h);
   FileClose(h);
   StringTrimLeft(key);
   StringTrimRight(key);
   return (StringLen(key) >= 16) ? key : "";
  }

// Which chart serves the panel, agreed through two temporary terminal variables: the host's token
// and its heartbeat. A chart takes over when there is no host or its heartbeat is 3 s old. The
// variables are temporary, so they go with the terminal.
class CAiLinkHost
  {
private:
   double            m_token;
   bool              m_host;

public:
                     CAiLinkHost() : m_token(0.0), m_host(false) {}

   void              Init(const double token)
     {
      m_token = token;
      m_host = false;
     }

   bool              IsHost() const
     {
      return m_host;
     }

   // Called about once a second, with the time in seconds.
   bool              Update(const double now)
     {
      if(!GlobalVariableCheck(AI_LINK_GV_HOST))
        {
         GlobalVariableTemp(AI_LINK_GV_HOST);
         GlobalVariableSet(AI_LINK_GV_HOST, 0.0);
        }
      if(!GlobalVariableCheck(AI_LINK_GV_BEAT))
        {
         GlobalVariableTemp(AI_LINK_GV_BEAT);
         GlobalVariableSet(AI_LINK_GV_BEAT, 0.0);
        }
      double host = GlobalVariableGet(AI_LINK_GV_HOST);
      if(host == m_token)
        {
         GlobalVariableSet(AI_LINK_GV_BEAT, now);
         m_host = true;
         return true;
        }
      m_host = false;
      bool gone = (host == 0.0) || (now - GlobalVariableGet(AI_LINK_GV_BEAT) > 3.0);
      if(gone && GlobalVariableSetOnCondition(AI_LINK_GV_HOST, m_token, host))
        {
         GlobalVariableSet(AI_LINK_GV_BEAT, now);
         m_host = true;
        }
      return m_host;
     }

   // The chart stops serving (EA removed, chart closed): another takes over at once.
   void              Release()
     {
      if(m_host)
         GlobalVariableSetOnCondition(AI_LINK_GV_HOST, 0.0, m_token);
      m_host = false;
     }
  };

// The pipe to the link program. Frames are a 4-byte length and UTF-8 JSON, as Chrome's native
// messaging frames them. Reads wait for nothing: FileSize tells how many bytes have arrived, as
// MetaQuotes' CFilePipe uses it. A link that went away shows when a write fails.
class CAiLinkPipe
  {
private:
   int               m_h;
   int               m_need;     // length of the frame being read, -1 = its length not read yet
   bool              m_broken;

public:
                     CAiLinkPipe() : m_h(INVALID_HANDLE), m_need(-1), m_broken(false) {}

   bool              IsOpen() const
     {
      return m_h != INVALID_HANDLE;
     }

   bool              Broken() const
     {
      return m_broken;
     }

   // Fails at once when the link isn't running.
   bool              Open()
     {
      Close();
      m_h = FileOpen(AI_LINK_PIPE, FILE_READ | FILE_WRITE | FILE_BIN);
      m_need = -1;
      m_broken = false;
      return m_h != INVALID_HANDLE;
     }

   void              Close()
     {
      if(m_h != INVALID_HANDLE)
         FileClose(m_h);
      m_h = INVALID_HANDLE;
      m_need = -1;
      m_broken = false;
     }

   bool              Send(const string json)
     {
      if(m_h == INVALID_HANDLE || m_broken)
         return false;
      uchar buf[];
      int n = StringToCharArray(json, buf, 0, WHOLE_ARRAY, CP_UTF8) - 1;   // without the closing zero
      if(n <= 0 || n > AI_LINK_MAX_FRAME)
         return false;
      ResetLastError();
      if(FileWriteInteger(m_h, n) != 4 || FileWriteArray(m_h, buf, 0, n) != (uint)n)
        {
         m_broken = true;
         return false;
        }
      FileFlush(m_h);
      return true;
     }

   // The frames that have arrived whole.
   int               Receive(string &lines[])
     {
      ArrayResize(lines, 0);
      int count = 0;
      for(int guard = 0; guard < 256 && m_h != INVALID_HANDLE && !m_broken; guard++)
        {
         ulong avail = FileSize(m_h);
         if(m_need < 0)
           {
            if(avail < 4)
               break;
            ResetLastError();
            int len = FileReadInteger(m_h);
            if(GetLastError() != 0 || len < 0 || len > AI_LINK_MAX_FRAME)
              {
               m_broken = true;
               break;
              }
            m_need = len;
            continue;
           }
         if(avail < (ulong)m_need)
            break;
         string line = "";
         if(m_need > 0)
           {
            uchar buf[];
            ResetLastError();
            int got = (int)FileReadArray(m_h, buf, 0, m_need);
            if(got != m_need)
              {
               m_broken = true;
               break;
              }
            line = CharArrayToString(buf, 0, got, CP_UTF8);
           }
         m_need = -1;
         ArrayResize(lines, count + 1, 8);
         lines[count] = line;
         count++;
        }
      return count;
     }
  };

// Glue for the EA: elects the host, runs the pipe on the host chart, feeds the bridge. The EA calls
// Timer() on every timer event; while this chart serves the panel, the timer runs every 25 ms.
class CAiLink
  {
private:
   bool              m_enabled;
   CAiLinkHost       m_host;
   CAiLinkPipe       m_pipe;
   CAiBridge         m_bridge;
   ulong             m_lastHostMs;
   ulong             m_lastOpenMs;
   ulong             m_lastSendMs;
   bool              m_fast;
   bool              m_authed;     // the link sent the right key: requests are served

   // The link's first frame must be {"t":"link","key":...} with the key from link.key.
   bool              KeyMatches(const string line) const
     {
      string key = AiLinkKey();
      CAiJsonIn in;
      return key != "" && in.Parse(line) && in.Str("t") == "link" && in.Str("key") == key;
     }

   void              SetPace(const bool fast)
     {
      if(fast == m_fast)
         return;
      m_fast = fast;
      EventSetMillisecondTimer(fast ? AI_LINK_FAST_MS : AI_LINK_SLOW_MS);
     }

   void              Drop(const string why)
     {
      if(m_pipe.IsOpen() && (m_authed || StringFind(why, "refused") == 0))
         AiLog("Browser panel " + why);
      m_pipe.Close();
      m_authed = false;
     }

public:
                     CAiLink() : m_enabled(false), m_lastHostMs(0), m_lastOpenMs(0), m_lastSendMs(0), m_fast(false), m_authed(false) {}

   void              Init(const AiSettings &cfg, const bool enabled)
     {
      m_enabled = enabled && MQLInfoInteger(MQL_TESTER) == 0;
      m_bridge.Init(cfg);
      // A token per chart: chart ids are unique in a terminal; a double holds this part exactly.
      m_host.Init(1.0 + (double)(ChartID() % 2000000000));
      m_lastHostMs = 0;
      m_lastOpenMs = 0;
      m_fast = false;
     }

   void              Deinit()
     {
      Drop("disconnected (EA stopped)");
      m_host.Release();
     }

   void              OnTrade()
     {
      if(m_pipe.IsOpen())
         m_bridge.OnTrade();
     }

   void              Timer()
     {
      if(!m_enabled)
         return;
      ulong now = AiNowMs();
      if(now - m_lastHostMs >= 1000 || m_lastHostMs == 0)
        {
         m_lastHostMs = now;
         // The heartbeat needs a clock every chart shares: GetMicrosecondCount counts from each
         // program's own start.
         bool host = m_host.Update((double)GetTickCount64() / 1000.0);
         SetPace(host);
         if(!host)
            Drop("handed to another chart");
        }
      if(!m_host.IsHost())
         return;
      if(!m_pipe.IsOpen())
        {
         if(now - m_lastOpenMs < 2000 && m_lastOpenMs != 0)
            return;
         m_lastOpenMs = now;
         if(!m_pipe.Open())
            return;
         m_authed = false;
        }
      string lines[];
      int n = m_pipe.Receive(lines);
      for(int i = 0; i < n; i++)
        {
         if(m_authed)
           {
            m_bridge.Handle(lines[i]);
            continue;
           }
         if(!KeyMatches(lines[i]))
           {
            Drop("refused: the link's key does not match link.key");
            m_lastOpenMs = now;
            return;
           }
         m_authed = true;
         AiLog("Browser panel connected");
         m_bridge.Start();
        }
      if(!m_authed)
        {
         if(now - m_lastOpenMs > 3000)
           {
            Drop("refused: the link sent no key");
            m_lastOpenMs = now;
           }
         return;
        }
      m_bridge.Poll();
      string out[];
      int k = m_bridge.TakeOut(out);
      for(int j = 0; j < k && !m_pipe.Broken(); j++)
         m_pipe.Send(out[j]);
      // A write is how a closed link shows, and it tells the panel this EA is alive.
      if(k > 0)
         m_lastSendMs = now;
      else if(now - m_lastSendMs >= 1000)
        {
         m_lastSendMs = now;
         m_pipe.Send("{\"t\":\"beat\"}");
        }
      if(m_pipe.Broken())
        {
         Drop("disconnected (side panel closed)");
         m_lastOpenMs = now;   // the next try in 2 s
        }
     }
  };

#endif
