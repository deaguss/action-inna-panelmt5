//+------------------------------------------------------------------+
//| ActionInna - chart settings the EA changes, and their restore    |
//+------------------------------------------------------------------+
#ifndef ACTIONINNA_CHARTGUARD_MQH
#define ACTIONINNA_CHARTGUARD_MQH

#include "Defines.mqh"

// Remembers the chart's own settings once, changes what the panel needs, and puts everything back
// when the EA is removed. A timeframe or symbol change keeps the EA loaded, so nothing is restored
// then and the remembered values stay the original ones.
class CAiChartGuard
  {
private:
   bool              m_captured;
   bool              m_oneClick;
   bool              m_quickNav;
   bool              m_mouseMove;
   bool              m_mouseScroll;
   bool              m_shift;
   double            m_shiftSize;
   bool              m_scrollLocked;
   bool              m_shifted;

public:
                     CAiChartGuard() : m_captured(false), m_oneClick(false), m_quickNav(true), m_mouseMove(false),
                     m_mouseScroll(true), m_shift(false), m_shiftSize(10.0), m_scrollLocked(false), m_shifted(false) {}

   void              Capture()
     {
      if(m_captured)
         return;
      m_oneClick = (ChartGetInteger(0, CHART_SHOW_ONE_CLICK) != 0);
      m_quickNav = (ChartGetInteger(0, CHART_QUICK_NAVIGATION) != 0);
      m_mouseMove = (ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE) != 0);
      m_mouseScroll = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
      m_shift = (ChartGetInteger(0, CHART_SHIFT) != 0);
      m_shiftSize = ChartGetDouble(0, CHART_SHIFT_SIZE);
      m_captured = true;
     }

   // Hides MT5's One-Click panel and keeps Enter/Space for the hotkeys instead of quick navigation.
   void              Apply(const bool hideOneClick, const bool hotkeys)
     {
      ChartSetInteger(0, CHART_SHOW_ONE_CLICK, hideOneClick ? false : m_oneClick);
      ChartSetInteger(0, CHART_QUICK_NAVIGATION, hotkeys ? false : m_quickNav);
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
     }

   // Empty space right of the last bar for the docked panel, or the trader's own setting back.
   void              Shift(const bool on, const double percent)
     {
      if(on)
        {
         ChartSetInteger(0, CHART_SHIFT, true);
         ChartSetDouble(0, CHART_SHIFT_SIZE, MathMax(10.0, MathMin(50.0, percent)));
         m_shifted = true;
        }
      else if(m_shifted)
        {
         ChartSetInteger(0, CHART_SHIFT, m_shift);
         ChartSetDouble(0, CHART_SHIFT_SIZE, m_shiftSize);
         m_shifted = false;
        }
     }

   // Stops the chart from scrolling while the mouse works the panel.
   void              LockScroll(const bool lock)
     {
      if(lock == m_scrollLocked)
         return;
      m_scrollLocked = lock;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, lock ? false : m_mouseScroll);
     }

   // keepCapture leaves the remembered values in place, for putting the panel back afterwards
   // (used while saving a template).
   void              Restore(const bool keepCapture)
     {
      if(!m_captured)
         return;
      ChartSetInteger(0, CHART_SHOW_ONE_CLICK, m_oneClick);
      ChartSetInteger(0, CHART_QUICK_NAVIGATION, m_quickNav);
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, m_mouseMove);
      ChartSetInteger(0, CHART_MOUSE_SCROLL, m_mouseScroll);
      ChartSetInteger(0, CHART_SHIFT, m_shift);
      ChartSetDouble(0, CHART_SHIFT_SIZE, m_shiftSize);
      m_scrollLocked = false;
      m_shifted = false;
      if(!keepCapture)
         m_captured = false;
     }
  };

#endif
