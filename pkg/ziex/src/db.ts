export type D1Value =
    | null
    | string
    | number
    | boolean
    | ArrayBuffer
    | ArrayBufferView;

export interface D1ExecResult {
    meta?: {
        changes?: number;
        last_row_id?: number;
    };
}

export interface D1PreparedStatement {
    bind(...values: D1Value[]): D1PreparedStatement;
    first<T = Record<string, unknown>>(): Promise<T | null>;
    all<T = Record<string, unknown>>(): Promise<{ results?: T[] }>;
    raw(options?: { columnNames?: boolean }): Promise<unknown[][]>;
    run(): Promise<D1ExecResult>;
}

export interface D1Database {
    prepare(query: string): D1PreparedStatement;
}

type JsonBinding =
    | { kind: "none" }
    | { kind: "positional"; values: JsonValue[] }
    | { kind: "named"; values: { name: string; value: JsonValue }[] };

type JsonValue =
    | { kind: "null" }
    | { kind: "integer"; integer: number }
    | { kind: "float"; float: number }
    | { kind: "text"; text: string }
    | { kind: "blob"; blob: string }
    | { kind: "boolean"; boolean: boolean };

type WireValue =
    | { kind: "null" }
    | { kind: "integer"; integer: number }
    | { kind: "float"; float: number }
    | { kind: "text"; text: string }
    | { kind: "blob"; blob: string }
    | { kind: "boolean"; boolean: boolean };

type WireField = { name: string; value: WireValue };
type WireRow = { fields: WireField[] };

function decodeBlob(base64: string): Uint8Array {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
}

function toD1Value(value: JsonValue): D1Value {
    switch (value.kind) {
        case "null": return null;
        case "integer": return value.integer;
        case "float": return value.float;
        case "text": return value.text;
        case "blob": return decodeBlob(value.blob);
        case "boolean": return value.boolean;
    }
}

function toPositionalBindings(json: JsonBinding): D1Value[] {
    switch (json.kind) {
        case "none":
            return [];
        case "positional":
            return json.values.map(toD1Value);
        case "named":
            throw new Error("Cloudflare D1 adapter does not support named bindings yet");
    }
}

function toWireValue(value: unknown): WireValue {
    if (value === null || value === undefined) return { kind: "null" };
    if (typeof value === "string") return { kind: "text", text: value };
    if (typeof value === "boolean") return { kind: "boolean", boolean: value };
    if (typeof value === "number") {
        return Number.isInteger(value)
            ? { kind: "integer", integer: value }
            : { kind: "float", float: value };
    }
    if (value instanceof ArrayBuffer) {
        const bytes = new Uint8Array(value);
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        return { kind: "blob", blob: btoa(binary) };
    }
    if (ArrayBuffer.isView(value)) {
        const bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        return { kind: "blob", blob: btoa(binary) };
    }
    return { kind: "text", text: String(value) };
}

function objectToWireRow(record: Record<string, unknown>): WireRow {
    return {
        fields: Object.entries(record).map(([name, value]) => ({
            name,
            value: toWireValue(value),
        })),
    };
}

function valuesToWireRows(rows: unknown[][]): WireValue[][] {
    return rows.map((row) => row.map((value) => toWireValue(value)));
}

export function createD1Imports(
    bindings: Record<string, D1Database>,
    getMemory: () => WebAssembly.Memory,
): Record<string, unknown> {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    function readStr(ptr: number, len: number): string {
        return decoder.decode(new Uint8Array(getMemory().buffer, ptr, len));
    }

    function writeJson(buf_ptr: number, buf_max: number, value: unknown): number {
        const data = encoder.encode(JSON.stringify(value));
        if (data.length > buf_max) return -2;
        new Uint8Array(getMemory().buffer, buf_ptr, data.length).set(data);
        return data.length;
    }

    function binding(ns: string): D1Database | null {
        return bindings[ns] ?? bindings["default"] ?? null;
    }

    async function statement(
        ns_ptr: number,
        ns_len: number,
        sql_ptr: number,
        sql_len: number,
        bindings_ptr: number,
        bindings_len: number,
    ): Promise<D1PreparedStatement | null> {
        const database = binding(readStr(ns_ptr, ns_len));
        if (!database) return null;

        const sql = readStr(sql_ptr, sql_len);
        const bindingsJson = JSON.parse(readStr(bindings_ptr, bindings_len)) as JsonBinding;
        return database.prepare(sql).bind(...toPositionalBindings(bindingsJson));
    }

    const Suspending = (WebAssembly as any).Suspending;
    if (typeof Suspending !== "function") {
        return {
            db_open: (_ns: number, _ns_len: number): number => -1,
            db_run: (_a: number, _b: number, _c: number, _d: number, _e: number, _f: number, _g: number, _h: number): number => -1,
            db_get: (_a: number, _b: number, _c: number, _d: number, _e: number, _f: number, _g: number, _h: number): number => -1,
            db_all: (_a: number, _b: number, _c: number, _d: number, _e: number, _f: number, _g: number, _h: number): number => -1,
            db_values: (_a: number, _b: number, _c: number, _d: number, _e: number, _f: number, _g: number, _h: number): number => -1,
        };
    }

    return {
        db_open: (ns_ptr: number, ns_len: number): number => binding(readStr(ns_ptr, ns_len)) ? 0 : -1,

        db_run: new Suspending(async (
            ns_ptr: number, ns_len: number,
            sql_ptr: number, sql_len: number,
            bindings_ptr: number, bindings_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const stmt = await statement(ns_ptr, ns_len, sql_ptr, sql_len, bindings_ptr, bindings_len);
            if (!stmt) return -1;
            const result = await stmt.run();
            return writeJson(buf_ptr, buf_max, {
                last_insert_rowid: result.meta?.last_row_id ?? 0,
                changes: result.meta?.changes ?? 0,
            });
        }),

        db_get: new Suspending(async (
            ns_ptr: number, ns_len: number,
            sql_ptr: number, sql_len: number,
            bindings_ptr: number, bindings_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const stmt = await statement(ns_ptr, ns_len, sql_ptr, sql_len, bindings_ptr, bindings_len);
            if (!stmt) return -1;
            const row = await stmt.first<Record<string, unknown>>();
            if (!row) return 0;
            return writeJson(buf_ptr, buf_max, [objectToWireRow(row)]);
        }),

        db_all: new Suspending(async (
            ns_ptr: number, ns_len: number,
            sql_ptr: number, sql_len: number,
            bindings_ptr: number, bindings_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const stmt = await statement(ns_ptr, ns_len, sql_ptr, sql_len, bindings_ptr, bindings_len);
            if (!stmt) return -1;
            const result = await stmt.all<Record<string, unknown>>();
            return writeJson(buf_ptr, buf_max, (result.results ?? []).map(objectToWireRow));
        }),

        db_values: new Suspending(async (
            ns_ptr: number, ns_len: number,
            sql_ptr: number, sql_len: number,
            bindings_ptr: number, bindings_len: number,
            buf_ptr: number, buf_max: number,
        ): Promise<number> => {
            const stmt = await statement(ns_ptr, ns_len, sql_ptr, sql_len, bindings_ptr, bindings_len);
            if (!stmt) return -1;
            const rows = await stmt.raw();
            return writeJson(buf_ptr, buf_max, valuesToWireRows(rows));
        }),
    };
}
