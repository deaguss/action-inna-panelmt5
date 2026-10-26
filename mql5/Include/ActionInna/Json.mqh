//+------------------------------------------------------------------+
//| ActionInna - JSON for the browser panel's messages               |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_JSON_MQH
#define ACTIONINNA_JSON_MQH

#include "Util.mqh"

#define AI_JSON_STR    0
#define AI_JSON_NUM    1
#define AI_JSON_BOOL   2
#define AI_JSON_NULL   3
#define AI_JSON_NESTED 4   // an object or array: skipped, the panel's requests have none

// "text" in JSON quotes: quotes, backslashes and control characters escaped.
string AiJsonQuote(const string s)
  {
   string out = "\"";
   int n = StringLen(s);
   int run = 0;
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      string esc = "";
      if(c == '"')
         esc = "\\\"";
      else if(c == '\\')
         esc = "\\\\";
      else if(c == '\n')
         esc = "\\n";
      else if(c == '\r')
         esc = "\\r";
      else if(c == '\t')
         esc = "\\t";
      else if(c < 0x20)
         esc = "\\u00" + ((c < 16) ? "0" : "1") + StringSubstr("0123456789abcdef", c % 16, 1);
      if(esc == "")
         continue;
      if(i > run)
         out += StringSubstr(s, run, i - run);
      out += esc;
      run = i + 1;
     }
   if(n > run)
      out += StringSubstr(s, run, n - run);
   return out + "\"";
  }

// A number for JSON. digits < 0 writes up to 8 decimals without trailing zeros.
string AiJsonNum(const double v, const int digits = -1)
  {
   if(!MathIsValidNumber(v))
      return "0";
   if(digits >= 0)
      return DoubleToString(v, digits);
   return AiTrimZeros(DoubleToString(v, 8));
  }

// Builds one JSON object. Open/Close nest objects and arrays; an empty key adds an array item.
class CAiJsonOut
  {
private:
   string            m_s;
   bool              m_comma;   // the next member needs a comma first

   void              Key(const string k)
     {
      if(m_comma)
         m_s += ",";
      m_comma = true;
      if(k != "")
         m_s += AiJsonQuote(k) + ":";
     }

public:
                     CAiJsonOut() : m_s("{"), m_comma(false) {}

   void              Str(const string k, const string v)
     {
      Key(k);
      m_s += AiJsonQuote(v);
     }

   void              Num(const string k, const double v, const int digits = -1)
     {
      Key(k);
      m_s += AiJsonNum(v, digits);
     }

   void              Int(const string k, const long v)
     {
      Key(k);
      m_s += IntegerToString(v);
     }

   void              Bool(const string k, const bool v)
     {
      Key(k);
      m_s += v ? "true" : "false";
     }

   void              Open(const string k, const bool array)
     {
      Key(k);
      m_s += array ? "[" : "{";
      m_comma = false;
     }

   void              Close(const bool array)
     {
      m_s += array ? "]" : "}";
      m_comma = true;
     }

   string            Text() const
     {
      return m_s + "}";
     }
  };

// Reads one flat JSON object: strings, numbers, true, false and null. Nested objects and arrays are
// skipped whole. Anything that isn't valid JSON is refused, with the reason in Error().
class CAiJsonIn
  {
private:
   string            m_keys[];
   string            m_vals[];   // strings decoded; numbers and literals as written
   int               m_kinds[];
   string            m_err;
   string            m_t;
   int               m_p;
   int               m_n;

   ushort            Ch() const
     {
      return (m_p < m_n) ? StringGetCharacter(m_t, m_p) : 0;
     }

   void              Space()
     {
      while(m_p < m_n)
        {
         ushort c = StringGetCharacter(m_t, m_p);
         if(c != ' ' && c != '\t' && c != '\r' && c != '\n')
            return;
         m_p++;
        }
     }

   bool              Fail(const string why)
     {
      if(m_err == "")
         m_err = why + " at character " + IntegerToString(m_p + 1);
      return false;
     }

   int               Hex(const ushort c) const
     {
      if(c >= '0' && c <= '9')
         return c - '0';
      if(c >= 'a' && c <= 'f')
         return c - 'a' + 10;
      if(c >= 'A' && c <= 'F')
         return c - 'A' + 10;
      return -1;
     }

   bool              ReadString(string &out)
     {
      out = "";
      if(Ch() != '"')
         return Fail("Expected a string");
      m_p++;
      int run = m_p;
      while(m_p < m_n)
        {
         ushort c = StringGetCharacter(m_t, m_p);
         if(c == '"')
           {
            if(m_p > run)
               out += StringSubstr(m_t, run, m_p - run);
            m_p++;
            return true;
           }
         if(c < 0x20)
            return Fail("Control character in a string");
         if(c != '\\')
           {
            m_p++;
            continue;
           }
         if(m_p > run)
            out += StringSubstr(m_t, run, m_p - run);
         m_p++;
         ushort e = Ch();
         m_p++;
         if(e == '"' || e == '\\' || e == '/')
            out += ShortToString(e);
         else if(e == 'b')
            out += ShortToString(8);
         else if(e == 'f')
            out += ShortToString(12);
         else if(e == 'n')
            out += "\n";
         else if(e == 'r')
            out += "\r";
         else if(e == 't')
            out += "\t";
         else if(e == 'u')
           {
            int code = 0;
            for(int k = 0; k < 4; k++)
              {
               int h = Hex(Ch());
               if(h < 0)
                  return Fail("Bad \\u escape");
               code = code * 16 + h;
               m_p++;
              }
            out += ShortToString((ushort)code);
           }
         else
            return Fail("Bad escape");
         run = m_p;
        }
      return Fail("Unterminated string");
     }

   bool              Digits()
     {
      int start = m_p;
      while(Ch() >= '0' && Ch() <= '9')
         m_p++;
      return m_p > start;
     }

   bool              ReadNumber(string &out)
     {
      int start = m_p;
      if(Ch() == '-')
         m_p++;
      if(Ch() == '0')
         m_p++;
      else if(!Digits())
         return Fail("Bad number");
      if(Ch() == '.')
        {
         m_p++;
         if(!Digits())
            return Fail("Bad number");
        }
      if(Ch() == 'e' || Ch() == 'E')
        {
         m_p++;
         if(Ch() == '+' || Ch() == '-')
            m_p++;
         if(!Digits())
            return Fail("Bad number");
        }
      out = StringSubstr(m_t, start, m_p - start);
      return true;
     }

   bool              Literal(const string word)
     {
      int len = StringLen(word);
      if(StringSubstr(m_t, m_p, len) != word)
         return Fail("Unexpected character");
      m_p += len;
      return true;
     }

   // Reads past an object or array, checking everything in it as strictly as the rest; nothing in
   // it is kept.
   bool              SkipNested(const int depth)
     {
      if(depth > 32)
         return Fail("Nested too deeply");
      bool obj = (Ch() == '{');
      ushort end = obj ? '}' : ']';
      m_p++;
      Space();
      if(Ch() == end)
        {
         m_p++;
         return true;
        }
      while(m_p < m_n)
        {
         if(obj)
           {
            string ignored;
            if(!ReadString(ignored))
               return false;
            Space();
            if(Ch() != ':')
               return Fail("Expected ':'");
            m_p++;
            Space();
           }
         if(Ch() == '{' || Ch() == '[')
           {
            if(!SkipNested(depth + 1))
               return false;
           }
         else
           {
            string v;
            int kind = AI_JSON_NULL;
            if(!ReadValue(v, kind))
               return false;
           }
         Space();
         if(Ch() == ',')
           {
            m_p++;
            Space();
            continue;
           }
         if(Ch() == end)
           {
            m_p++;
            return true;
           }
         return Fail(obj ? "Expected ',' or '}'" : "Expected ',' or ']'");
        }
      return Fail("Unterminated object or array");
     }

   bool              ReadValue(string &val, int &kind)
     {
      val = "";
      ushort c = Ch();
      if(c == '"')
        {
         kind = AI_JSON_STR;
         return ReadString(val);
        }
      if(c == '-' || (c >= '0' && c <= '9'))
        {
         kind = AI_JSON_NUM;
         return ReadNumber(val);
        }
      if(c == 't' || c == 'f')
        {
         kind = AI_JSON_BOOL;
         val = (c == 't') ? "true" : "false";
         return Literal(val);
        }
      if(c == 'n')
        {
         kind = AI_JSON_NULL;
         return Literal("null");
        }
      if(c == '{' || c == '[')
        {
         kind = AI_JSON_NESTED;
         return SkipNested(1);
        }
      return Fail("Expected a value");
     }

   int               Find(const string k) const
     {
      int n = ArraySize(m_keys);
      for(int i = 0; i < n; i++)
         if(m_keys[i] == k)
            return i;
      return -1;
     }

   void              Put(const string k, const string v, const int kind)
     {
      int i = Find(k);
      if(i < 0)
        {
         i = ArraySize(m_keys);
         ArrayResize(m_keys, i + 1);
         ArrayResize(m_vals, i + 1);
         ArrayResize(m_kinds, i + 1);
         m_keys[i] = k;
        }
      m_vals[i] = v;
      m_kinds[i] = kind;
     }

public:
   bool              Parse(const string text)
     {
      ArrayResize(m_keys, 0);
      ArrayResize(m_vals, 0);
      ArrayResize(m_kinds, 0);
      m_err = "";
      m_t = text;
      m_p = 0;
      m_n = StringLen(text);
      Space();
      if(Ch() != '{')
         return Fail("Not a JSON object");
      m_p++;
      Space();
      if(Ch() == '}')
         m_p++;
      else
         while(true)
           {
            string k;
            string v;
            int kind = AI_JSON_NULL;
            if(!ReadString(k))
               return false;
            Space();
            if(Ch() != ':')
               return Fail("Expected ':'");
            m_p++;
            Space();
            if(!ReadValue(v, kind))
               return false;
            if(kind != AI_JSON_NESTED)
               Put(k, v, kind);
            Space();
            if(Ch() == ',')
              {
               m_p++;
               Space();
               continue;
              }
            if(Ch() == '}')
              {
               m_p++;
               break;
              }
            return Fail("Expected ',' or '}'");
           }
      Space();
      if(m_p < m_n)
         return Fail("Text after the object");
      return true;
     }

   string            Error() const
     {
      return m_err;
     }

   bool              Has(const string k) const
     {
      return Find(k) >= 0;
     }

   // A string value; a number or literal comes back as written.
   string            Str(const string k, const string def = "") const
     {
      int i = Find(k);
      return (i < 0 || m_kinds[i] == AI_JSON_NULL) ? def : m_vals[i];
     }

   double            Num(const string k, const double def = 0.0) const
     {
      int i = Find(k);
      if(i < 0 || m_kinds[i] != AI_JSON_NUM)
         return def;
      double v = StringToDouble(m_vals[i]);
      return MathIsValidNumber(v) ? v : def;
     }

   // A whole number: from a JSON number without a fraction, or a string of digits (tickets above
   // 2^53 travel as strings).
   long              Int(const string k, const long def = 0) const
     {
      int i = Find(k);
      if(i < 0 || (m_kinds[i] != AI_JSON_NUM && m_kinds[i] != AI_JSON_STR))
         return def;
      string v = m_vals[i];
      int n = StringLen(v);
      if(n == 0 || n > 19)
         return def;
      for(int j = 0; j < n; j++)
        {
         ushort c = StringGetCharacter(v, j);
         if(!((c >= '0' && c <= '9') || (c == '-' && j == 0 && n > 1)))
            return def;
        }
      return StringToInteger(v);
     }

   bool              Bool(const string k, const bool def = false) const
     {
      int i = Find(k);
      if(i < 0 || m_kinds[i] != AI_JSON_BOOL)
         return def;
      return m_vals[i] == "true";
     }
  };

#endif
