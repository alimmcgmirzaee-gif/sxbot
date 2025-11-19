export function parseAdminIds(raw: string): number[] {
  return raw
    .split(",")
    .map((s) => Number(s.trim()))
    .filter((n) => Number.isFinite(n));
}

export function cleanBotToken(token: string): string {
  return token.replace(/^\uFEFF/, '').trim();
}

