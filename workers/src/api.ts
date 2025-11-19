import { Env } from "./types";
import { getUser, saveUser } from "./db";
import { verifyTelegramInitData, verifyTurnstileToken } from "./verification";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export async function handleVerify(request: Request, env: Env): Promise<Response> {
  try {
    const body = (await request.json()) as {
      initData?: string;
      turnstileToken?: string;
    };

    if (!body.initData || !body.turnstileToken) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { 
          status: 400, 
          headers: { 
            "Content-Type": "application/json",
            ...corsHeaders
          } 
        },
      );
    }

    const initDataResult = await verifyTelegramInitData(
      body.initData,
      env.BOT_TOKEN,
    );
    if (!initDataResult.valid || !initDataResult.userId) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid Telegram data" }),
        { 
          status: 403, 
          headers: { 
            "Content-Type": "application/json",
            ...corsHeaders
          } 
        },
      );
    }

    const turnstileResult = await verifyTurnstileToken(
      body.turnstileToken,
      env.TURNSTILE_SECRET,
    );
    if (!turnstileResult.success) {
      console.error('Turnstile verification failed:', turnstileResult);
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: turnstileResult.error || "Turnstile verification failed",
          details: turnstileResult.details
        }),
        { 
          status: 403, 
          headers: { 
            "Content-Type": "application/json",
            ...corsHeaders
          } 
        },
      );
    }

    const user = await getUser(env, initDataResult.userId);
    if (!user) {
      return new Response(
        JSON.stringify({ success: false, error: "User not found" }),
        { 
          status: 404, 
          headers: { 
            "Content-Type": "application/json",
            ...corsHeaders
          } 
        },
      );
    }

    user.verified = true;
    user.verifiedAt = new Date().toISOString();
    await saveUser(env, user);

    // 发送验证成功消息给用户
    try {
      const { cleanBotToken } = await import("./utils");
      const cleanToken = cleanBotToken(env.BOT_TOKEN);
      const telegramApiUrl = `https://api.telegram.org/bot${cleanToken}/sendMessage`;
      
      await fetch(telegramApiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: user.id,
          text: "✅ 验证成功！\n\n现在您可以发送消息给管理员了OvO~",
        }),
      });
    } catch (error) {
      console.error("Failed to send verification success message:", error);
      // 即使发送消息失败，也返回验证成功
    }

    return new Response(
      JSON.stringify({ success: true }),
      { 
        status: 200, 
        headers: { 
          "Content-Type": "application/json",
          ...corsHeaders
        } 
      },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: "Internal server error" }),
      { 
        status: 500, 
        headers: { 
          "Content-Type": "application/json",
          ...corsHeaders
        } 
      },
    );
  }
}

export function handleOptions(): Response {
  return new Response(null, {
    status: 204,
    headers: corsHeaders,
  });
}

