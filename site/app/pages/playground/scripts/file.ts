export interface PlaygroundFile {
    name: string;
    content: string;
}

export class FileManager {
    private files: Map<string, string> = new Map();
    private listeners: Set<() => void> = new Set();

    addFile(name: string, content: string): void {
        this.files.set(name, content);
    }

    removeFile(name: string): boolean {
        const deleted = this.files.delete(name);
        return deleted;
    }

    renameFile(oldName: string, newName: string): boolean {
        if (!this.files.has(oldName) || this.files.has(newName)) {
            return false;
        }
        const content = this.files.get(oldName)!;
        this.files.delete(oldName);
        this.files.set(newName, content);
        return true;
    }

    updateContent(name: string, content: string): void {
        if (this.files.has(name)) {
            this.files.set(name, content);
        }
    }

    getAllFiles(): PlaygroundFile[] {
        return Array.from(this.files.entries()).map(([name, content]) => ({
            name,
            content,
        }));
    }

    hasFile(name: string): boolean {
        return this.files.has(name);
    }

}

export const fileManager = new FileManager();
