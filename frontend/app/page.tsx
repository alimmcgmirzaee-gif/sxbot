"use client";

import { useEffect, useState } from "react";
import { Turnstile } from "@marsidev/react-turnstile";

// 动态导入 WebApp SDK，避免 SSR 时访问 window
let WebApp: any = null;
if (typeof window !== "undefined") {
  import("@twa-dev/sdk").then((mod) => {
    WebApp = mod.default;
    WebApp.ready();
    WebApp.expand();
  });
}

export default function VerifyPage() {
  const [turnstileToken, setTurnstileToken] = useState<string | null>(null);
  const [isVerifying, setIsVerifying] = useState(false);
  const [message, setMessage] = useState<{
    type: "error" | "success";
    text: string;
  } | null>(null);
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  const handleTurnstileSuccess = async (token: string) => {
    setTurnstileToken(token);
    await submitVerification(token);
  };

  const submitVerification = async (token: string) => {
    if (isVerifying) return;
    setIsVerifying(true);
    setMessage(null);

    try {
      if (!WebApp) {
        setMessage({
          type: "error",
          text: "正在初始化，请稍后重试。",
        });
        setIsVerifying(false);
        return;
      }

      const initData = WebApp.initData;
      if (!initData) {
        setMessage({
          type: "error",
          text: "无法获取 Telegram 用户信息，请在 Telegram 中打开此页面。",
        });
        setIsVerifying(false);
        return;
      }

      const apiUrl = process.env.NEXT_PUBLIC_API_URL || "";
      const response = await fetch(`${apiUrl}/api/verify`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          initData,
          turnstileToken: token,
        }),
      });

      const result = await response.json();

      if (result.success) {
        setMessage({ type: "success", text: "验证成功！正在关闭..." });
        setTimeout(() => {
          if (WebApp) WebApp.close();
        }, 1500);
      } else {
        setMessage({
          type: "error",
          text: `验证失败：${result.error || "未知错误"}`,
        });
        setIsVerifying(false);
      }
    } catch (error) {
      setMessage({ type: "error", text: "网络错误，请稍后重试。" });
      setIsVerifying(false);
    }
  };

  const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY || "";

  // 等待客户端渲染
  if (!isClient) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p>加载中...</p>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-5 bg-[var(--tg-theme-bg-color,#ffffff)] text-[var(--tg-theme-text-color,#000000)]">
      <div className="w-full max-w-md text-center">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold mb-3 text-[var(--tg-theme-text-color,#000000)]">
            🔐 人机验证
          </h1>
          <p className="text-sm text-[var(--tg-theme-hint-color,#999999)]">
            请完成下方验证以继续使用机器人
          </p>
        </div>

        {/* Verify Box */}
        <div className="bg-[var(--tg-theme-secondary-bg-color,#f0f0f0)] rounded-xl p-8 mb-5">
          <div className="flex justify-center">
            <Turnstile
              siteKey={siteKey}
              onSuccess={handleTurnstileSuccess}
              onError={() =>
                setMessage({
                  type: "error",
                  text: "Turnstile 验证失败，请刷新页面重试。",
                })
              }
            />
          </div>

          {/* Message */}
          {message && (
            <div className="mt-4">
              <p
                className={
                  message.type === "error"
                    ? "text-[var(--tg-theme-destructive-text-color,#ff3b30)]"
                    : "text-[var(--tg-theme-link-color,#007aff)]"
                }
              >
                {message.text}
              </p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="text-xs text-[var(--tg-theme-hint-color,#999999)]">
          <p>验证成功后窗口会自动关闭</p>
        </div>
      </div>
    </div>
  );
}
