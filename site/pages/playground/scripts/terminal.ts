export function setTerminalCollapsed(collapsed: boolean) {
    const terminal = document.getElementById("pg-terminal");
    const preview = document.getElementById("pg-preview");
    const toggleBtn = document.getElementById("pg-terminal-toggle");
    if (!terminal) return;
    if (collapsed) {
        terminal.classList.add("collapsed");
        if (preview) preview.classList.add("terminal-collapsed");
        if (toggleBtn) toggleBtn.innerHTML = "▲";
    } else {
        terminal.classList.remove("collapsed");
        if (preview) preview.classList.remove("terminal-collapsed");
        if (toggleBtn) toggleBtn.innerHTML = "▼";
    }
}

export function revealOutputWindow() {
    const outputs = document.getElementById("pg-terminal-body");
    if (outputs) outputs.scrollTo(0, outputs.scrollHeight!);
}

export function appendTerminalLine(text: string, className?: string) {
    const termBody = document.getElementById("pg-terminal-body");
    if (!termBody) return;
    
    const line = document.createElement("span");
    line.className = "pg-terminal-line";

    const prompt = document.createElement("span");
    prompt.className = "pg-terminal-prompt";
    prompt.textContent = "";
    line.appendChild(prompt);

    const content = document.createElement("span");
    if (className) content.className = className;
    content.textContent = text;
    line.appendChild(content);
    termBody.appendChild(line);
}

export function clearTerminal() {
    const termBody = document.getElementById("pg-terminal-body");
    if (termBody) termBody.innerHTML = "";
}

window.addEventListener("DOMContentLoaded", () => {
    // Collapse terminal by default on load
    setTerminalCollapsed(true);

    // Toggle button logic
    document.getElementById("pg-terminal-toggle")?.addEventListener("click", (e) => {
        const terminal = document.getElementById("pg-terminal");
        if (terminal) setTerminalCollapsed(!terminal.classList.contains("collapsed"));
        e.stopPropagation();
    });

    // Clear button logic
    document.getElementById("pg-terminal-clear")?.addEventListener("click", (e) => {
        clearTerminal();
        e.stopPropagation();
    });

    // Also allow clicking the header to toggle
    document.getElementById("pg-terminal-header")?.addEventListener("click", (e) => {
        if ((e.target as any).id !== "pg-terminal-toggle" && (e.target as any).id !== "pg-terminal-clear") {
            const terminal = document.getElementById("pg-terminal");
            if (terminal) setTerminalCollapsed(!terminal.classList.contains("collapsed"));
        }
    });
});
