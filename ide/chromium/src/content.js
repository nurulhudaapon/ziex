// Content script that runs on web pages
// This detects Ziex and prepares the environment

function detectZiex() {
  // Check if Ziex is loaded
  const hasZiex = !!window.__ZIEX__ || !!window.Ziex || !!window.__zx_dev_reinit || !!window.__ZIEX_DEVTOOLS_GLOBAL_HOOK__;

  if (hasZiex) {
    console.log('Ziex detected on page');
  }
}

// Run detection
detectZiex();

// Also check after DOM is loaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', detectZiex);
} else {
  detectZiex();
}

// Detect SPA navigations (pushState/replaceState/popstate)
// and notify the devtools panel so it can refetch components.
(function observeNavigation() {
  let lastHref = location.href;

  function notifyNavigation() {
    const href = location.href;
    if (href === lastHref) return;
    lastHref = href;
    chrome.runtime.sendMessage({ type: 'zx-navigation', href }).catch(() => {});
  }

  // Patch History API
  const origPushState = history.pushState;
  const origReplaceState = history.replaceState;

  history.pushState = function (...args) {
    origPushState.apply(this, args);
    notifyNavigation();
  };
  history.replaceState = function (...args) {
    origReplaceState.apply(this, args);
    notifyNavigation();
  };

  window.addEventListener('popstate', notifyNavigation);
})();
