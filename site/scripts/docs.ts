import "../assets/clipboard";
// import "./routing";

// Dynamic import to reduce initial bundle size
async function formatHTML(html: string, printWidth: number): Promise<string> {
  const prettier = await import("prettier");
  const prettierPluginHtml = await import("prettier/plugins/html.js");
  
  return await prettier.format(html, {
    parser: "html",
    plugins: [prettierPluginHtml],
    printWidth: printWidth,
    singleAttributePerLine: false,
    htmlWhitespaceSensitivity: "css",
  });
}

// Calculate printWidth based on window width
function getPrintWidth(): number {
  const width = window.innerWidth;
  
  // Responsive breakpoints for printWidth
  if (width < 640) {
    // Mobile: ~30 chars
    return 30;
  } else if (width < 768) {
    // Small tablet: ~40 chars
    return 40;
  } else if (width < 1024) {
    // Tablet: ~60 chars
    return 60;
  } else if (width < 1280) {
    // Desktop: ~80 chars
    return 80;
  } else {
    // Large desktop: ~100 chars
    return 100;
  }
}

// Simple lightweight HTML syntax highlighter
function highlightHTML(html: string): string {
  let result = html;
  
  // HTML comments (must be first to avoid matching inside tags)
  result = result.replace(/&lt;!--[\s\S]*?--&gt;/g, '<span class="comment">$&</span>');
  
  // Doctype
  result = result.replace(/&lt;!DOCTYPE[^&]*&gt;/gi, '<span class="keyword">$&</span>');
  
  // HTML tags with attributes
  result = result.replace(/&lt;(\/?)([\w-]+)([^&]*?)&gt;/g, (match, closing, tagName, attrs) => {
    // Highlight attributes: name="value" or name='value' or name=value
    const attrsHighlighted = attrs.replace(/([\w-]+)(\s*=\s*)("([^"]*)"|'([^']*)'|([^\s>]+))/g, 
      '<span class="attribute">$1</span><span class="punctuation">$2</span><span class="string">$3</span>');
    return `<span class="punctuation">&lt;</span><span class="tag">${closing}${tagName}</span>${attrsHighlighted}<span class="punctuation">&gt;</span>`;
  });
  
  return result;
}

// Find and format HTML code snippets
document.addEventListener("DOMContentLoaded", async () => {
  const htmlCodeElements = document.querySelectorAll<HTMLPreElement>('code.language-markup');

  for (const codeElement of htmlCodeElements) {
    const htmlContent = codeElement.textContent || codeElement.innerText;
    
    if (htmlContent.trim()) {
      try {
        const formatted = await formatHTML(htmlContent, getPrintWidth());
        
        // Escape HTML for highlighting, then apply syntax highlighting
        const escaped = formatted
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
        
        const highlighted = highlightHTML(escaped);
        
        // Update the code element with highlighted HTML
        codeElement.innerHTML = highlighted;
        
      } catch (error) {
        // console.error("Error formatting HTML:", error);
      }
    }
  }

  // Setup section heading anchor links
  setupSectionAnchors();
});

// Convert section headings with IDs into clickable anchor links
function setupSectionAnchors() {
  const linkIcon = `<svg class="section-anchor-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
    <path d="M7.775 3.275a.75.75 0 0 0 1.06 1.06l1.25-1.25a2 2 0 1 1 2.83 2.83l-2.5 2.5a2 2 0 0 1-2.83 0 .75.75 0 0 0-1.06 1.06 3.5 3.5 0 0 0 4.95 0l2.5-2.5a3.5 3.5 0 0 0-4.95-4.95l-1.25 1.25Z"/>
    <path d="M8.225 12.725a.75.75 0 0 0-1.06-1.06l-1.25 1.25a2 2 0 1 1-2.83-2.83l2.5-2.5a2 2 0 0 1 2.83 0 .75.75 0 0 0 1.06-1.06 3.5 3.5 0 0 0-4.95 0l-2.5 2.5a3.5 3.5 0 0 0 4.95 4.95l1.25-1.25Z"/>
  </svg>`;

  function makeAnchor(heading: HTMLHeadingElement, id: string) {
    // Skip if already processed
    if (heading.querySelector('.section-anchor')) return;

    // Get the text content
    const textContent = heading.innerHTML;

    // Create the anchor link wrapper
    const anchor = document.createElement('a');
    anchor.href = `#${id}`;
    anchor.className = 'section-anchor';
    anchor.innerHTML = textContent + linkIcon;

    // Clear the heading and add the anchor
    heading.innerHTML = '';
    heading.appendChild(anchor);

    // Handle click to copy the link
    anchor.addEventListener('click', async () => {
      // Allow normal navigation but also copy the link
      const url = new URL(window.location.href);
      url.hash = id;
      
      try {
        await navigator.clipboard.writeText(url.toString());
      } catch {
        // Fallback - just let the browser handle the navigation
      }
    });
  }

  // Handle h2/h3 with IDs directly on them
  const headingsWithIds = document.querySelectorAll<HTMLHeadingElement>('.section h2[id], .section h3[id]');
  headingsWithIds.forEach((heading) => {
    const id = heading.id;
    if (id) makeAnchor(heading, id);
  });

  // Handle h2 that are direct children of sections with IDs (but h2 has no ID)
  const sections = document.querySelectorAll<HTMLElement>('.section[id]');
  sections.forEach((section) => {
    const sectionId = section.id;
    if (!sectionId) return;
    
    // Find the first h2 that's a direct child (or within a container div)
    const h2 = section.querySelector<HTMLHeadingElement>(':scope > h2, :scope > div > h2');
    if (h2 && !h2.id) {
      makeAnchor(h2, sectionId);
    }
  });
}

function getOS() {
  const userAgent = navigator.userAgent;
  if (/Windows NT/i.test(userAgent)) {
      return 'windows';
  } else if (/Macintosh|Mac OS X/i.test(userAgent)) {
      return 'macos';
  } else if (/Android/i.test(userAgent)) {
      return 'android';
  } else if (/iPhone|iPad|iPod/i.test(userAgent)) {
      return 'ios';
  } else if (/Linux/i.test(userAgent)) {
      return 'linux';
  }
  return 'unknown';
}

// Add OS class to body and auto-select appropriate tabs
const os = getOS();
document.body.classList.add(os);

// Auto-select tabs based on OS
const osTabs = {
  windows: ['tab-windows', 'tab-zig-win'],
  linux: ['tab-zig-other']
};

(osTabs[os] || []).forEach(id => {
  const tab = document.getElementById(id);
  if (tab && tab instanceof HTMLInputElement) tab.checked = true;
});
