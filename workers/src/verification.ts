import { cleanBotToken } from "./utils";

export async function verifyTelegramInitData(
  initData: string,
  botToken: string,
): Promise<{ valid: boolean; userId?: number }> {
  try {
    const cleanToken = cleanBotToken(botToken);
    
    const params = new URLSearchParams(initData);
    const hash = params.get("hash");
    if (!hash) {
      console.log('Telegram verification failed: no hash');
      return { valid: false };
    }

    params.delete("hash");
    const sortedKeys: string[] = [];
    params.forEach((_, key) => sortedKeys.push(key));
    sortedKeys.sort();
    const dataCheckString = sortedKeys
      .map((key) => `${key}=${params.get(key)}`)
      .join("\n");

    console.log('Telegram verification:', {
      hashLength: hash.length,
      dataCheckStringLength: dataCheckString.length,
      sortedKeys: sortedKeys
    });

    const encoder = new TextEncoder();
    const secretKey = await crypto.subtle.importKey(
      "raw",
      encoder.encode("WebAppData"),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const tokenKey = await crypto.subtle.sign(
      "HMAC",
      secretKey,
      encoder.encode(cleanToken),
    );

    const dataKey = await crypto.subtle.importKey(
      "raw",
      tokenKey,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const signature = await crypto.subtle.sign(
      "HMAC",
      dataKey,
      encoder.encode(dataCheckString),
    );

    const computedHash = Array.from(new Uint8Array(signature))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    console.log('Hash comparison:', {
      computed: computedHash,
      received: hash,
      match: computedHash === hash
    });

    if (computedHash !== hash) {
      console.log('Telegram verification failed: hash mismatch');
      return { valid: false };
    }

    const userParam = params.get("user");
    if (!userParam) return { valid: false };

    const user = JSON.parse(userParam);
    return { valid: true, userId: user.id };
  } catch {
    return { valid: false };
  }
}

export async function verifyTurnstileToken(
  token: string,
  secret: string,
): Promise<{ success: boolean; error?: string; details?: any }> {
  try {
    const cleanSecret = secret.replace(/^\uFEFF/, '').trim();
    
    console.log('Verifying Turnstile token:', {
      tokenLength: token.length,
      secretLength: cleanSecret.length,
      secretPrefix: cleanSecret.substring(0, 10)
    });
    
    const response = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ secret: cleanSecret, response: token }),
      },
    );

    const data = (await response.json()) as any;
    console.log('Turnstile API response:', data);
    
    if (!data.success) {
      return { 
        success: false, 
        error: 'Turnstile verification failed',
        details: data
      };
    }
    
    return { success: true };
  } catch (error) {
    console.error('Turnstile verification error:', error);
    return { 
      success: false, 
      error: 'Exception during verification',
      details: error
    };
  }
}

