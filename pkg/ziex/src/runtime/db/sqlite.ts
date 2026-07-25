/**
 * Native SQLite client binding - not implemented yet.
 * Server builds currently use the WASM `__zx_db` host via {@link createDbImports}.
 */
export const Sqlite = {
    open(_path: string): never {
        throw new Error("db/sqlite: not implemented yet");
    },
};
