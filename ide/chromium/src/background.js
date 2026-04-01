// Background service worker for Chrome extension
chrome.runtime.onInstalled.addListener(() => {
  console.log('Ziex DevTools installed');
});

// Track devtools panel connections per tab so we can forward navigation events.
const devtoolsPorts = new Map();

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== 'zx-devtools') return;

  const listener = (msg) => {
    if (msg.type === 'zx-devtools-init' && typeof msg.tabId === 'number') {
      devtoolsPorts.set(msg.tabId, port);
      port.onDisconnect.addListener(() => devtoolsPorts.delete(msg.tabId));
    }
  };
  port.onMessage.addListener(listener);
});

// Relay navigation messages from content scripts to the matching devtools panel.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'zx-navigation' && sender.tab?.id != null) {
    const port = devtoolsPorts.get(sender.tab.id);
    if (port) {
      port.postMessage(message);
    }
  }
  sendResponse({ success: true });
  return true;
});
