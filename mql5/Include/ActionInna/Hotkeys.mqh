//+------------------------------------------------------------------+
//| ActionInna - hotkey parsing and matching                         |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_HOTKEYS_MQH
#define ACTIONINNA_HOTKEYS_MQH

#include "Defines.mqh"

struct AiKey
  {
   int               vk;      // Windows virtual-key code, 0 = disabled
   bool              shift;
   bool              ctrl;
  };

// Reads "B", "1", "ENTER", "ESC", "SPACE", "TAB", "F5", "SHIFT+B", "CTRL+1". An empty text disables
// the key. Alt is not offered: the terminal keeps Alt combinations for itself.
bool AiParseKey(const string spec, AiKey &k)
  {
   k.vk = 0;
   k.shift = false;
   k.ctrl = false;
   string s = spec;
   StringTrimLeft(s);
   StringTrimRight(s);
   StringToUpper(s);
   if(s == "")
      return false;
   string parts[];
   int n = StringSplit(s, '+', parts);
   if(n <= 0)
      return false;
   for(int i = 0; i < n - 1; i++)
     {
      if(parts[i] == "SHIFT")
         k.shift = true;
      else if(parts[i] == "CTRL" || parts[i] == "CONTROL")
         k.ctrl = true;
      else
         return false;
     }
   string key = parts[n - 1];
   int len = StringLen(key);
   if(len == 1)
     {
      ushort c = StringGetCharacter(key, 0);
      if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
         k.vk = (int)c;
     }
   else if(key == "ENTER" || key == "RETURN")
      k.vk = 13;
   else if(key == "ESC" || key == "ESCAPE")
      k.vk = 27;
   else if(key == "SPACE")
      k.vk = 32;
   else if(key == "TAB")
      k.vk = 9;
   else if(len >= 2 && len <= 3 && StringGetCharacter(key, 0) == 'F')
     {
      int f = (int)StringToInteger(StringSubstr(key, 1));
      if(f >= 1 && f <= 12)
         k.vk = 111 + f;
     }
   if(k.vk == 0)
     {
      k.shift = false;
      k.ctrl = false;
      return false;
     }
   return true;
  }

// Number-pad digits count as the digits on the top row.
bool AiKeyMatch(const AiKey &k, const int vk, const bool shift, const bool ctrl)
  {
   if(k.vk == 0)
      return false;
   int v = vk;
   if(v >= 96 && v <= 105)
      v = 48 + (v - 96);
   return (v == k.vk && shift == k.shift && ctrl == k.ctrl);
  }

// TERMINAL_KEYSTATE_* follows GetKeyState: the 0x8000 bit is set while the key is held.
bool AiKeyHeld(const ENUM_TERMINAL_INFO_INTEGER key)
  {
   return (TerminalInfoInteger(key) & 0x8000) != 0;
  }

#endif
