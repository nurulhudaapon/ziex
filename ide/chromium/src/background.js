// Background service worker for Chrome extension
chrome.runtime.onInstalled.addListener(() => {
  console.log('Ziex DevTools installed');
});

// Handle messages from content scripts or devtools
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('Message received:', message);
  sendResponse({ success: true });
  return true;
});
