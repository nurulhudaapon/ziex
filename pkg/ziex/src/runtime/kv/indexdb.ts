import type { KVNamespace } from "../kv";

export type IndexedDbKVOptions = {
    databaseName?: string;
    storeName?: string;
    namespace?: string;
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
            return typeof value === "string" ? value : null;
        },

        async put(key, value) {
            const db = await dbPromise;
            const tx = db.transaction(storeName, "readwrite");
            tx.objectStore(storeName).put(value, scopedKey(key));
            await transactionToPromise(tx);
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
