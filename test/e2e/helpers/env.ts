export function isRemoteStaticDeploy(): boolean {
  return false;
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
