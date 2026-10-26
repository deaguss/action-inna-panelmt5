// The toolbar button opens the side panel. Everything else happens in the panel.
chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch((e) => console.error(e));
