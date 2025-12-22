import * as prettier from "https://unpkg.com/prettier@3.6.2/standalone.mjs";
import * as prettierPluginHtml from "https://unpkg.com/prettier@3.6.2/plugins/html.mjs";

// Find and format HTML code snippets
document.addEventListener("DOMContentLoaded", async () => {
  const htmlCodeElements = document.querySelectorAll('code.language-markup');

  for (const codeElement of htmlCodeElements) {
    const htmlContent = codeElement.textContent || codeElement.innerText;
    
    if (htmlContent.trim()) {
      try {
        const formatted = await prettier.format(htmlContent, {
          parser: "html",
          plugins: [prettierPluginHtml],
          printWidth: 120,
          singleAttributePerLine: false,
          htmlWhitespaceSensitivity: "css",
        });
        
        // Update the code element with formatted content
        codeElement.textContent = formatted;
        
      } catch (error) {
        // console.error("Error formatting HTML:", error);
      }
    }
  }

  // Setup copy buttons for code blocks and install boxes
  setupCopyButtons();
});

function setupCopyButtons() {
  const copyButtonHTML = `
    <svg class="copy-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25v-7.5Z"></path>
      <path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25v-7.5Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25h-7.5Z"></path>
    </svg>
    <svg class="check-icon" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true" style="display: none;">
      <path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path>
    </svg>
  `;

  function showCopied(button) {
    const copyIcon = button.querySelector('.copy-icon');
    const checkIcon = button.querySelector('.check-icon');
    copyIcon.style.display = 'none';
    checkIcon.style.display = 'block';
    button.classList.add('copied');
    button.setAttribute('aria-label', 'Copied!');
    
    setTimeout(() => {
      copyIcon.style.display = 'block';
      checkIcon.style.display = 'none';
      button.classList.remove('copied');
      button.setAttribute('aria-label', 'Copy code');
    }, 2000);
  }

  async function copyText(text, button) {
    try {
      await navigator.clipboard.writeText(text);
      showCopied(button);
    } catch (err) {
      // Fallback for older browsers
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.opacity = '0';
      document.body.appendChild(textArea);
      textArea.select();
      try {
        document.execCommand('copy');
        showCopied(button);
      } catch (fallbackErr) {
        console.error('Copy failed:', fallbackErr);
      }
      document.body.removeChild(textArea);
    }
  }

  // Setup for regular code blocks (pre code)
  document.querySelectorAll('pre code').forEach((codeElement) => {
    const preElement = codeElement.parentElement;
    if (!preElement || preElement.querySelector('.copy-button')) return;
    
    const copyButton = document.createElement('button');
    copyButton.className = 'copy-button';
    copyButton.setAttribute('aria-label', 'Copy code');
    copyButton.innerHTML = copyButtonHTML;
    
    copyButton.addEventListener('click', () => {
      copyText(codeElement.textContent || codeElement.innerText, copyButton);
    });
    
    preElement.appendChild(copyButton);
  });

  // Setup for install boxes
  document.querySelectorAll('.install-box').forEach((box) => {
    if (box.querySelector('.copy-button')) return;
    
    const copyButton = document.createElement('button');
    copyButton.className = 'copy-button install-box-copy';
    copyButton.setAttribute('aria-label', 'Copy command');
    copyButton.innerHTML = copyButtonHTML;
    
    copyButton.addEventListener('click', () => {
      // Find the visible install code based on checked radio button
      let installCode = null;
      
      // Check which radio is checked and find corresponding content
      const checkedRadio = box.querySelector('.install-tab-radio:checked');
      if (checkedRadio) {
        const contentId = 'content-' + checkedRadio.id.replace('tab-', '');
        const visibleTab = box.querySelector('#' + contentId);
        installCode = visibleTab?.querySelector('.install-code');
      }
      
      // Fallback for simple boxes without tabs
      if (!installCode) {
        installCode = box.querySelector('.install-code');
      }
      
      if (!installCode) return;
      
      // Extract text, handling multiline
      const lines = installCode.querySelectorAll('.install-code-multiline > div');
      let text;
      if (lines.length > 0) {
        text = Array.from(lines).map(line => 
          line.textContent.replace(/^\$\s*|^>\s*/, '').trim()
        ).join(' && ');
      } else {
        text = installCode.textContent.replace(/^\$\s*|^>\s*/, '').trim();
      }
      
      copyText(text, copyButton);
    });
    
    // Add to header if it exists, otherwise to content
    const header = box.querySelector('.install-box-header');
    const content = box.querySelector('.install-box-content');
    if (header) {
      header.appendChild(copyButton);
    } else if (content) {
      content.appendChild(copyButton);
    }
  });
}

// Setup "ON THIS PAGE" navigation for docs and CLI pages
function setupOnThisPage() {
  const content = document.querySelector('.content');
  const nav = document.getElementById('on-this-page-nav');
  if (!content || !nav) return;

  // Get all headings, but filter out those inside code examples or code blocks
  const allHeadings = content.querySelectorAll('h1, h2, h3, h4');
  const items = [];

  allHeadings.forEach(function(heading) {
    // Skip headings inside code blocks, example blocks, or pre elements
    if (heading.closest('pre') || 
        heading.closest('.code-example') || 
        heading.closest('.example-code') ||
        heading.closest('code') ||
        heading.closest('.code-wrapper') ||
        heading.closest('iframe')) {
      return;
    }

    const id = heading.id || heading.textContent.toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '');
    if (!heading.id) {
      heading.id = id;
    }

    const level = parseInt(heading.tagName.charAt(1));
    const text = heading.textContent.trim();
    
    items.push({ level: level, id: id, text: text });
  });

  if (items.length === 0) {
    const sidebar = document.getElementById('on-this-page');
    if (sidebar) sidebar.style.display = 'none';
    return;
  }

  items.forEach(function(item) {
    const link = document.createElement('a');
    link.href = '#' + item.id;
    link.textContent = item.text;
    link.className = 'right-sidebar-link';
    if (item.level > 2) {
      link.className += ' right-sidebar-link-nested';
      link.style.paddingLeft = ((item.level - 2) * 1) + 'rem';
    }
    nav.appendChild(link);
  });

  // Highlight active section on scroll
  function updateActiveLink() {
    const scrollPos = window.scrollY + 100;
    let current = '';
    
    items.forEach(function(item) {
      const element = document.getElementById(item.id);
      if (element && element.offsetTop <= scrollPos) {
        current = item.id;
      }
    });

    nav.querySelectorAll('.right-sidebar-link').forEach(function(link) {
      link.classList.remove('active');
      if (link.getAttribute('href') === '#' + current) {
        link.classList.add('active');
      }
    });
  }

  window.addEventListener('scroll', updateActiveLink);
  updateActiveLink();
}

// Initialize ON THIS PAGE navigation when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', setupOnThisPage);
} else {
  setupOnThisPage();
}