import { createDocsSnippetFiles, createPlaygroundShareUrl } from "./playground_share";

function getVisibleCodePanel(container: Element): HTMLElement | null {
  // Find all code panels in this container
  const panels = Array.from(container.querySelectorAll<HTMLElement>(".code-example-panel"));
  
  // Find the visible one (the one whose tab radio is checked)
  const containerRadios = Array.from(container.querySelectorAll<HTMLInputElement>(".code-example-tab-radio"));
  const checkedRadio = containerRadios.find(radio => radio.checked);
  
  if (checkedRadio) {
    const checkedIndex = containerRadios.indexOf(checkedRadio);
    if (checkedIndex >= 0 && checkedIndex < panels.length) {
      return panels[checkedIndex];
    }
  }
  
  // Fallback to first visible panel
  return panels.find(panel => window.getComputedStyle(panel).display !== "none") || panels[0] || null;
}

function extractCodeFromPanel(panel: HTMLElement | null): string {
  if (!panel) return "";
  
  const codeElement = panel.querySelector("code");
  if (!codeElement) return "";
  
  // Get text content (automatically strips HTML tags)
  return codeElement.textContent?.trim() || "";
}

function setupHomeCodeExampleButtons() {
  const buttons = document.querySelectorAll<HTMLButtonElement>(".code-example-open-playground");
  if (buttons.length === 0) return;

  buttons.forEach((button) => {
    button.addEventListener("click", async (event) => {
      event.preventDefault();

      // Find the parent code example container
      const container = button.closest(".code-example, .code-preview-example");
      if (!container) return;

      let code = "";
      
      // Determine container type and extract code accordingly
      if (container.classList.contains("code-example--tabs")) {
        // Multi-tab code example
        const panel = getVisibleCodePanel(container);
        code = extractCodeFromPanel(panel);
      } else if (container.classList.contains("code-preview-example")) {
        // Code preview with live preview
        const panel = container.querySelector<HTMLElement>(".code-preview-code .code-example-panel") || 
                     container.querySelector<HTMLElement>("pre code");
        if (panel) {
          code = panel.textContent?.trim() || "";
        }
      }

      if (!code) return;

      // Create snippet files and generate share URL
      const files = createDocsSnippetFiles(code, "example.zx");
      const url = await createPlaygroundShareUrl(files, `${window.location.origin}/playground`);
      window.open(url, "_blank", "noopener,noreferrer");
    });
  });
}

document.addEventListener("DOMContentLoaded", () => {
  setupHomeCodeExampleButtons();
});
