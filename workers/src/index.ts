import { Bot, webhookCallback } from "grammy";
import { Env } from "./types";
import { parseAdminIds, cleanBotToken } from "./utils";
import { setupCommands } from "./commands";
import { setupMessageHandlers } from "./messages";
import { setupCallbackHandlers } from "./callbacks";
import { handleVerify, handleOptions } from "./api";

export { Env };

function createBot(env: Env): Bot {
  const cleanToken = cleanBotToken(env.BOT_TOKEN);
  const bot = new Bot(cleanToken);
  const adminIds = parseAdminIds(env.ADMIN_IDS);
  const adminIdSet = new Set(adminIds);

  // 设置命令处理
  setupCommands(bot, env, adminIdSet);
  
  // 设置消息处理
  setupMessageHandlers(bot, env, adminIdSet);
  
  // 设置回调处理
  setupCallbackHandlers(bot, env, adminIdSet);

  return bot;
}

export default {
  async fetch(
    request: Request,
    env: Env,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response("OK", { status: 200 });
    }

    if (url.pathname === "/webhook") {
      const bot = createBot(env);
      const handleUpdate = webhookCallback(bot, "cloudflare-mod");
      return handleUpdate(request);
    }

    // 处理 CORS preflight 请求
    if (request.method === "OPTIONS") {
      return handleOptions();
    }

    if (url.pathname === "/api/verify" && request.method === "POST") {
      return handleVerify(request, env);
    }

    return new Response("Not found", { status: 404 });
  },
};
