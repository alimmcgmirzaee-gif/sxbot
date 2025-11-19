import { Bot, Context } from "grammy";
import { Env } from "./types";
import { getUser, saveUser, getAdminState, setAdminState, getAllUsers } from "./db";

export function setupCallbackHandlers(bot: Bot, env: Env, adminIdSet: Set<number>) {
  bot.on("callback_query:data", async (ctx: Context) => {
    const from = ctx.from;
    if (!from || !adminIdSet.has(from.id)) {
      await ctx.answerCallbackQuery({
        text: "你不是管理员，无权进行此操作。",
        show_alert: true,
      });
      return;
    }

    const data = ctx.callbackQuery!.data!;
    
    // 处理群发确认
    if (data === "broadcast:confirm") {
      await handleBroadcastConfirm(ctx, env, from.id);
      return;
    }
    
    // 处理群发取消
    if (data === "broadcast:cancel") {
      await setAdminState(env, from.id, null);
      await ctx.editMessageText("❌ 已取消群发");
      await ctx.answerCallbackQuery();
      return;
    }
    
    // 处理封禁用户
    if (data.startsWith("ban:")) {
      await handleBanUser(ctx, env, data);
      return;
    }
  });
}

async function handleBroadcastConfirm(ctx: Context, env: Env, adminId: number) {
  const adminState = await getAdminState(env, adminId);
  if (!adminState || !adminState.messageId || !adminState.chatId) {
    await ctx.answerCallbackQuery({ text: "群发消息已过期，请重新开始" });
    return;
  }
  
  await ctx.editMessageText("⏳ 正在群发...");
  await ctx.answerCallbackQuery();
  
  // 获取所有用户（包括未验证的）
  const allUsers = await getAllUsers(env);
  let successCount = 0;
  let failCount = 0;
  
  for (const user of allUsers) {
    // 跳过被封禁的用户
    if (user.banned) continue;
    
    try {
      await ctx.api.copyMessage(user.id, adminState.chatId, adminState.messageId);
      successCount++;
    } catch (error) {
      failCount++;
      console.error(`Failed to send to user ${user.id}:`, error);
    }
  }
  
  // 清除管理员状态
  await setAdminState(env, adminId, null);
  
  await ctx.api.sendMessage(
    ctx.chat!.id,
    `✅ 群发完成\n\n成功: ${successCount}\n失败: ${failCount}`
  );
}

async function handleBanUser(ctx: Context, env: Env, data: string) {
  const userId = Number(data.split(":")[1]);
  if (!Number.isFinite(userId)) {
    await ctx.answerCallbackQuery({ text: "无效的用户 ID" });
    return;
  }

  const user = await getUser(env, userId);
  if (!user) {
    await ctx.answerCallbackQuery({
      text: "未找到该用户记录。",
      show_alert: true,
    });
    return;
  }

  user.banned = true;
  await saveUser(env, user);

  await ctx.answerCallbackQuery({
    text: `已封禁用户 ID ${userId}`,
    show_alert: true,
  });

  await ctx.editMessageReplyMarkup();
}

