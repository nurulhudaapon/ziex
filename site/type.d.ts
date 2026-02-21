// Make import of .zig files work in TypeScript
declare module "*.zig" {
    const content: string;
    export default content;
}
declare module "*.zx" {
    const content: string;
    export default content;
}
declare module "*.css" {
    const content: string;
    export default content;
}