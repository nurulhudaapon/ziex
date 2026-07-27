export type Options = {
    databaseName?: string;
    storeName?: string;
    namespace?: string;
};

const databaseName = "ziex-kv";
const storeName = "kv";
const namespace = "default";

let dbPromise: Promise<IDBDatabase> | undefined;

function openDb(): Promise<IDBDatabase> {
    if (!dbPromise) {
        if (typeof indexedDB === "undefined") {
            return Promise.reject(new Error("IndexedDB is not available in this environment"));
        }
        dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
            const request = indexedDB.open(databaseName, 1);

            request.onupgradeneeded = () => {
                const db = request.result;
                if (!db.objectStoreNames.contains(storeName)) {
                    db.createObjectStore(storeName);
                }
            };

            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error ?? new Error("Failed to open IndexedDB"));
        });
    }
    return dbPromise;
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

export async function get(key: string): Promise<string | null> {
    const db = await openDb();
    const tx = db.transaction(storeName, "readonly");
    const value = await requestToPromise(tx.objectStore(storeName).get(`${namespace}:${key}`));
    await transactionToPromise(tx);
    return typeof value === "string" ? value : null;
}

export async function put(key: string, value: string): Promise<void> {
    const db = await openDb();
    const tx = db.transaction(storeName, "readwrite");
    tx.objectStore(storeName).put(value, `${namespace}:${key}`);
    await transactionToPromise(tx);
}

export async function del(key: string): Promise<void> {
    const db = await openDb();
    const tx = db.transaction(storeName, "readwrite");
    tx.objectStore(storeName).delete(`${namespace}:${key}`);
    await transactionToPromise(tx);
}

export async function list(options?: { prefix?: string }): Promise<{ keys: { name: string }[] }> {
    const db = await openDb();
    const tx = db.transaction(storeName, "readonly");
    const keys = await requestToPromise(tx.objectStore(storeName).getAllKeys());
    await transactionToPromise(tx);

    const prefix = `${namespace}:${options?.prefix ?? ""}`;
    return {
        keys: keys
            .filter((key): key is string => typeof key === "string" && key.startsWith(prefix))
            .map((key) => ({ name: key.slice(namespace.length + 1) })),
    };
}
