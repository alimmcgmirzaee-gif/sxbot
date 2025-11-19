import { Env, UserRecord, AdminState, TelegramUserLike } from "./types";

export function userKey(userId: number): string {
  return `user:${userId}`;
}

export function adminStateKey(adminId: number): string {
  return `admin_state:${adminId}`;
}

export async function getUser(env: Env, userId: number): Promise<UserRecord | null> {
  const data = (await env.KV.get(userKey(userId), "json")) as UserRecord | null;
  return data ?? null;
}

export async function getOrCreateUser(env: Env, from: TelegramUserLike): Promise<UserRecord> {
  const existing = await getUser(env, from.id);
  if (existing) return existing;

  const fresh: UserRecord = {
    id: from.id,
    username: from.username,
    firstName: from.first_name,
    verified: false,
    banned: false,
  };
  await env.KV.put(userKey(fresh.id), JSON.stringify(fresh));
  return fresh;
}

export async function saveUser(env: Env, user: UserRecord): Promise<void> {
  await env.KV.put(userKey(user.id), JSON.stringify(user));
}

export async function getAdminState(env: Env, adminId: number): Promise<AdminState | null> {
  const data = await env.KV.get(adminStateKey(adminId), "json") as AdminState | null;
  return data;
}

export async function setAdminState(env: Env, adminId: number, state: AdminState | null): Promise<void> {
  if (state === null) {
    await env.KV.delete(adminStateKey(adminId));
  } else {
    await env.KV.put(adminStateKey(adminId), JSON.stringify(state));
  }
}

export async function getAllUsers(env: Env): Promise<UserRecord[]> {
  const allKeys = await env.KV.list({ prefix: "user:" });
  const users: UserRecord[] = [];
  
  for (const key of allKeys.keys) {
    const user = await env.KV.get(key.name, "json") as UserRecord | null;
    if (user) {
      users.push(user);
    }
  }
  
  return users;
}

