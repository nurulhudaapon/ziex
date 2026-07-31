export type PlaygroundMode = "playground" | "app";

export type TemplateDef = {
    id: string;
    label: string;
    mode: PlaygroundMode;
    files: Record<string, string>;
};

type ApiFile = { path: string; content: string };

type ApiTemplate = {
    name: string;
    description: string;
    kind: "app" | "none_app";
    files: ApiFile[];
};

type ApiResponse = {
    shared_files: {
        none_app: ApiFile[];
        app: ApiFile[];
    };
    templates: ApiTemplate[];
};

const TEMPLATES_URL = "/playground/templates.json";

let templates: TemplateDef[] = [];
let loadPromise: Promise<TemplateDef[]> | null = null;

function filesToRecord(files: ApiFile[], into: Record<string, string> = {}): Record<string, string> {
    for (const f of files) into[f.path] = f.content;
    return into;
}

function toTemplateDef(t: ApiTemplate, shared: ApiResponse["shared_files"]): TemplateDef {
    const files: Record<string, string> = {};
    filesToRecord(t.kind === "app" ? shared.app : shared.none_app, files);
    filesToRecord(t.files, files);
    return {
        id: t.name,
        label: t.description || t.name,
        mode: t.kind === "app" ? "app" : "playground",
        files,
    };
}

export function loadTemplates(): Promise<TemplateDef[]> {
    if (loadPromise) return loadPromise;
    loadPromise = (async () => {
        const res = await fetch(TEMPLATES_URL);
        if (!res.ok) throw new Error(`Failed to load templates (${res.status})`);
        const data = (await res.json()) as ApiResponse;
        templates = data.templates.map((t) => toTemplateDef(t, data.shared_files));
        return templates;
    })().catch((err) => {
        loadPromise = null;
        throw err;
    });
    return loadPromise;
}

export function allTemplates(): TemplateDef[] {
    return templates;
}

export function templatesForMode(mode: PlaygroundMode): TemplateDef[] {
    return templates.filter((t) => t.mode === mode);
}

export function defaultTemplateId(mode: PlaygroundMode): string {
    const forMode = templatesForMode(mode);
    if (forMode.length > 0) return forMode[0].id;
    return mode === "playground" ? "playground" : "app";
}

export function getTemplate(id: string): TemplateDef | undefined {
    return templates.find((t) => t.id === id);
}
