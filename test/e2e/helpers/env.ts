/**
 * True when Playwright is pointed at a remote BASE_URL (e.g. https://ziex.dev).
 * The public deploy is a static export — server actions, POST APIs, DB/KV writes,
 * and some playground-only UI are not available there. Leave unset for local
 * `zig build e2e` so the full suite still runs against `zig build dev`.
 */
export function isRemoteStaticDeploy(): boolean {
  const base = process.env.BASE_URL;
  if (!base) return false;
  try {
    const { hostname } = new URL(base);
    return hostname !== 'localhost' && hostname !== '127.0.0.1' && hostname !== '[::1]';
  } catch {
    return false;
  }
}

export const skipOnRemoteStatic = isRemoteStaticDeploy();
