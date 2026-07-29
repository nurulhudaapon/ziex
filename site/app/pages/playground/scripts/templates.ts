export type PlaygroundMode = "playground" | "app";

export type TemplateDef = {
    id: string;
    label: string;
    mode: PlaygroundMode;
    files: Record<string, string>;
};

// @ts-ignore
import playgroundMain from "./template/main.zig" with { type: "text" };
// @ts-ignore
import playgroundZx from "./template/Playground.zx" with { type: "text" };
// @ts-ignore
import playgroundCss from "./template/style.css" with { type: "text" };

// @ts-ignore
import appMain from "./template/app/main.zig" with { type: "text" };
// @ts-ignore
import appLayout from "./template/app/pages/layout.zx" with { type: "text" };
// @ts-ignore
import appPage from "./template/app/pages/page.zx" with { type: "text" };
// @ts-ignore
import appAboutPage from "./template/app/pages/about/page.zx" with { type: "text" };
// @ts-ignore
import appApiRoute from "./template/app/routes/api/route.zig" with { type: "text" };

// @ts-ignore
import eventsLayout from "./template/app-events/pages/layout.zx" with { type: "text" };
// @ts-ignore
import eventsPage from "./template/app-events/pages/page.zx" with { type: "text" };

export const TEMPLATES: TemplateDef[] = [
    {
        id: "pg-hello",
        label: "Hello",
        mode: "playground",
        files: {
            "Playground.zx": playgroundZx,
            "style.css": playgroundCss,
            "main.zig": playgroundMain,
        },
    },
    {
        id: "app-counter",
        label: "Counter",
        mode: "app",
        files: {
            "app/main.zig": appMain,
            "app/pages/layout.zx": appLayout,
            "app/pages/page.zx": appPage,
            "app/pages/about/page.zx": appAboutPage,
            "app/routes/api/route.zig": appApiRoute,
        },
    },
    {
        id: "app-events",
        label: "Events",
        mode: "app",
        files: {
            "app/main.zig": appMain,
            "app/pages/layout.zx": eventsLayout,
            "app/pages/page.zx": eventsPage,
        },
    },
];

export function templatesForMode(mode: PlaygroundMode): TemplateDef[] {
    return TEMPLATES.filter((t) => t.mode === mode);
}

export function defaultTemplateId(mode: PlaygroundMode): string {
    return mode === "playground" ? "pg-hello" : "app-counter";
}

export function getTemplate(id: string): TemplateDef | undefined {
    return TEMPLATES.find((t) => t.id === id);
}
