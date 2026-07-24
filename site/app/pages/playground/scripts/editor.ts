import { appendTerminalLine, revealOutputWindow, setTerminalCollapsed, clearTerminal, appendStatusStep, completeStatusStep } from "./terminal.ts";
import { EditorState, Prec } from "@codemirror/state"
import { keymap, ViewPlugin, type ViewUpdate } from "@codemirror/view"
import { EditorView, basicSetup } from "codemirror"
import { createZlsClient, workerTransport } from "./lsp";
import { formatDocument } from "@codemirror/lsp-client";
import { indentWithTab } from "@codemirror/commands";
import { indentUnit } from "@codemirror/language";
import { editorTheme, editorHighlightStyle } from "./theme.ts";
import { isGeneratedPlaygroundPath, CLIENT_WASM_PLACEHOLDER, type PlaygroundBuildArtifacts } from "./csr.ts";
import {
    type PlaygroundMode,
    defaultTemplateId,
    getTemplate,
    templatesForMode,
} from "./templates.ts";
// @ts-ignore
import stubZxOptsServer from './template/stubs/zx_module_options_server.zig' with { type: "text" };
// @ts-ignore
import stubZxOptsClient from './template/stubs/zx_module_options_client.zig' with { type: "text" };
// @ts-ignore
import stubZxInfo from './template/stubs/zx_info.zig' with { type: "text" };
// @ts-ignore
import stubAppOpts from './template/stubs/app_opts.zig' with { type: "text" };
// @ts-ignore
import stubManifest from './template/stubs/manifest.zon' with { type: "text" };
// @ts-ignore
import stubBuildInjections from './template/stubs/build_injections.zon' with { type: "text" };
import { fileManager, PlaygroundFile } from "./file";
import { html } from "@codemirror/lang-html";
import { css } from "@codemirror/lang-css";
import { javascript } from "@codemirror/lang-javascript";
import { createPlaygroundShareUrl, decodeFilesFromQuery } from "../../../scripts/playground_share";

// TODO: zls is not available for Zig 0.17 yet.
let client = createZlsClient(workerTransport(new Worker('/assets/playground/workers/zls.js')));
const PLAYGROUND_NOTICE_STORAGE_KEY = "playground_feature_notice_dismissed_v1";
const MODE_STORAGE_KEY = "playground_mode_v1";
const TEMPLATE_STORAGE_KEY = "playground_template_v1";

let playgroundMode: PlaygroundMode = "playground";
let activeTemplateId = defaultTemplateId("playground");

try {
    const savedMode = localStorage.getItem(MODE_STORAGE_KEY);
    if (savedMode === "app" || savedMode === "playground") playgroundMode = savedMode;
    const savedTemplate = localStorage.getItem(TEMPLATE_STORAGE_KEY);
    if (savedTemplate && getTemplate(savedTemplate)?.mode === playgroundMode) {
        activeTemplateId = savedTemplate;
    } else {
        activeTemplateId = defaultTemplateId(playgroundMode);
    }
} catch { /* ignore */ }

window.addEventListener("message", (ev: MessageEvent) => {
    if (ev.data?.type === "pg-hydrate-error" && typeof ev.data.message === "string") {
        appendTerminalLine(ev.data.message, "pg-terminal-error");
        setTerminalCollapsed(false);
        revealOutputWindow();
    }
});


interface EditorFile {
    name: string;
    state: EditorState;
    hidden?: boolean;
    locked?: boolean; // if true, file cannot be renamed or deleted
}

let files: EditorFile[] = [];
let activeFileIndex = -1;
let editorView: EditorView;
let formatting = false;

function languageLabel(filename: string): string {
    if (filename.endsWith(".zx") || filename.endsWith(".mdzx")) return "ZX";
    if (filename.endsWith(".zig") || filename.endsWith(".zon")) return "Zig";
    if (filename.endsWith(".css")) return "CSS";
    if (filename.endsWith(".html")) return "HTML";
    if (filename.endsWith(".ts") || filename.endsWith(".tsx")) return "TS";
    if (filename.endsWith(".js") || filename.endsWith(".jsx")) return "JS";
    if (filename.endsWith(".md")) return "MD";
    return "File";
}

function updateEditorStatus(view: EditorView, filename: string) {
    const pos = view.state.selection.main.head;
    const line = view.state.doc.lineAt(pos);
    const col = pos - line.from + 1;
    const cursorEl = document.getElementById("pg-cursor-pos");
    if (cursorEl) cursorEl.textContent = `Ln ${line.number}, Col ${col}`;
    const langEl = document.getElementById("pg-file-lang");
    if (langEl) langEl.textContent = languageLabel(filename);
}

function editorStatusPlugin(filename: string) {
    return ViewPlugin.fromClass(class {
        constructor(view: EditorView) {
            updateEditorStatus(view, filename);
        }
        update(update: ViewUpdate) {
            if (update.selectionSet || update.docChanged || update.focusChanged) {
                updateEditorStatus(update.view, filename);
            }
        }
    });
}

function createEditorState(filename: string, content: string) {
    const extensions = [
        basicSetup,
        editorTheme,
        editorHighlightStyle,
        indentUnit.of("    "),
        editorStatusPlugin(filename),
        Prec.highest(keymap.of([
            {
                key: "Shift-Alt-f",
                run: () => {
                    void formatActiveFile();
                    return true;
                },
            },
            {
                key: "Mod-s",
                run: () => {
                    void formatActiveFile();
                    return true;
                },
            },
        ])),
        keymap.of([
            indentWithTab,
            {
                key: "F5",
                run: () => {
                    outputsRun.click();
                    return true;
                },
            },
        ]),
    ];

    if (filename.endsWith('.zig') || filename.endsWith('.zx') || filename.endsWith('.zon')) {
    // TODO: zls is not available for Zig 0.17 yet.
        extensions.push(client.plugin(`file:///${filename}`, "zig"));
    }

    if (filename.endsWith(".zx") || filename.endsWith(".html")) {
        if (filename.endsWith(".zx")) {
            extensions.push(Prec.highest(EditorState.languageData.of(() => [{ commentTokens: { line: "//" } }])));
        }
        extensions.push(html());
    } else if (filename.endsWith(".css")) {
        extensions.push(css());
    } else if (filename.endsWith(".js") || filename.endsWith(".jsx")) {
        extensions.push(javascript({ jsx: true }));
    } else if (filename.endsWith(".ts") || filename.endsWith(".tsx")) {
        extensions.push(javascript({ jsx: true, typescript: true }));
    }
    return EditorState.create({
        doc: content,
        extensions,
    });
}

function getFileClass(filename: string): string {
    if (filename.endsWith('.zig')) return 'zig';
    if (filename.endsWith('.zx')) return 'zx';
    if (filename.endsWith('.css')) return 'css';
    if (filename.endsWith('.html')) return 'html';
    if (filename.endsWith('.md')) return 'md';
    if (filename.endsWith('.jsx')) return 'jsx';
    if (filename.endsWith('.tsx')) return 'tsx';
    if (filename.endsWith('.js')) return 'js';
    if (filename.endsWith('.ts')) return 'ts';
    return 'file';
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
        iconSpan.className = `pg-tab-icon type-${getFileClass(file.name)}`;
        const template = document.getElementById("pg-icons-template") as HTMLTemplateElement;
        if (template) {
            iconSpan.appendChild(template.content.cloneNode(true));
        }
        tab.appendChild(iconSpan);

        const tabLabel = file.name.includes("/") ? file.name.slice(file.name.lastIndexOf("/") + 1) : file.name;
        tab.appendChild(document.createTextNode(tabLabel));

        const closeBtn = document.createElement("span");
        closeBtn.className = "pg-tab-close";
        closeBtn.setAttribute("aria-label", "Close tab");
        closeBtn.innerHTML = "×";
        if (file.locked) {
            closeBtn.style.opacity = "0.3";
            closeBtn.style.pointerEvents = "none";
            closeBtn.title = "Locked framework entry file";
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
            tab.title = file.name;
        }

        tabsContainer.appendChild(tab);
    });

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

    updateEditorStatus(editorView, file.name);
    updateTabs();
}

function addFile() {
    let name = "untitled.zx";
    let counter = 0;
    while (fileManager.hasFile(name)) {
        counter++;
        name = `untitled${counter}.zx`;
    }

    const promptedName = prompt("File name:", name);
    if (!promptedName) return;

    if (fileManager.hasFile(promptedName)) {
        alert("File already exists!");
        return;
    }

    fileManager.addFile(promptedName, "");
    const newFile: EditorFile = {
        name: promptedName,
        state: createEditorState(promptedName, ""),
    };
    files.push(newFile);
    switchFile(files.length - 1);
}

function removeFile(index: number) {
    if (files[index].locked) {
        alert("This file is locked and cannot be deleted.");
        return;
    }

    const removedFileWasActive = (index === activeFileIndex);
    fileManager.removeFile(files[index].name);
    files.splice(index, 1);

    if (removedFileWasActive) {
        activeFileIndex = -1;

        // Find the next visible (non-hidden) file
        let nextIndex = index;
        if (nextIndex >= files.length)  nextIndex = files.length - 1;
        while (nextIndex >= 0 && files[nextIndex]?.hidden) nextIndex--;
        if (nextIndex >= 0) switchFile(nextIndex);
        else updateTabs();
        
    } else {
        if (index < activeFileIndex) activeFileIndex--;
        updateTabs();
    }
}

function renameFile(index: number) {
    const file = files[index];
    if (file.locked) {
        alert("This file is locked and cannot be renamed.");
        return;
    }
    const newName = prompt("Rename file:", file.name);
    if (newName && newName !== file.name) {
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

async function copyText(text: string): Promise<boolean> {
    try {
        await navigator.clipboard.writeText(text);
        return true;
    } catch {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.opacity = '0';
        document.body.appendChild(textArea);
        textArea.select();
        try {
            document.execCommand('copy');
            document.body.removeChild(textArea);
            return true;
        } catch {
            document.body.removeChild(textArea);
            return false;
        }
    }
}

function showShareSuccess() {
    const btn = document.getElementById("pg-share-btn");
    if (!btn) return;
    const orig = btn.innerHTML;
    btn.innerHTML = '<span style="vertical-align:middle;display:inline-block;width:1em;height:1em;margin-right:0.3em;"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="1em" height="1em"><path fill-rule="evenodd" d="M16.704 6.29a1 1 0 0 1 0 1.42l-6.004 6a1 1 0 0 1-1.416 0l-2.996-3a1 1 0 1 1 1.416-1.42l2.288 2.29 5.296-5.29a1 1 0 0 1 1.416 0z" clip-rule="evenodd"/></svg></span>Copied!';
    setTimeout(() => { btn.innerHTML = orig; }, 1200);
}

document.getElementById("pg-share-btn")?.addEventListener("click", async () => {
    const filesMap = getCurrentFilesMap();

    // Create the URL promise for ClipboardItem (Safari needs this pattern for async clipboard)
    const urlPromise = createPlaygroundShareUrl(filesMap, `${location.origin}${location.pathname}`);

    // Try ClipboardItem with Promise first (Safari-friendly for async data)
    let success = false;
    if (navigator.clipboard && typeof ClipboardItem !== 'undefined') {
        try {
            const item = new ClipboardItem({
                'text/plain': urlPromise.then(url => new Blob([url], { type: 'text/plain' }))
            });
            await navigator.clipboard.write([item]);
            success = true;
        } catch {
            // Fall through to fallback
        }
    }

    // Fallback: await the URL then use execCommand
    if (!success) {
        const url = await urlPromise;
        success = await copyText(url);
    }

    const url = await urlPromise;
    if (url.length > 8000) {
        alert(`Warning: This share link is ${url.length} characters long. Older browsers, proxies, or chat apps max out at 2,000-8,000 bytes and might truncate it, breaking the link.`);
    }

    if (success) {
        showShareSuccess();
    } else {
        alert("Failed to copy link to clipboard. Please copy manually:\n\n" + url);
    }
});

function persistModeState() {
    try {
        localStorage.setItem(MODE_STORAGE_KEY, playgroundMode);
        localStorage.setItem(TEMPLATE_STORAGE_KEY, activeTemplateId);
    } catch { /* ignore */ }
}

function updateModeNotice() {
    const el = document.getElementById("pg-feature-notice-text");
    if (!el) return;
    el.textContent = playgroundMode === "app"
        ? "App mode: SSR + client hydrate. Not all framework features are supported in the playground."
        : "Toggle App for client-side rendering. Not all framework features are supported in the playground yet.";
}

function refreshTemplateSelect() {
    const select = document.getElementById("pg-template-select") as HTMLSelectElement | null;
    if (!select) return;
    const options = templatesForMode(playgroundMode);
    select.innerHTML = "";
    for (const t of options) {
        const opt = document.createElement("option");
        opt.value = t.id;
        opt.textContent = t.label;
        select.appendChild(opt);
    }
    if (!options.some((t) => t.id === activeTemplateId)) {
        activeTemplateId = defaultTemplateId(playgroundMode);
    }
    select.value = activeTemplateId;
}

function loadFilesFromMap(fileMap: { [filename: string]: string }) {
    fileManager.getAllFiles().forEach((f) => fileManager.removeFile(f.name));
    Object.entries(fileMap).forEach(([name, content]) => fileManager.addFile(name, content));
    const newFiles = fileManager.getAllFiles().map((f) => ({
        name: f.name,
        state: createEditorState(f.name, f.content),
        hidden: isHiddenPlaygroundFile(f.name),
        locked: isLockedPlaygroundFile(f.name),
    }));
    files.length = 0;
    files.push(...newFiles);
    activeFileIndex = -1;
    let initialFileIndex = files.findIndex((f) => !f.hidden && (f.name.endsWith("page.zx") || f.name === "Playground.zx"));
    if (initialFileIndex < 0) initialFileIndex = files.findIndex((f) => !f.hidden);
    if (initialFileIndex < 0) initialFileIndex = 0;
    updateTabs();
    void switchFile(initialFileIndex);
    transpileCache.clear();
    buildCache.clear();
    resetPreviewNavigation();
    resetPreviewPlaceholder();
}

function loadTemplateFiles(templateId = activeTemplateId) {
    const template = getTemplate(templateId) ?? getTemplate(defaultTemplateId(playgroundMode))!;
    activeTemplateId = template.id;
    playgroundMode = template.mode;
    persistModeState();
    loadFilesFromMap(template.files);
}

function ensureBaselinePlaygroundFiles(filesDecoded: { [filename: string]: string }): { [filename: string]: string } {
    const normalized: { [filename: string]: string } = { ...filesDecoded };
    const looksLikeApp = Boolean(normalized["app/pages/page.zx"] || normalized["app/main.zig"]);

    if (looksLikeApp) {
        playgroundMode = "app";
        activeTemplateId = defaultTemplateId("app");
        const fallback = getTemplate(activeTemplateId)!.files;
        for (const [name, content] of Object.entries(fallback)) {
            if (!normalized[name]) normalized[name] = content;
        }
        return normalized;
    }

    playgroundMode = "playground";
    if (!normalized["Playground.zx"]) {
        const firstZx = Object.keys(normalized).find((name) => name.endsWith(".zx"));
        if (firstZx) {
            normalized["Playground.zx"] = normalized[firstZx];
            if (firstZx !== "Playground.zx") delete normalized[firstZx];
        }
    }
    const fallback = getTemplate(defaultTemplateId("playground"))!.files;
    for (const [name, content] of Object.entries(fallback)) {
        if (!normalized[name]) normalized[name] = content;
    }
    activeTemplateId = defaultTemplateId("playground");
    return normalized;
}

function isLockedPlaygroundFile(name: string): boolean {
    return playgroundMode === "app"
        ? name === "app/main.zig"
        : name === "Playground.zx" || name === "main.zig";
}

function isHiddenPlaygroundFile(name: string): boolean {
    if (playgroundMode === "app") {
        return isGeneratedPlaygroundPath(name) || name === "app/main.zig";
    }
    return name.endsWith(".zig");
}

function clearSharedDataHashFromUrl() {
    if (!location.hash.startsWith("#data=")) return;
    history.replaceState(null, "", `${location.pathname}${location.search}`);
}

function setupFeatureNotice() {
    const notice = document.getElementById("pg-feature-notice");
    if (!notice) return;

    let dismissed = false;
    try {
        dismissed = localStorage.getItem(PLAYGROUND_NOTICE_STORAGE_KEY) === "1";
    } catch {
        dismissed = false;
    }

    if (dismissed) {
        notice.classList.add("is-hidden");
        return;
    }

    // Show after initial layout is stable to avoid immediate content jump on load.
    window.setTimeout(() => {
        notice.classList.remove("is-hidden");
    }, 450);

    const closeBtn = document.getElementById("pg-feature-notice-close");
    closeBtn?.addEventListener("click", () => {
        notice.classList.add("is-hidden");
        try {
            localStorage.setItem(PLAYGROUND_NOTICE_STORAGE_KEY, "1");
        } catch {
            // Ignore storage failures (private mode/quota).
        }
    });
}


window.addEventListener("DOMContentLoaded", async () => {
    setupFeatureNotice();
    setupModeControls();
    await Promise.race([
        client.initializing,
        new Promise<void>((resolve) => setTimeout(resolve, 2500)),
    ]);
    let code = null;
    if (location.hash.startsWith("#data=")) {
        code = location.hash.slice(6);
    }
    if (code) {
        const filesDecoded = await decodeFilesFromQuery(code);
        if (filesDecoded) {
            const filesWithDefaults = ensureBaselinePlaygroundFiles(filesDecoded);
            loadFilesFromMap(filesWithDefaults);
            clearSharedDataHashFromUrl();
            syncModeUi();
            enableChromeButtons();
            return;
        }
    }
    loadTemplateFiles();
    syncModeUi();
    enableChromeButtons();
});

function enableChromeButtons() {
    document.getElementById("pg-run-btn")?.removeAttribute("disabled");
    document.getElementById("pg-share-btn")?.removeAttribute("disabled");
    document.getElementById("pg-format-btn")?.removeAttribute("disabled");
}

function syncModeUi() {
    const appToggle = document.getElementById("pg-app-toggle") as HTMLButtonElement | null;
    if (appToggle) {
        const on = playgroundMode === "app";
        appToggle.classList.toggle("is-active", on);
        appToggle.setAttribute("aria-pressed", on ? "true" : "false");
    }
    refreshTemplateSelect();
    updateModeNotice();
    syncBrowserToolbar();
}

const PREVIEW_HOST = "playground.local";
const PREVIEW_ORIGIN = `https://${PREVIEW_HOST}`;

type PreviewLocation = { pathname: string; search: string; url: string; display: string };

let previewLocation: PreviewLocation = normalizePreviewLocation("/");
let previewHistory: PreviewLocation[] = [previewLocation];
let previewHistoryIndex = 0;
let lastAppArtifacts: PlaygroundBuildArtifacts | null = null;
let previewNavigating = false;

function normalizePreviewLocation(input: string): PreviewLocation {
    let raw = input.trim();
    if (!raw) raw = "/";

    try {
        if (/^https?:\/\//i.test(raw)) {
            const u = new URL(raw);
            const pathname = u.pathname || "/";
            const search = u.search || "";
            return {
                pathname,
                search,
                url: `${PREVIEW_ORIGIN}${pathname}${search}`,
                display: `${PREVIEW_HOST}${pathname}${search}`,
            };
        }
    } catch { /* fall through */ }

    raw = raw.replace(/^(https?:\/\/)?(playground\.local|localhost(?::\d+)?)/i, "");
    if (!raw.startsWith("/")) raw = `/${raw}`;
    const q = raw.indexOf("?");
    const pathname = (q >= 0 ? raw.slice(0, q) : raw) || "/";
    const search = q >= 0 ? raw.slice(q) : "";
    return {
        pathname,
        search,
        url: `${PREVIEW_ORIGIN}${pathname}${search}`,
        display: `${PREVIEW_HOST}${pathname}${search}`,
    };
}

function setPreviewLocation(loc: PreviewLocation, mode: "replace" | "push" | "none" = "replace") {
    previewLocation = loc;
    if (mode === "push") {
        previewHistory = previewHistory.slice(0, previewHistoryIndex + 1);
        const prev = previewHistory[previewHistory.length - 1];
        if (!prev || prev.url !== loc.url) {
            previewHistory.push(loc);
            previewHistoryIndex = previewHistory.length - 1;
        }
    } else if (mode === "replace") {
        previewHistory = [loc];
        previewHistoryIndex = 0;
    }
    const input = document.getElementById("pg-browser-url-input") as HTMLInputElement | null;
    if (input && document.activeElement !== input) input.value = loc.display;
    updateBrowserNavButtons();
}

function resetPreviewNavigation() {
    lastAppArtifacts = null;
    setPreviewLocation(normalizePreviewLocation("/"), "replace");
}

function updateBrowserNavButtons() {
    const back = document.getElementById("pg-browser-back") as HTMLButtonElement | null;
    const forward = document.getElementById("pg-browser-forward") as HTMLButtonElement | null;
    if (back) back.disabled = previewHistoryIndex <= 0;
    if (forward) forward.disabled = previewHistoryIndex >= previewHistory.length - 1;
}

function syncBrowserToolbar() {
    const toolbar = document.getElementById("pg-browser-toolbar");
    if (!toolbar) return;
    toolbar.classList.toggle("is-hidden", playgroundMode !== "app");
    const input = document.getElementById("pg-browser-url-input") as HTMLInputElement | null;
    if (input && document.activeElement !== input) input.value = previewLocation.display;
    updateBrowserNavButtons();
}

function setupBrowserToolbar() {
    const form = document.getElementById("pg-browser-url-form") as HTMLFormElement | null;
    form?.addEventListener("submit", (ev) => {
        ev.preventDefault();
        const input = document.getElementById("pg-browser-url-input") as HTMLInputElement | null;
        void navigatePreview(input?.value ?? "/", { history: "push" });
    });

    document.getElementById("pg-browser-refresh")?.addEventListener("click", () => {
        void navigatePreview(previewLocation.display, { history: "none" });
    });
    document.getElementById("pg-browser-back")?.addEventListener("click", () => {
        if (previewHistoryIndex <= 0) return;
        previewHistoryIndex -= 1;
        const loc = previewHistory[previewHistoryIndex]!;
        void navigatePreview(loc.display, { history: "none", location: loc });
    });
    document.getElementById("pg-browser-forward")?.addEventListener("click", () => {
        if (previewHistoryIndex >= previewHistory.length - 1) return;
        previewHistoryIndex += 1;
        const loc = previewHistory[previewHistoryIndex]!;
        void navigatePreview(loc.display, { history: "none", location: loc });
    });

    window.addEventListener("message", (ev) => {
        const data = ev.data;
        if (!data || typeof data !== "object") return;
        if (data.type === "pg-navigate" && typeof data.href === "string") {
            void navigatePreview(data.href, { history: "push" });
        }
    });
}

async function navigatePreview(
    input: string,
    opts: { history?: "push" | "replace" | "none"; location?: PreviewLocation } = {},
) {
    if (playgroundMode !== "app") return;
    if (!lastAppArtifacts) {
        appendTerminalLine("Run the app first, then use the URL bar to navigate.", "pg-terminal-error");
        setTerminalCollapsed(false);
        revealOutputWindow();
        return;
    }
    if (previewNavigating) return;

    const loc = opts.location ?? normalizePreviewLocation(input);
    const historyMode = opts.history ?? "push";
    if (historyMode === "push") setPreviewLocation(loc, "push");
    else if (historyMode === "replace") setPreviewLocation(loc, "replace");
    else {
        previewLocation = loc;
        const urlInput = document.getElementById("pg-browser-url-input") as HTMLInputElement | null;
        if (urlInput && document.activeElement !== urlInput) urlInput.value = loc.display;
        updateBrowserNavButtons();
    }

    previewNavigating = true;
    setRunButtonLoading(true);
    try {
        await runAppArtifacts(lastAppArtifacts, loc);
    } finally {
        previewNavigating = false;
        setRunButtonLoading(false);
    }
}

function setupModeControls() {
    setupBrowserToolbar();
    document.getElementById("pg-app-toggle")?.addEventListener("click", () => {
        const next: PlaygroundMode = playgroundMode === "app" ? "playground" : "app";
        playgroundMode = next;
        activeTemplateId = defaultTemplateId(next);
        persistModeState();
        loadTemplateFiles(activeTemplateId);
        syncModeUi();
    });
    document.getElementById("pg-template-select")?.addEventListener("change", (ev) => {
        const id = (ev.target as HTMLSelectElement).value;
        const template = getTemplate(id);
        if (!template || template.mode !== playgroundMode) return;
        activeTemplateId = id;
        persistModeState();
        loadTemplateFiles(id);
        syncModeUi();
    });
}

// Client connects on construction; file loading is handled in DOMContentLoaded.

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


let zigWorker = new Worker(`/assets/playground/workers/zig.js?v=${Date.now()}`);
let zxWorker = new Worker(`/assets/playground/workers/zx.js?v=${Date.now()}`);

function setRunButtonLoading(loading: boolean) {
    const btn = document.getElementById("pg-run-btn")!;
    if (loading) {
        btn.classList.add("pg-nav-btn--loading");
        btn.setAttribute("disabled", "true");
        btn.innerHTML = '<span class="pg-spinner"></span>';
    } else {
        btn.classList.remove("pg-nav-btn--loading");
        btn.removeAttribute("disabled");
        btn.innerHTML = 'Run';
    }
}

/** Restore the preview pane to the idle "Press Run" state. */
function resetPreviewPlaceholder() {
    const viewport = document.getElementById("pg-browser-viewport")!;
    while (viewport.firstChild) viewport.removeChild(viewport.firstChild);
    const placeholder = document.createElement("div");
    placeholder.className = "pg-browser-placeholder";
    const icon = document.createElement("div");
    icon.className = "pg-browser-placeholder-icon";
    icon.textContent = "";
    placeholder.appendChild(icon);
    placeholder.appendChild(document.createTextNode("Press Run to see preview"));
    viewport.appendChild(placeholder);
}

/** Update the preview pane's in-progress placeholder to reflect the current pipeline step. */
function updatePreviewStatus(emoji: string, label: string, stepId: string) {
    const iconEl = document.getElementById("pg-preview-step-icon");
    const textEl = document.getElementById("pg-preview-step-label");
    if (iconEl) {
        iconEl.textContent = emoji;
        iconEl.dataset.step = stepId;
    }
    if (textEl) textEl.textContent = label;
}

// Content hash (fast djb2 variant)
function hashFiles(map: { [name: string]: string }): string {
    const s = JSON.stringify(Object.entries(map).sort(([a], [b]) => a.localeCompare(b)));
    let h = 5381;
    for (let i = 0; i < s.length; i++) h = Math.imul(h, 33) ^ s.charCodeAt(i);
    return (h >>> 0).toString(36);
}

// In-memory LRU caches (max 8 entries each)
const MAX_CACHE = 8;
function cachePut<V>(cache: Map<string, V>, key: string, value: V) {
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value!);
    cache.set(key, value);
}

interface CacheEntry<V> {
    value: V;
    duration: number;
    isPrefetch: boolean;
}

const transpileCache = new Map<string, CacheEntry<{ [name: string]: string }>>();
const buildCache = new Map<string, CacheEntry<PlaygroundBuildArtifacts>>();

function stubFiles(): { [name: string]: string } {
    return {
        "stubs/zx_module_options_server.zig": stubZxOptsServer,
        "stubs/zx_module_options_client.zig": stubZxOptsClient,
        "stubs/zx_info.zig": stubZxInfo,
        "stubs/app_opts.zig": stubAppOpts,
        "stubs/manifest.zon": stubManifest,
        "stubs/build_injections.zon": stubBuildInjections,
    };
}

function transpileAppAsync(filesMap: { [name: string]: string }): Promise<{ [filename: string]: string }> {
    return new Promise((resolve, reject) => {
        function handler(ev: MessageEvent) {
            const d = ev.data;
            if (d?.failed) {
                zxWorker.removeEventListener("message", handler);
                reject({ stderr: d.stderr || "Transpile failed" });
            } else if (d?.transpiled) {
                zxWorker.removeEventListener("message", handler);
                resolve(d.transpiled);
            }
        }
        zxWorker.addEventListener("message", handler);
        zxWorker.postMessage({
            files: { ...filesMap, ...stubFiles() },
            path: "app",
            buildInjections: "stubs/build_injections.zon",
        });
    });
}

function transpileZxFileAsync(zxName: string, zxContent: string): Promise<{ [filename: string]: string }> {
    return new Promise((resolve, reject) => {
        function handler(ev: MessageEvent) {
            const d = ev.data;
            if (d && d.failed) {
                zxWorker.removeEventListener('message', handler);
                reject({ stderr: d.stderr || 'Transpile failed' });
            } else if (d && d.stdout) {
                zxWorker.removeEventListener('message', handler);
                resolve({ [zxName.replace(/\.zx$/, '.zig')]: d.stdout });
            }
        }
        zxWorker.addEventListener('message', handler);
        zxWorker.postMessage({ filename: zxName, content: zxContent });
    });
}

function formatZxFileAsync(zxName: string, zxContent: string): Promise<string> {
    return new Promise((resolve, reject) => {
        function handler(ev: MessageEvent) {
            const d = ev.data;
            if (d && d.failed) {
                zxWorker.removeEventListener("message", handler);
                reject({ stderr: d.stderr || "Format failed" });
            } else if (d && typeof d.stdout === "string") {
                zxWorker.removeEventListener("message", handler);
                resolve(d.stdout);
            }
        }
        zxWorker.addEventListener("message", handler);
        zxWorker.postMessage({ filename: zxName, content: zxContent, subcommand: "fmt" });
    });
}

function setFormatButtonLoading(loading: boolean) {
    const btn = document.getElementById("pg-format-btn") as HTMLButtonElement | null;
    if (!btn) return;
    if (loading) {
        btn.classList.add("pg-editor-status-btn--loading");
        btn.setAttribute("disabled", "true");
        btn.setAttribute("aria-busy", "true");
        btn.title = "Formatting…";
    } else {
        btn.classList.remove("pg-editor-status-btn--loading");
        btn.removeAttribute("disabled");
        btn.removeAttribute("aria-busy");
        btn.title = "Format file (Shift+Alt+F)";
    }
}

function applyFormattedContent(formatted: string) {
    if (!editorView || activeFileIndex < 0) return;
    const file = files[activeFileIndex];
    const current = editorView.state.doc.toString();
    if (current === formatted) return;

    const selection = editorView.state.selection.main;
    const nextPos = Math.min(selection.head, formatted.length);
    editorView.dispatch({
        changes: { from: 0, to: current.length, insert: formatted },
        selection: { anchor: nextPos, head: nextPos },
    });
    file.state = editorView.state;
    fileManager.updateContent(file.name, formatted);
    transpileCache.clear();
}

async function formatActiveFile(): Promise<boolean> {
    if (formatting || activeFileIndex < 0 || !editorView) return false;

    const file = files[activeFileIndex];
    const name = file.name;
    const content = editorView.state.doc.toString();

    if (name.endsWith(".zx") || name.endsWith(".mdzx")) {
        formatting = true;
        setFormatButtonLoading(true);
        try {
            const formatted = await formatZxFileAsync(name, content);
            applyFormattedContent(formatted);
            appendTerminalLine(`Formatted ${name}`, "pg-terminal-success");
            setTerminalCollapsed(false);
            revealOutputWindow();
            return true;
        } catch (err: any) {
            const message = err?.stderr || `Failed to format ${name}`;
            appendTerminalLine(message, "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            return false;
        } finally {
            formatting = false;
            setFormatButtonLoading(false);
        }
    }

    if (name.endsWith(".zig") || name.endsWith(".zon")) {
        // Prefer ZLS formatting when the language server is available.
        return formatDocument(editorView);
    }

    appendTerminalLine(`No formatter for ${name}`, "pg-terminal-info");
    return false;
}

document.getElementById("pg-format-btn")?.addEventListener("click", () => {
    void formatActiveFile();
});

// Promisified build
let build_start_time = performance.now();
function buildFilesAsync(filesMap: { [name: string]: string }): Promise<PlaygroundBuildArtifacts | Uint8Array> {
    return new Promise((resolve, reject) => {
        let stderrAcc = "";
        function handler(ev: MessageEvent) {
            const d = ev.data;
            if (d.stderr) {
                stderrAcc += (stderrAcc ? "\n" : "") + d.stderr;
            }
            if (d.stderr && !d.compiled && !d.failed) return;
            if (d.failed) {
                zigWorker.removeEventListener("message", handler);
                reject({ type: "failed", stderr: d.stderr || stderrAcc });
            } else if (d.compiled) {
                zigWorker.removeEventListener("message", handler);
                console.info("Build finished in", (performance.now() - build_start_time).toFixed(2), "ms");
                resolve(d.compiled as PlaygroundBuildArtifacts | Uint8Array);
            }
        }
        zigWorker.addEventListener("message", handler);
        build_start_time = performance.now();
        const payload = playgroundMode === "app"
            ? { files: { ...filesMap, ...stubFiles() }, mode: "app" }
            : { files: filesMap, mode: "playground" };
        zigWorker.postMessage(payload);
    });
}

let lastClientWasmUrl: string | null = null;

function showHtmlPreview(html: string) {
    const vp = document.getElementById("pg-browser-viewport")!;
    vp.innerHTML = "";
    const iframe = document.createElement("iframe");
    iframe.style.cssText = "width:100%;height:100%;border:none;background-color:white";
    vp.appendChild(iframe);
    iframe.contentDocument?.open();
    iframe.contentDocument?.write(html);
    iframe.contentDocument?.close();
}

function showHydratedPreview(html: string, clientWasm: Uint8Array) {
    if (lastClientWasmUrl) URL.revokeObjectURL(lastClientWasmUrl);
    lastClientWasmUrl = URL.createObjectURL(new Blob([clientWasm], { type: "application/wasm" }));

    const baseHref = `${location.origin}/`;
    let doc = html;
    if (!/__PLAYGROUND_CLIENT_WASM__|#__\$wasmlink|id=["']__\$wasmlink["']/.test(doc)) {
        doc = doc.replace(
            /<\/head>/i,
            `<link id="__$wasmlink" rel="preload" as="fetch" href="${CLIENT_WASM_PLACEHOLDER}" crossorigin></link>\n` +
            `<script defer src="/assets/playground/init.js"></script>\n</head>`,
        );
    }
    doc = doc.split(CLIENT_WASM_PLACEHOLDER).join(lastClientWasmUrl);
    if (/<base\s/i.test(doc)) {
        doc = doc.replace(/<base\b[^>]*>/i, `<base href="${baseHref}">`);
    } else {
        doc = doc.replace(/<head([^>]*)>/i, `<head$1><base href="${baseHref}">`);
    }

    const previewBridge = `<script>
(function(){
  function report(err) {
    var msg = (err && err.stack) ? String(err.stack) : String(err);
    if (window.__pgHydrateReported === msg) return;
    window.__pgHydrateReported = msg;
    console.error('[playground hydrate]', msg);
    try { parent.postMessage({ type: 'pg-hydrate-error', message: msg }, '*'); } catch (_) {}
  }
  window.addEventListener('error', function(e) { report(e.error || e.message); });
  window.addEventListener('unhandledrejection', function(e) { report(e.reason); });
  var origErr = console.error.bind(console);
  console.error = function() {
    origErr.apply(console, arguments);
    try {
      var a = arguments[0];
      if (a && (a instanceof Error || (typeof a === 'object' && a.message))) report(a);
    } catch (_) {}
  };
  if (typeof WebAssembly.promising === 'function') {
    var origP = WebAssembly.promising.bind(WebAssembly);
    WebAssembly.promising = function(fn) {
      var wrapped = origP(fn);
      return function() {
        var ret = wrapped.apply(this, arguments);
        if (ret && typeof ret.then === 'function') {
          return ret.then(undefined, function(err) { report(err); throw err; });
        }
        return ret;
      };
    };
  }

  var SITE_ORIGIN = ${JSON.stringify(location.origin)};
  var PREVIEW_HOST = ${JSON.stringify(PREVIEW_HOST)};

  function previewPathForAnchor(a) {
    var raw = a.getAttribute('href') || '';
    if (!raw || raw.charAt(0) === '#' || /^(javascript:|mailto:|tel:)/i.test(raw)) return null;
    try {
      var resolved = new URL(a.href);
      if (resolved.origin === SITE_ORIGIN || resolved.hostname === PREVIEW_HOST) {
        return resolved.pathname + resolved.search;
      }
    } catch (_) {}
    if (raw.charAt(0) === '/') return raw.split('#')[0];
    return null;
  }

  function onNavClick(e) {
    if (e.defaultPrevented) return;
    if (e.button != null && e.button !== 0) return;
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    var t = e.target;
    if (!t || !t.closest) return;
    var a = t.closest('a[href]');
    if (!a || a.target === '_blank' || a.hasAttribute('download')) return;
    var path = previewPathForAnchor(a);
    if (path == null) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.stopImmediatePropagation) e.stopImmediatePropagation();
    try { parent.postMessage({ type: 'pg-navigate', href: path }, '*'); } catch (_) {}
  }
  document.addEventListener('click', onNavClick, true);
})();
</script>`;

    if (/<\/head>/i.test(doc)) {
        doc = doc.replace(/<\/head>/i, previewBridge + "\n</head>");
    } else {
        doc = previewBridge + doc;
    }

    const vp = document.getElementById("pg-browser-viewport")!;
    vp.innerHTML = "";
    const iframe = document.createElement("iframe");
    iframe.style.cssText = "width:100%;height:100%;border:none;background-color:white";
    iframe.setAttribute("sandbox", "allow-scripts allow-same-origin allow-forms");
    vp.appendChild(iframe);
    iframe.srcdoc = doc;
}

function runCompiled(compiled: PlaygroundBuildArtifacts | Uint8Array) {
    appendStatusStep("run", "Running\u2026");
    updatePreviewStatus("", "Running\u2026", "run");

    if (compiled instanceof Uint8Array) {
        lastAppArtifacts = null;
        void runPlaygroundWasm(compiled);
        return;
    }

    lastAppArtifacts = compiled;
    const input = document.getElementById("pg-browser-url-input") as HTMLInputElement | null;
    const loc = normalizePreviewLocation(input?.value || previewLocation.display);
    setPreviewLocation(loc, "replace");
    void runAppArtifacts(compiled, loc);
}

function runPlaygroundWasm(compiled: Uint8Array): Promise<void> {
    return new Promise((resolve) => {
        const runnerWorker = new Worker(`/assets/playground/workers/runner.js?v=${Date.now()}`);
        runnerWorker.onerror = (ev) => {
            completeStatusStep("run", "error");
            appendTerminalLine(`runner worker error: ${ev.message}`, "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            setRunButtonLoading(false);
            resetPreviewPlaceholder();
            runnerWorker.terminate();
            resolve();
        };
        runnerWorker.onmessage = (rev: MessageEvent) => {
            if (rev.data?.stderr) appendTerminalLine(rev.data.stderr, "pg-terminal-error");
            if (rev.data?.failed) {
                completeStatusStep("run", "error");
                setTerminalCollapsed(false);
                revealOutputWindow();
                setRunButtonLoading(false);
                resetPreviewPlaceholder();
                runnerWorker.terminate();
                resolve();
                return;
            }
            if (rev.data?.preview != null) {
                showHtmlPreview(rev.data.preview);
                if (rev.data?.done) {
                    completeStatusStep("run", "done");
                    runnerWorker.terminate();
                    setRunButtonLoading(false);
                    resolve();
                }
                return;
            }
            if (rev.data?.done) {
                completeStatusStep("run", "done");
                runnerWorker.terminate();
                setRunButtonLoading(false);
                resolve();
            }
        };
        const copy = compiled.slice();
        runnerWorker.postMessage({ run: copy }, [copy.buffer]);
    });
}

function runAppArtifacts(compiled: PlaygroundBuildArtifacts, loc: PreviewLocation): Promise<void> {
    return new Promise((resolve) => {
        const runnerWorker = new Worker(`/assets/playground/workers/runner.js?v=${Date.now()}`);
        const clientWasm = compiled.clientWasm;
        const ssr = compiled.ssrWasm;

        runnerWorker.onerror = (ev) => {
            completeStatusStep("run", "error");
            appendTerminalLine(`runner worker error: ${ev.message}`, "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            setRunButtonLoading(false);
            resetPreviewPlaceholder();
            runnerWorker.terminate();
            resolve();
        };

        runnerWorker.onmessage = (rev: MessageEvent) => {
            if (rev.data?.stderr) appendTerminalLine(rev.data.stderr, "pg-terminal-error");
            if (rev.data?.failed) {
                completeStatusStep("run", "error");
                setTerminalCollapsed(false);
                revealOutputWindow();
                setRunButtonLoading(false);
                resetPreviewPlaceholder();
                runnerWorker.terminate();
                resolve();
                return;
            }
            if (rev.data?.preview != null) {
                if (clientWasm instanceof Uint8Array) {
                    showHydratedPreview(rev.data.preview, clientWasm);
                } else {
                    showHtmlPreview(rev.data.preview);
                }
                if (rev.data?.done) {
                    completeStatusStep("run", "done");
                    runnerWorker.terminate();
                    setRunButtonLoading(false);
                    resolve();
                }
                return;
            }
            if (rev.data?.done) {
                completeStatusStep("run", "done");
                runnerWorker.terminate();
                setRunButtonLoading(false);
                resolve();
            }
        };

        if (!(ssr instanceof Uint8Array) || ssr.byteLength < 8) {
            completeStatusStep("run", "error");
            appendTerminalLine("Invalid SSR wasm artifact", "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            setRunButtonLoading(false);
            resetPreviewPlaceholder();
            runnerWorker.terminate();
            resolve();
            return;
        }
        if (!(clientWasm instanceof Uint8Array) || clientWasm.byteLength < 8) {
            completeStatusStep("run", "error");
            appendTerminalLine("Invalid client wasm artifact", "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            setRunButtonLoading(false);
            resetPreviewPlaceholder();
            runnerWorker.terminate();
            resolve();
            return;
        }

        const ssrCopy = ssr.slice();
        runnerWorker.postMessage({
            run: {
                ssrWasm: ssrCopy,
                pathname: loc.pathname,
                search: loc.search,
                method: "GET",
                url: loc.url,
            },
        }, [ssrCopy.buffer]);
    });
}

function getCurrentFilesMap(): { [filename: string]: string } {
    if (activeFileIndex !== -1 && editorView) {
        fileManager.updateContent(files[activeFileIndex].name, editorView.state.doc.toString());
    }
    const map: { [filename: string]: string } = {};
    fileManager.getAllFiles().forEach((f) => {
        if (playgroundMode === "app") {
            if (isGeneratedPlaygroundPath(f.name)) return;
        } else if (f.name.endsWith(".zig") && f.name !== "main.zig") {
            return;
        }
        map[f.name] = f.content;
    });
    if (playgroundMode === "app") {
        const appMain = getTemplate("app-counter")?.files["app/main.zig"];
        if (!map["app/main.zig"] && appMain) map["app/main.zig"] = appMain;
    } else {
        const pgMain = getTemplate("pg-hello")?.files["main.zig"];
        if (!map["main.zig"] && pgMain) map["main.zig"] = pgMain;
    }
    return map;
}

async function runTranspileAndBuild(visible: boolean): Promise<PlaygroundBuildArtifacts | Uint8Array | null> {
    let filesMap = getCurrentFilesMap();
    const zxEntries = Object.entries(filesMap).filter(([n]) => n.endsWith(".zx"));
    const zxHash = hashFiles(Object.fromEntries(zxEntries)) + `|${playgroundMode}`;
    let transpiledFiles: { [name: string]: string } = {};

    const emptyZxFiles = zxEntries.filter(([_, content]) => !content.trim());
    if (emptyZxFiles.length > 0) {
        if (visible) {
            completeStatusStep("transpile", "error");
            appendTerminalLine("One or more .zx files are empty. Please add code or remove the empty file(s).", "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            resetPreviewPlaceholder();
            setRunButtonLoading(false);
        }
        return null;
    }

    if (zxEntries.length > 0) {
        const hit = transpileCache.get(zxHash);
        if (hit) {
            transpiledFiles = hit.value;
            if (visible) {
                appendStatusStep("transpile", "Transpiling\u2026");
                if (hit.isPrefetch) {
                    completeStatusStep("transpile", "prefetched", hit.duration);
                    hit.isPrefetch = false;
                } else {
                    completeStatusStep("transpile", "cached");
                }
                updatePreviewStatus("", "Transpiling\u2026 (cached)", "transpile");
            }
        } else {
            if (visible) {
                appendStatusStep("transpile", "Transpiling\u2026");
                updatePreviewStatus("", "Transpiling\u2026", "transpile");
            }
            const start = performance.now();
            try {
                if (playgroundMode === "app") {
                    transpiledFiles = await transpileAppAsync(filesMap);
                } else {
                    for (const [name, content] of zxEntries) {
                        Object.assign(transpiledFiles, await transpileZxFileAsync(name, content));
                    }
                }
                const duration = performance.now() - start;
                cachePut(transpileCache, zxHash, { value: { ...transpiledFiles }, duration, isPrefetch: !visible });
                if (visible) completeStatusStep("transpile", "done");
            } catch (err: any) {
                if (visible) {
                    completeStatusStep("transpile", "error");
                    appendTerminalLine(err.stderr || "Transpile failed", "pg-terminal-error");
                    setTerminalCollapsed(false);
                    revealOutputWindow();
                    resetPreviewPlaceholder();
                    setRunButtonLoading(false);
                }
                return null;
            }
        }
    } else if (visible) {
        updatePreviewStatus("", "Building\u2026", "build");
    }

    for (const [zigName, zigContent] of Object.entries(transpiledFiles)) {
        if (playgroundMode === "app" && zigName.endsWith(".zon")) {
            filesMap[zigName === "app/app.zon" ? "stubs/manifest.zon" : zigName] = zigContent;
            continue;
        }
        filesMap[zigName] = zigContent;
        if (fileManager.hasFile(zigName)) {
            fileManager.updateContent(zigName, zigContent);
            const f = files.find((x) => x.name === zigName);
            if (f) { f.state = createEditorState(zigName, zigContent); f.hidden = true; }
        } else {
            fileManager.addFile(zigName, zigContent);
            files.push({ name: zigName, state: createEditorState(zigName, zigContent), hidden: true });
        }
    }

    if (playgroundMode === "app" && !filesMap["app/app.zig"]) {
        if (visible) {
            completeStatusStep("build", "error");
            appendTerminalLine("Transpile did not produce app/app.zig", "pg-terminal-error");
            setTerminalCollapsed(false);
            revealOutputWindow();
            resetPreviewPlaceholder();
            setRunButtonLoading(false);
        }
        return null;
    }

    const buildKey = hashFiles(filesMap) + `|${playgroundMode}|v5`;
    const buildHit = buildCache.get(buildKey);
    if (buildHit) {
        if (visible) {
            appendStatusStep("build", "Building\u2026");
            if (buildHit.isPrefetch) {
                completeStatusStep("build", "prefetched", buildHit.duration);
                buildHit.isPrefetch = false;
            } else {
                completeStatusStep("build", "cached");
            }
            updatePreviewStatus("", "Building\u2026 (cached)", "build");
        }
        return buildHit.value as PlaygroundBuildArtifacts | Uint8Array;
    }

    if (visible) {
        appendStatusStep("build", "Building\u2026");
        updatePreviewStatus("", "Building\u2026", "build");
    }
    const bStart = performance.now();
    try {
        const compiled = await buildFilesAsync(filesMap);
        const bDuration = performance.now() - bStart;
        cachePut(buildCache, buildKey, { value: compiled, duration: bDuration, isPrefetch: !visible });
        if (visible) completeStatusStep("build", "done");
        return compiled;
    } catch (err: any) {
        if (visible) {
            completeStatusStep("build", "error");
            if (err.stderr) {
                const lines = err.stderr.split("\n").filter((l: string) => l.length > 0);
                for (const l of lines) appendTerminalLine(l, "pg-terminal-error");
            } else {
                appendTerminalLine("Compilation failed.", "pg-terminal-error");
            }
            setTerminalCollapsed(false);
            revealOutputWindow();
            resetPreviewPlaceholder();
            setRunButtonLoading(false);
        }
        return null;
    }
}

let prefetchPromise: Promise<void> | null = null;
const outputsRun = document.getElementById('pg-run-btn')! as HTMLButtonElement;
outputsRun.addEventListener('click', async () => {
    setRunButtonLoading(true);
    clearTerminal();

    // Animated "building" preview placeholder
    const viewport = document.getElementById('pg-browser-viewport')!;
    while (viewport.firstChild) viewport.removeChild(viewport.firstChild);
    const ph = document.createElement('div');
    ph.className = 'pg-browser-placeholder pg-browser-placeholder--building';
    const phIcon = document.createElement('div');
    phIcon.className = 'pg-browser-placeholder-icon';
    phIcon.id = 'pg-preview-step-icon';
    phIcon.dataset.step = 'transpile';
    phIcon.textContent = '';
    ph.appendChild(phIcon);
    const phLabel = document.createElement('span');
    phLabel.id = 'pg-preview-step-label';
    phLabel.textContent = 'Transpiling\u2026';
    ph.appendChild(phLabel);
    viewport.appendChild(ph);

    // If a background prefetch is in flight, wait - result will be in cache
    if (prefetchPromise) await prefetchPromise;

    const compiled = await runTranspileAndBuild(true);
    if (compiled == null) return;
    runCompiled(compiled);
});

// Background building on editor mouseleave
document.getElementById('pg-editor')?.addEventListener('mouseleave', () => {
    if (prefetchPromise) return; // already prefetching

    const snap = getCurrentFilesMap();
    const zxEntries = Object.entries(snap).filter(([n]) => n.endsWith('.zx'));
    const zxHash = hashFiles(Object.fromEntries(zxEntries)) + `|${playgroundMode}`;
    const transpiled = transpileCache.get(zxHash) ?? (zxEntries.length === 0 ? { value: {} } : null);
    if (transpiled !== null && buildCache.has(hashFiles({ ...snap, ...transpiled.value }) + `|${playgroundMode}|v5`)) return;

    prefetchPromise = (async () => {
        try { await runTranspileAndBuild(false); } catch { /* silent */ }
    })().finally(() => { prefetchPromise = null; });
});
