import { EditorState } from "@codemirror/state"
import { keymap } from "@codemirror/view"
import { EditorView, basicSetup } from "codemirror"
import { JsonRpcMessage, LspClient } from "./lsp";
import { indentWithTab } from "@codemirror/commands";
import { indentUnit } from "@codemirror/language";
import { editorTheme, editorHighlightStyle } from "./theme.ts";
import zigMainSource from './template/main.zig' with { type: "text" };
import zxModSource from './template/Playground.zx' with { type: "text" };
import zxstylecss from './template/style.css' with { type: "text" };
import { fileManager, PlaygroundFile } from "./file";
import { html } from "@codemirror/lang-html";

export default class ZlsClient extends LspClient {
    public worker: Worker;

    constructor(worker: Worker) {
        super("file:///", []);
        this.worker = worker;
        this.autoClose = false;

        this.worker.addEventListener("message", this.messageHandler);
    }

    private messageHandler = (ev: MessageEvent) => {
        const data = JSON.parse(ev.data);

        if (data.method == "window/logMessage") {
            if (!data.stderr) {
                switch (data.params.type) {
                    case 5:
                        console.debug("ZLS --- ", data.params.message);
                        break;
                    case 4:
                        console.log("ZLS --- ", data.params.message);
                        break;
                    case 3:
                        console.info("ZLS --- ", data.params.message);
                        break;
                    case 2:
                        console.warn("ZLS --- ", data.params.message);
                        break;
                    case 1:
                        console.error("ZLS --- ", data.params.message);
                        break;
                    default:
                        console.error(data.params.message);
                        break;
                }
            }
        } else {
            console.debug("LSP <<-", data);
        }
        this.handleMessage(data);
    };

    public async sendMessage(message: JsonRpcMessage): Promise<void> {
        console.debug("LSP ->>", message);
        if (this.worker) {
            this.worker.postMessage(JSON.stringify(message));
        }
    }

    public async close(): Promise<void> {
        super.close();
        this.worker.terminate();
    }
}

let client = new ZlsClient(new Worker('/assets/playground/workers/zls.js'));


interface EditorFile {
    name: string;
    state: EditorState;
    hidden?: boolean;
    locked?: boolean; // if true, file cannot be renamed or deleted
}

let files: EditorFile[] = [];
let activeFileIndex = -1;
let editorView: EditorView;

function createEditorState(filename: string, content: string) {
    const extensions = [
        basicSetup,
        editorTheme,
        editorHighlightStyle,
        indentUnit.of("    "),
        client.createPlugin(`file:///${filename}`, "zig", true),
        keymap.of([indentWithTab]),
    ];
    // Add HTML highlighting for .zx files
    if (filename.endsWith(".zx")) {
        extensions.push(html());
    }
    return EditorState.create({
        doc: content,
        extensions,
    });
}

function getFileIcon(filename: string): string {
    if (filename.endsWith('.zig')) return '⚡';
    if (filename.endsWith('.zx')) return '⚡';
    if (filename.endsWith('.css')) return '🎨';
    if (filename.endsWith('.html')) return '📄';
    if (filename.endsWith('.js') || filename.endsWith('.ts')) return '📜';
    return '📄';
}

function updateTabs() {
    const tabsContainer = document.getElementById("pg-tabs")!;
    // Remove all tab buttons but keep the add-file button
    const addBtn = document.getElementById("pg-add-file");
    tabsContainer.innerHTML = "";

    files.forEach((file, index) => {
        if (file.hidden) return;
        const tab = document.createElement("button");
        tab.className = `pg-tab${index === activeFileIndex ? " pg-tab--active" : ""}`;
        tab.setAttribute("data-file", file.name);
        tab.id = `pg-tab-${index}`;

        const iconSpan = document.createElement("span");
        iconSpan.className = "pg-tab-icon";
        iconSpan.textContent = getFileIcon(file.name);
        tab.appendChild(iconSpan);

        tab.appendChild(document.createTextNode(file.name));

        const closeBtn = document.createElement("span");
        closeBtn.className = "pg-tab-close";
        closeBtn.setAttribute("aria-label", "Close tab");
        closeBtn.innerHTML = "×";
        if (file.locked) {
            closeBtn.style.opacity = "0.3";
            closeBtn.style.pointerEvents = "none";
            closeBtn.title = "Main playground file: cannot rename or close, and fn Playground must exist in it";
        } else {
            closeBtn.onclick = (e) => {
                e.stopPropagation();
                removeFile(index);
            };
        }
        tab.appendChild(closeBtn);

        tab.onclick = () => switchFile(index);
        if (!file.locked) {
            tab.ondblclick = () => renameFile(index);
        } else {
            tab.ondblclick = null;
            tab.title = "Main playground file: cannot rename or close, and fn Playground must exist in it";
        }

        tabsContainer.appendChild(tab);
    });

    // Re-append the add-file button at the end
    if (addBtn) {
        tabsContainer.appendChild(addBtn);
    } else {
        const newAddBtn = document.createElement("button");
        newAddBtn.className = "pg-tab-add";
        newAddBtn.id = "pg-add-file";
        newAddBtn.setAttribute("aria-label", "Add new file");
        newAddBtn.title = "New file";
        newAddBtn.textContent = "+";
        newAddBtn.addEventListener("click", addFile);
        tabsContainer.appendChild(newAddBtn);
    }
}

async function switchFile(index: number) {
    if (index === activeFileIndex) return;

    if (activeFileIndex !== -1 && editorView) {
        files[activeFileIndex].state = editorView.state;
        // Update fileManager content
        fileManager.updateContent(files[activeFileIndex].name, editorView.state.doc.toString());
    }

    activeFileIndex = index;
    const file = files[index];

    if (!editorView) {
        editorView = new EditorView({
            state: file.state,
            parent: document.getElementById("pg-code-area")!,
        });
    } else {
        editorView.setState(file.state);
    }

    updateTabs();
}

function addFile() {
    let name = "untitled.zig";
    let counter = 0;
    while (fileManager.hasFile(name)) {
        counter++;
        name = `untitled${counter}.zig`;
    }
    fileManager.addFile(name, "");
    const newFile: EditorFile = {
        name,
        state: createEditorState(name, ""),
    };
    files.push(newFile);
    switchFile(files.length - 1);
}

function removeFile(index: number) {
    if (files[index].locked) {
        alert("This file is locked and cannot be deleted.");
        return;
    }
    fileManager.removeFile(files[index].name);
    files.splice(index, 1);
    if (activeFileIndex >= files.length) {
        activeFileIndex = files.length - 1;
    }
    switchFile(activeFileIndex);
    updateTabs();
}

function renameFile(index: number) {
    const file = files[index];
    if (file.locked) {
        alert("This file is locked and cannot be renamed.");
        return;
    }
    const newName = prompt("Rename file:", file.name);
    if (newName && newName !== file.name && newName.endsWith(".zig")) {
        if (fileManager.hasFile(newName)) {
            alert("File already exists!");
            return;
        }
        const content = file.state.doc.toString();
        if (fileManager.renameFile(file.name, newName)) {
            file.name = newName;
            file.state = createEditorState(newName, content);
            if (index === activeFileIndex) {
                editorView.setState(file.state);
            }
            updateTabs();
        } else {
            alert("Rename failed!");
        }
    }
}



(async () => {
    await client.initialize();

    // Initialize fileManager and files[]
    fileManager.addFile("Playground.zx", zxModSource);
    fileManager.addFile("main.zig", zigMainSource);
    fileManager.addFile("style.css", zxstylecss);

    files = fileManager.getAllFiles().map(f => {
        return {
            name: f.name,
            state: createEditorState(f.name, f.content),
            hidden: f.name === "main.zig",
            locked: f.name === "Playground.zx" || f.name === "main.zig", // lock template files
        };
    });

    updateTabs();
    await switchFile(0);
})();

document.getElementById("pg-add-file")?.addEventListener("click", addFile);

// Convert vertical mouse wheel to horizontal scroll on the tabs bar
const tabsEl = document.getElementById("pg-tabs")!;
tabsEl.addEventListener("wheel", (e) => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
        e.preventDefault();
        tabsEl.scrollLeft += e.deltaY;
    }
}, { passive: false });

// Show/hide right scroll shadow when tabs overflow
function updateTabsScrollShadow() {
    const hasOverflowRight = tabsEl.scrollLeft + tabsEl.clientWidth < tabsEl.scrollWidth - 1;
    tabsEl.classList.toggle("scroll-shadow-right", hasOverflowRight);
}
tabsEl.addEventListener("scroll", updateTabsScrollShadow);
new ResizeObserver(updateTabsScrollShadow).observe(tabsEl);
new MutationObserver(updateTabsScrollShadow).observe(tabsEl, { childList: true });

function revealOutputWindow() {
    const outputs = document.getElementById("pg-terminal-body")!;
    outputs.scrollTo(0, outputs.scrollHeight!);
    const splitPane = document.getElementById("split-pane")!;
    // const editorHeightPercent = parseFloat(splitPane.style.getPropertyValue("--editor-height-percent"));
    // if (editorHeightPercent == 100) {
    //     splitPane.style.setProperty("--editor-height-percent", `${resizeBarPreviousSize}%`);
    // }
}

let zigWorker = new Worker('/assets/playground/workers/zig.js');
let zxWorker = new Worker('/assets/playground/workers/zx.js');

function setRunButtonLoading(loading: boolean) {
    const btn = document.getElementById("pg-run-btn")!;
    if (loading) {
        btn.classList.add("pg-nav-btn--loading");
        btn.setAttribute("disabled", "true");
        btn.innerHTML = '<span class="pg-spinner"></span>';
    } else {
        btn.classList.remove("pg-nav-btn--loading");
        btn.removeAttribute("disabled");
        btn.innerHTML = '▶ Run';
    }
}

function appendTerminalLine(text: string, className?: string) {
    const termBody = document.getElementById("pg-terminal-body")!;
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

function clearTerminal() {
    const termBody = document.getElementById("pg-terminal-body")!;
    termBody.innerHTML = "";
}

zxWorker.onmessage = (ev: MessageEvent) => {
    console.info("Transpiled finished in", (performance.now() - build_start_time).toFixed(2), "ms");
    console.debug("ZX Worker ->>", ev.data);
}

zigWorker.onmessage = (ev: MessageEvent) => {
    console.info("Build finished in", (performance.now() - build_start_time).toFixed(2), "ms");

    if (ev.data.stderr) {
        // Append compiler stderr as error lines
        const lines = ev.data.stderr.split('\n').filter((l: string) => l.length > 0);
        for (const l of lines) {
            appendTerminalLine(l, "pg-terminal-error");
        }
        revealOutputWindow();
        return;
    } else if (ev.data.failed) {
        appendTerminalLine("Compilation failed.", "pg-terminal-error");
        setRunButtonLoading(false);
    } else if (ev.data.compiled) {
        // appendTerminalLine("Compiled successfully. Running…", "pg-terminal-success");
        let runnerWorker = new Worker('/assets/playground/workers/runner.js');

        runnerWorker.postMessage({ run: ev.data.compiled });

        runnerWorker.onmessage = (rev: MessageEvent) => {
            if (rev.data.stderr) {
                appendTerminalLine("", "pg-terminal-info");
                const lines = rev.data.stderr.split('\n').filter((l: string) => l.length > 0);
                for (const l of lines) {
                    appendTerminalLine(l, "pg-terminal-info");
                }
                revealOutputWindow();
                return;
            } else if (rev.data.preview) {
                const viewport = document.getElementById("pg-browser-viewport")!;
                let iframe = viewport.querySelector("iframe") as HTMLIFrameElement;
                if (!iframe) {
                    viewport.innerHTML = "";
                    iframe = document.createElement("iframe");
                    iframe.style.width = "100%";
                    iframe.style.height = "100%";
                    iframe.style.border = "none";
                    iframe.style.backgroundColor = "white";
                    viewport.appendChild(iframe);
                    iframe.contentDocument?.open();
                }
                iframe.contentDocument?.write(rev.data.preview);
                return;
            } else if (rev.data.done) {
                const viewport = document.getElementById("pg-browser-viewport")!;
                const iframe = viewport.querySelector("iframe") as HTMLIFrameElement;
                if (iframe) {
                    iframe.contentDocument?.close();
                }

                runnerWorker.terminate();
                appendTerminalLine("Program exited.\n", "pg-terminal-muted");
                setRunButtonLoading(false);
            }
        }
    }
}


let build_start_time = performance.now();

// Helper to get current files as { [filename]: content }
function getCurrentFilesMap(): { [filename: string]: string } {
    // Sync current editor state to fileManager
    if (activeFileIndex !== -1 && editorView) {
        fileManager.updateContent(files[activeFileIndex].name, editorView.state.doc.toString());
    }
    const filesMap: { [filename: string]: string } = {};
    fileManager.getAllFiles().forEach(f => {
        filesMap[f.name] = f.content;
    });
    return filesMap;
}

const outputsRun = document.getElementById("pg-run-btn")! as HTMLButtonElement;
outputsRun.addEventListener("click", async () => {
    setRunButtonLoading(true);
    clearTerminal();
    const viewport = document.getElementById("pg-browser-viewport")!;
    viewport.innerHTML = `
        <div class="pg-browser-placeholder">
            <div class="pg-browser-placeholder-icon">🌐</div>
            Running…
        </div>`;
    revealOutputWindow();

    let filesMap = getCurrentFilesMap();
    // Find all .zx files
    const zxFiles = Object.entries(filesMap).filter(([name]) => name.endsWith('.zx'));
    let transpiledZigFiles: { [filename: string]: string } = {};


    // Helper to transpile a single .zx file and return a Promise
    function transpileZxFile(zxName: string, zxContent: string): Promise<{ [filename: string]: string }> {
        return new Promise((resolve, reject) => {
            const handler = (ev: MessageEvent) => {
                console.log('[DEBUG] zxWorker message:', ev.data);
                if (ev.data && ev.data.filename && ev.data.transpiled) {
                    zxWorker.removeEventListener('message', handler);
                    resolve({ [ev.data.filename]: ev.data.transpiled });
                } else if (ev.data && ev.data.failed) {
                    zxWorker.removeEventListener('message', handler);
                    appendTerminalLine(ev.data.stderr || "Transpile failed", "pg-terminal-error");
                    setRunButtonLoading(false);
                    reject(ev.data.stderr);
                } else if (ev.data && ev.data.stderr) {
                    // If only stderr is returned, treat as transpiled .zig content
                    zxWorker.removeEventListener('message', handler);
                    const zigName = zxName.replace(/\.zx$/, ".zig");
                    console.log('[DEBUG] Treating stderr as transpiled .zig for', zigName);
                    resolve({ [zigName]: ev.data.stderr });
                }
            };
            zxWorker.addEventListener('message', handler);
            console.log('[DEBUG] Posting to zxWorker:', zxName);
            zxWorker.postMessage({ filename: zxName, content: zxContent });
        });
    }

    // Transpile each .zx file sequentially
    for (const [zxName, zxContent] of zxFiles) {
        console.log('[DEBUG] Transpiling', zxName);
        try {
            transpiledZigFiles = await transpileZxFile(zxName, zxContent);
            console.log('[DEBUG] Transpiled result:', transpiledZigFiles);
            // Add transpiled .zig file to filesMap
            Object.assign(filesMap, transpiledZigFiles);
            // Also update fileManager and files[] if .zig file exists in tabs, else add it as hidden
            const zigName = Object.keys(transpiledZigFiles)[0];
            const zigContent = transpiledZigFiles[zigName];
            if (fileManager.hasFile(zigName)) {
                fileManager.updateContent(zigName, zigContent);
                let zigFile = files.find(f => f.name === zigName);
                if (zigFile) {
                    zigFile.state = createEditorState(zigName, zigContent);
                    zigFile.hidden = true;
                }
            } else {
                fileManager.addFile(zigName, zigContent);
                files.push({ name: zigName, state: createEditorState(zigName, zigContent), hidden: true });
            }
        } catch (err) {
            console.error('[DEBUG] Transpile error:', err);
            return; // Stop further processing if transpile fails
        }
    }

    // Now send all files (including transpiled .zig) to zigWorker
    console.log('[DEBUG] Sending files to zigWorker:', Object.keys(filesMap));
    build_start_time = performance.now();
    zigWorker.postMessage({ files: filesMap });
});
