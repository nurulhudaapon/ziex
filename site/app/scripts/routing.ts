const routecache = new Map<string, string>();

function handleRouteClick(e: Event) {
  const target = e.target as Element;
  const link = target.closest('a[link]');
  if (!link) return;
  
  e.preventDefault();
  const href = link.getAttribute('href');
  if (!href) return;

  // Check cache first
  if (routecache.has(href)) {
    const html = routecache.get(href)!;
    updatePageContent(html, href);
    return;
  }
  
  // Fetch the page
  fetch(href)
    .then(r => r.text())
    .then(html => {
      // Cache the HTML string (not the DOM)
      routecache.set(href, html);
      updatePageContent(html, href);
    })
    .catch(err => console.error('Navigation failed:', err));
}

function updatePageContent(html: string, href: string) {
  const parser = new DOMParser();
  const newDoc = parser.parseFromString(html, 'text/html');
  
  // Update only main content
  const oldMain = document.querySelector('main');
  const newMain = newDoc.querySelector('main');
  
  if (oldMain && newMain) {
    oldMain.replaceWith(newMain);
  }
  
  // Update page title
  const newTitle = newDoc.querySelector('title');
  if (newTitle) {
    document.title = newTitle.textContent || '';
  }
  
  // Update history
  window.history.pushState({}, '', href);
  
  // Scroll to top
  window.scrollTo(0, 0);
  
  // Re-run initialization for NEW content only
  reinitializeContentHandlers();
}

function reinitializeContentHandlers() {
  // Only setup handlers for new content
  
  // If you have syntax highlighting for code blocks, rerun it
  // formatCodeBlocks();
}

function handlePrefetch(e: Event) {
  const target = e.target as Element;
  const link = target.closest('a[link]');
  if (!link) return;
  
  const href = link.getAttribute('href');
  if (!href || routecache.has(href)) return;
  
  fetch(href, { priority: 'low' as any })
    .then(r => r.text())
    .then(html => {
      routecache.set(href, html);
    })
    .catch(err => console.warn('Prefetch failed:', href, err));
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
  // Add listeners once (not in setupRouteHandlers)
  document.addEventListener('click', handleRouteClick);
  document.addEventListener('mouseover', handlePrefetch);
  
});

// Handle back button
window.addEventListener('popstate', (e) => {
  // Re-fetch the page at current URL
  const href = window.location.pathname + window.location.search;
  fetch(href)
    .then(r => r.text())
    .then(html => updatePageContent(html, href))
    .catch(() => window.location.reload());
});