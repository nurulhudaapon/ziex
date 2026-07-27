type MemoryEntry = [string, number | undefined];
const store = new Map<string, MemoryEntry>();

export async function get(key: string): Promise<string | null> {
    const entry = store.get(key);
    if (!entry) return null;
    const expiresAt = entry[1];
    if (expiresAt !== undefined && Date.now() >= expiresAt) {
        store.delete(key);
        return null;
    }
    return entry[0];
}

export async function put(
    key: string,
    value: string,
    options?: { expiration?: number; expirationTtl?: number },
): Promise<void> {
    let expiresAt: number | undefined;
    if (options?.expiration !== undefined) {
        expiresAt = options.expiration * 1000;
    } else if (options?.expirationTtl !== undefined) {
        expiresAt = Date.now() + options.expirationTtl * 1000;
    }
    store.set(key, [value, expiresAt]);
}

export async function del(key: string): Promise<void> {
    store.delete(key);
}

export async function list(options?: { prefix?: string }): Promise<{ keys: { name: string }[] }> {
    const keys: { name: string }[] = [];
    for (const name of [...store.keys()]) {
        if (options?.prefix && !name.startsWith(options.prefix)) continue;
        if ((await get(name)) !== null) keys.push({ name });
    }
    return { keys };
}
