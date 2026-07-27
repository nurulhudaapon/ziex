export type Options = {
    namespace?: string;
    storagePrefix?: string;
};

const namespace = "default";
const storagePrefix = "ziex-kv";
const namespacePrefix = `${storagePrefix}:${namespace}:`;

function storage(): Storage {
    if (typeof localStorage === "undefined") {
        throw new Error("localStorage is not available in this environment");
    }
    return localStorage;
}

export function get(key: string): string | null {
    return storage().getItem(`${storagePrefix}:${namespace}:${key}`);
}

export function put(key: string, value: string): void {
    storage().setItem(`${storagePrefix}:${namespace}:${key}`, value);
}

export function del(key: string): void {
    storage().removeItem(`${storagePrefix}:${namespace}:${key}`);
}

export function list(options?: { prefix?: string }): { keys: { name: string }[] } {
    const ls = storage();
    const prefix = namespacePrefix + (options?.prefix ?? "");
    const keys: { name: string }[] = [];
    for (let i = 0; i < ls.length; i += 1) {
        const key = ls.key(i);
        if (!key || !key.startsWith(prefix)) continue;
        keys.push({ name: key.slice(namespacePrefix.length) });
    }
    return { keys };
}
