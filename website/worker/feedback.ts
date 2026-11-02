const MAX_BODY_BYTES = 16 * 1024;
const MAX_MESSAGE_LENGTH = 4000;
const categoryLabels = {
  problem: "问题反馈",
  suggestion: "功能建议",
  other: "其他反馈",
} as const;
const allowedFields = new Set([
  "category",
  "message",
  "email",
  "includeDeviceInfo",
  "appVersion",
  "buildNumber",
  "platform",
  "website",
]);

type FeedbackCategory = keyof typeof categoryLabels;

export interface FeedbackEnv {
  RESEND_API_KEY?: string;
  FEEDBACK_FROM?: string;
  FEEDBACK_TO?: string;
}

type Fetcher = typeof fetch;

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function optionalText(
  value: unknown,
  maximumLength: number,
): string | null {
  if (value === undefined) return "";
  if (typeof value !== "string" || value.length > maximumLength) return null;
  return value.trim();
}

function validEmail(email: string): boolean {
  return (
    email.length <= 254 &&
    !/[\r\n]/.test(email) &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  );
}

export async function handleFeedback(
  request: Request,
  env: FeedbackEnv,
  fetcher: Fetcher = fetch,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "仅支持 POST 请求" }, 405);
  }
  const contentType = request.headers.get("content-type") ?? "";
  if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
    return json({ error: "请求必须使用 JSON" }, 415);
  }
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    return json({ error: "反馈内容过大" }, 413);
  }

  let payload: unknown;
  try {
    const body = await request.text();
    if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) {
      return json({ error: "反馈内容过大" }, 413);
    }
    payload = JSON.parse(body);
  } catch {
    return json({ error: "请求格式无效" }, 400);
  }
  if (!isRecord(payload)) return json({ error: "请求格式无效" }, 400);
  if (Object.keys(payload).some((key) => !allowedFields.has(key))) {
    return json({ error: "包含不支持的字段" }, 400);
  }

  const website = optionalText(payload.website, 200);
  if (website === null) return json({ error: "请求格式无效" }, 400);
  if (website) return json({ ok: true });

  const category = payload.category;
  if (
    typeof category !== "string" ||
    !Object.hasOwn(categoryLabels, category)
  ) {
    return json({ error: "反馈类型无效" }, 400);
  }
  const message = optionalText(payload.message, MAX_MESSAGE_LENGTH);
  if (!message) return json({ error: "请填写 1–4000 字反馈内容" }, 400);
  const email = optionalText(payload.email, 254);
  if (email === null || (email !== "" && !validEmail(email))) {
    return json({ error: "联系邮箱格式无效" }, 400);
  }
  if (
    payload.includeDeviceInfo !== undefined &&
    typeof payload.includeDeviceInfo !== "boolean"
  ) {
    return json({ error: "设备信息选项无效" }, 400);
  }
  const includeDeviceInfo = payload.includeDeviceInfo === true;
  const appVersion = optionalText(payload.appVersion, 80);
  const buildNumber = optionalText(payload.buildNumber, 40);
  const platform = optionalText(payload.platform, 40);
  if (appVersion === null || buildNumber === null || platform === null) {
    return json({ error: "版本或平台信息无效" }, 400);
  }

  const apiKey = env.RESEND_API_KEY?.trim();
  const from = env.FEEDBACK_FROM?.trim();
  const to = env.FEEDBACK_TO?.trim();
  if (
    !apiKey ||
    !from ||
    !to ||
    /[\r\n]/.test(from) ||
    /[\r\n]/.test(to)
  ) {
    return json({ error: "反馈服务尚未配置" }, 503);
  }

  const lines = [
    `类型：${categoryLabels[category as FeedbackCategory]}`,
    "",
    message,
    "",
    `联系方式：${email || "未填写"}`,
  ];
  if (includeDeviceInfo) {
    lines.push(
      `应用版本：${appVersion || "未知"}${buildNumber ? `+${buildNumber}` : ""}`,
      `平台：${platform || "未知"}`,
    );
  }

  const emailPayload: Record<string, unknown> = {
    from,
    to: [to],
    subject: `[MuBangumi 反馈] ${categoryLabels[category as FeedbackCategory]}`,
    text: lines.join("\n"),
  };
  if (email) emailPayload.reply_to = email;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(emailPayload),
      redirect: "manual",
      signal: controller.signal,
    });
    if (!response.ok) return json({ error: "邮件服务暂时不可用" }, 502);
    const result: unknown = await response.json();
    if (!isRecord(result) || typeof result.id !== "string" || !result.id) {
      return json({ error: "邮件服务未确认提交" }, 502);
    }
    return json({ ok: true });
  } catch {
    return json({ error: "邮件服务暂时不可用" }, 502);
  } finally {
    clearTimeout(timeout);
  }
}
