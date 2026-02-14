// Content script that runs on web pages
// This detects Ziex and prepares the environment

function detectZiex() {
  // Check if Ziex is loaded
  const hasZiex = !!window.__ZIEX__ || !!window.Ziex;
  
  if (hasZiex) {
    console.log('Ziex detected on page');
    
    // Inject hook for Ziex devtools
    const script = document.createElement('script');
    script.textContent = `
      window.__ZIEX_DEVTOOLS_GLOBAL_HOOK__ = {
        enabled: true,
        version: '1.0.0'
      };
    `;
    document.documentElement.appendChild(script);
    script.remove();
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
