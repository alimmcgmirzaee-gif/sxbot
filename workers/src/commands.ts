import { Bot, Context, InlineKeyboard } from "grammy";
import { Env, TelegramUserLike } from "./types";
import { getOrCreateUser, setAdminState } from "./db";

export function createVerifyKeyboard(miniAppUrl: string): InlineKeyboard {
  return new InlineKeyboard().webApp("点击这里完成验证 ✅", miniAppUrl);
}

export function setupCommands(bot: Bot, env: Env, adminIdSet: Set<number>) {
  // 处理 /start 命令
  bot.command("start", async (ctx: Context) => {
    const from = ctx.from;
    if (!from || ctx.chat?.type !== "private") return;

    const isAdmin = adminIdSet.has(from.id);
    if (isAdmin) {
      await setAdminState(env, from.id, null);
      await ctx.reply("👋 你好，管理员");
      return;
    }

    const user = await getOrCreateUser(env, from as TelegramUserLike);

    if (user.banned) {
      await ctx.reply("你已被管理员封禁，无法继续与机器人对话。");
      return;
    }

    if (!user.verified) {
      const keyboard = createVerifyKeyboard(env.MINIAPP_URL);
      await ctx.reply(
        "👋 欢迎使用本机器人！\n\n" +
        "为了防止机器人滥用，请先点击下方按钮完成人机验证：",
        { reply_markup: keyboard }
      );
      return;
    }

    await ctx.reply(
      "✅ 你已通过验证！\n\n" +
      "现在您可以发送消息给管理员了OvO~"
    );
  });

  // 处理 /qf 群发命令（仅管理员）
  bot.command("qf", async (ctx: Context) => {
    const from = ctx.from;
    if (!from || !adminIdSet.has(from.id)) {
      return;
    }

    await setAdminState(env, from.id, { action: "broadcast" });
    await ctx.reply(
      "📢 群发模式\n\n" +
      "请发送要群发的内容（支持文本、图片、视频等）。\n\n" +
      "💡 发送 /start 可以取消群发"
    );
  });
}

