/**
 * Ziex adapter for Vercel Edge Functions.
 *
 * @example
 * ```ts
 * import { Ziex } from "ziex/cloudflare";
 * import { handle } from "ziex/vercel";
 * import module from "./app.wasm"; // or fetch at runtime
 *
 * const app = new Ziex({ module });
 *
 * export const config = { runtime: "edge" };
 * export default handle(app);
 * ```
 */

type FetchApp = { fetch(req: Request, env?: unknown, ctx?: unknown): Promise<Response> };

/**
 * Wrap a Ziex app as a Vercel Edge Function handler.
 *
 * Returns a standard `(req: Request) => Promise<Response>` function.
 * Vercel's edge runtime calls it directly - just export it as default.
 */
export function handle(app: FetchApp): (req: Request) => Promise<Response> {
    return (req) => app.fetch(req);
}
