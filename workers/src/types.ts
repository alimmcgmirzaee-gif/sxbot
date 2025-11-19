export interface Env {
  BOT_TOKEN: string;
  TURNSTILE_SECRET: string;
  MINIAPP_URL: string;
  ADMIN_IDS: string;
  KV: KVNamespace;
}

export interface UserRecord {
  id: number;
  username?: string;
  firstName?: string;
  verified: boolean;
  verifiedAt?: string;
  banned: boolean;
}

export interface AdminState {
  action: "broadcast";
  messageId?: number;
  chatId?: number;
}

export interface TelegramUserLike {
  id: number;
  username?: string;
  first_name?: string;
}

