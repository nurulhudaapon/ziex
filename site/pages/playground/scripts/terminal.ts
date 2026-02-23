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

    // Hide the empty-state placeholder once we have output
    document.getElementById("pg-terminal-empty")?.classList.add("hidden");

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
    if (!termBody) return;
    // Remove all children except the empty-state element
    Array.from(termBody.children).forEach(child => {
        if (child.id !== "pg-terminal-empty") child.remove();
    });
    // Restore the empty-state placeholder
    document.getElementById("pg-terminal-empty")?.classList.remove("hidden");
}

/** Append a new animated pipeline step row to the terminal. */
export function appendStatusStep(stepId: string, label: string): void {
    const termBody = document.getElementById("pg-terminal-body");
    if (!termBody) return;

    // Hide empty-state placeholder
    document.getElementById("pg-terminal-empty")?.classList.add("hidden");

    const line = document.createElement("div");
    line.className = "pg-status-step pg-status-step--running";
    line.id = `pg-status-step-${stepId}`;
    line.dataset.step = stepId;
    line.dataset.start = String(performance.now());

    const iconEl = document.createElement("span");
    iconEl.className = "pg-status-step-icon";

    const labelEl = document.createElement("span");
    labelEl.className = "pg-status-step-label";
    labelEl.textContent = label;

    const timeEl = document.createElement("span");
    timeEl.className = "pg-status-step-time";

    line.appendChild(iconEl);
    line.appendChild(labelEl);
    line.appendChild(timeEl);
    termBody.appendChild(line);
    revealOutputWindow();
}

/** Mark a pipeline step as done or errored, stamping elapsed time. */
export function completeStatusStep(stepId: string, state: 'done' | 'error'): void {
    const line = document.getElementById(`pg-status-step-${stepId}`);
    if (!line) return;

    line.classList.remove("pg-status-step--running");
    line.classList.add(`pg-status-step--${state}`);

    const timeEl = line.querySelector(".pg-status-step-time") as HTMLElement | null;
    if (timeEl && line.dataset.start) {
        const elapsed = performance.now() - parseFloat(line.dataset.start);
        timeEl.textContent = `${(elapsed / 1000).toFixed(2)}s`;
    }
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
