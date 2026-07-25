import type { SyncKVNamespace } from "../kv";

export type LocalStorageKVOptions = {
    namespace?: string;
    storagePrefix?: string;
};

function getLocalStorage(): Storage {
    if (typeof localStorage === "undefined") {
        throw new Error("localStorage is not available in this environment");
    }
    return localStorage;
}

export function createLocalStorageKV(options: LocalStorageKVOptions = {}): SyncKVNamespace {
    const storage = getLocalStorage();
    const namespace = options.namespace ?? "default";
    const storagePrefix = options.storagePrefix ?? "ziex-kv";
    const scopedKey = (key: string): string => `${storagePrefix}:${namespace}:${key}`;
    const namespacePrefix = scopedKey("");

    return {
        getSync(key) {
            return storage.getItem(scopedKey(key));
        },
        async get(key) {
            return this.getSync(key);
        },

        putSync(key, value) {
            storage.setItem(scopedKey(key), value);
        },
        async put(key, value) {
            this.putSync(key, value);
        },

        deleteSync(key) {
            storage.removeItem(scopedKey(key));
        },
        async delete(key) {
            this.deleteSync(key);
        },

        listSync(options) {
            const prefix = namespacePrefix + (options?.prefix ?? "");
            const keys: { name: string }[] = [];
            for (let i = 0; i < storage.length; i += 1) {
                const key = storage.key(i);
                if (!key || !key.startsWith(prefix)) continue;
                keys.push({ name: key.slice(namespacePrefix.length) });
            }
            return { keys };
        },
        async list(options) {
            return this.listSync(options);
        },
    };
}
