import { Bot, Context, InlineKeyboard } from "grammy";
import { Env, TelegramUserLike } from "./types";
import { getOrCreateUser, getAdminState, setAdminState } from "./db";
import { parseAdminIds } from "./utils";
import { createVerifyKeyboard } from "./commands";

export function setupMessageHandlers(bot: Bot, env: Env, adminIdSet: Set<number>) {
  bot.on("message", async (ctx: Context) => {
    const from = ctx.from;
    const chat = ctx.chat;
    if (!from || !chat || chat.type !== "private") return;

    const isAdmin = adminIdSet.has(from.id);
    if (isAdmin) {
      await handleAdminMessage(ctx, env, from.id);
      return;
    }

    await handleUserMessage(ctx, env, parseAdminIds(env.ADMIN_IDS));
  });
}

async function handleAdminMessage(ctx: Context, env: Env, adminId: number) {
  const adminState = await getAdminState(env, adminId);
  
  // 处理群发状态
  if (adminState && adminState.action === "broadcast") {
    await setAdminState(env, adminId, {
      action: "broadcast",
      messageId: ctx.message!.message_id,
      chatId: ctx.chat!.id,
    });
    
    const keyboard = new InlineKeyboard()
      .text("✅ 确认群发", "broadcast:confirm")
      .text("❌ 取消", "broadcast:cancel");
    
    await ctx.reply(
      "📢 已收到群发内容\n\n" +
      "请确认是否开始群发给所有用户（包括未验证用户）？",
      { reply_markup: keyboard }
    );
    return;
  }
  
  // 管理员回复消息
  const replyTo = ctx.message?.reply_to_message;
  if (replyTo) {
    const messageKey = `msg:${replyTo.message_id}`;
    const userIdStr = await env.KV.get(messageKey);
    
    if (userIdStr) {
      const userId = parseInt(userIdStr, 10);
      const { getUser } = await import("./db");
      const user = await getUser(env, userId);
      
      await ctx.api.copyMessage(userId, ctx.chat!.id, ctx.message!.message_id);
      
      const userName = user?.firstName || user?.username || `用户 ${userId}`;
      await ctx.reply(`✅ 回复已发送给 ${userName} (ID: ${userId})`);
      return;
    }
  }
  
  await ctx.reply("💡 请回复用户发来的消息，以便将回复发送给该用户");
}

async function handleUserMessage(ctx: Context, env: Env, adminIds: number[]) {
  const from = ctx.from!;
  const user = await getOrCreateUser(env, from as TelegramUserLike);

  if (user.banned) {
    await ctx.reply("你已被管理员封禁，无法继续与机器人对话。");
    return;
  }

  if (!user.verified) {
    const keyboard = createVerifyKeyboard(env.MINIAPP_URL);
    await ctx.reply("为了防止机器人滥用，请先点击下方按钮完成验证：", {
      reply_markup: keyboard,
    });
    return;
  }

  const name = user.firstName ?? from.first_name ?? "未知用户";
  const username = user.username ?? from.username;
  const header = `来自用户 ${name}${username ? ` (@${username})` : ""} (ID: ${from.id})`;

  for (const adminId of adminIds) {
    // 先转发用户消息
    const forwardedMessage = await ctx.api.forwardMessage(adminId, ctx.chat!.id, ctx.message!.message_id);
    
    // 然后发送引用该消息的提示（包含封禁按钮）
    const keyboardForAdmin = new InlineKeyboard().text(
      "封禁此用户",
      `ban:${user.id}`,
    );
    
    await ctx.api.sendMessage(adminId, header, {
      reply_to_message_id: forwardedMessage.message_id,
      reply_markup: keyboardForAdmin,
    });
    
    // 保存消息 ID 映射（保存 90 天）
    const messageKey = `msg:${forwardedMessage.message_id}`;
    await env.KV.put(messageKey, user.id.toString(), { expirationTtl: 7776000 });
  }

  await ctx.reply("消息已发送，请耐心等待回复。");
}

