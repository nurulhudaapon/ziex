import type { KVNamespace, SyncKVNamespace } from "../kv";

export type IndexedDbKVOptions = {
    databaseName?: string;
    storeName?: string;
    namespace?: string;
};

export type BrowserKVOptions = IndexedDbKVOptions & {
    storagePrefix?: string;
};

function getIndexedDb(): IDBFactory {
    if (typeof indexedDB === "undefined") {
        throw new Error("IndexedDB is not available in this environment");
    }
    return indexedDB;
}

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
    return new Promise((resolve, reject) => {
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed"));
    });
}

function transactionToPromise(transaction: IDBTransaction): Promise<void> {
    return new Promise((resolve, reject) => {
        transaction.oncomplete = () => resolve();
        transaction.onabort = () => reject(transaction.error ?? new Error("IndexedDB transaction aborted"));
        transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB transaction failed"));
    });
}

export function createIndexedDbKV(options: IndexedDbKVOptions = {}): KVNamespace {
    const databaseName = options.databaseName ?? "ziex-kv";
    const storeName = options.storeName ?? "kv";
    const namespace = options.namespace ?? "default";
    const dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
        const request = getIndexedDb().open(databaseName, 1);

        request.onupgradeneeded = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains(storeName)) {
                db.createObjectStore(storeName);
            }
        };

        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error ?? new Error("Failed to open IndexedDB"));
    });

    const scopedKey = (key: string): string => `${namespace}:${key}`;

    return {
        async get(key) {
            const db = await dbPromise;
            const tx = db.transaction(storeName, "readonly");
            const store = tx.objectStore(storeName);
            const value = await requestToPromise(store.get(scopedKey(key)));
            await transactionToPromise(tx);

            console.debug(`KV GET - Key: ${key}, Value: ${value}`);
            return typeof value === "string" ? value : null;
        },

        async put(key, value) {
            const db = await dbPromise;
            const tx = db.transaction(storeName, "readwrite");
            tx.objectStore(storeName).put(value, scopedKey(key));
            await transactionToPromise(tx);
            console.debug(`KV PUT - Key: ${key}, Value: ${value}`);
        },

        async delete(key) {
            const db = await dbPromise;
            const tx = db.transaction(storeName, "readwrite");
            tx.objectStore(storeName).delete(scopedKey(key));
            await transactionToPromise(tx);
        },

        async list(options) {
            const db = await dbPromise;
            const tx = db.transaction(storeName, "readonly");
            const store = tx.objectStore(storeName);
            const keys = await requestToPromise(store.getAllKeys());
            await transactionToPromise(tx);

            const prefix = scopedKey(options?.prefix ?? "");
            return {
                keys: keys
                    .filter((key): key is string => typeof key === "string" && key.startsWith(prefix))
                    .map((key) => ({ name: key.slice(namespace.length + 1) })),
            };
        },
    };
}

function getLocalStorage(): Storage {
    if (typeof localStorage === "undefined") {
        throw new Error("localStorage is not available in this environment");
    }
    return localStorage;
}

export function createLocalStorageKV(options: BrowserKVOptions = {}): SyncKVNamespace {
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

export function hasJSPI(): boolean {
    return (
        typeof (WebAssembly as any).Suspending === "function" &&
        typeof (WebAssembly as any).promising === "function"
    );
}

export function createBrowserKVBindings(options: BrowserKVOptions = {}): Record<string, KVNamespace> {
    const namespace = options.namespace ?? "default";
    return {
        [namespace]: hasJSPI() ? createIndexedDbKV(options) : createLocalStorageKV(options),
    };
}
