import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source = await readFile(new URL("../worker/feedback.ts", import.meta.url), "utf8");
const { outputText } = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 },
});
const moduleUrl = `data:text/javascript;base64,${Buffer.from(outputText).toString("base64")}`;
const { handleFeedback } = await import(moduleUrl);

const env = {
  RESEND_API_KEY: "re_test",
  FEEDBACK_FROM: "MuBangumi Feedback <no-reply@send.example.com>",
  FEEDBACK_TO: "feedback@example.com",
};

function request(payload, options = {}) {
  const method = options.method ?? "POST";
  return new Request("https://worker.example/api/feedback", {
    method,
    headers: { "content-type": "application/json", ...options.headers },
    body: method === "GET" ? undefined : options.rawBody ?? JSON.stringify(payload ?? {
      category: "problem",
      message: "收藏页面无法同步",
      email: "reader@example.net",
      includeDeviceInfo: true,
      appVersion: "2.4.1",
      buildNumber: "4031",
      platform: "android",
      website: "",
    }),
  });
}

function successFetch(capture) {
  return async (input, init) => {
    capture.input = input;
    capture.init = init;
    return Response.json({ id: "email_test_id" });
  };
}

test("valid feedback sends a plain-text email with reply-to and device info", async () => {
  const capture = {};
  const response = await handleFeedback(request(), env, successFetch(capture));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(capture.input, "https://api.resend.com/emails");
  assert.equal(capture.init.headers.Authorization, "Bearer re_test");

  const email = JSON.parse(capture.init.body);
  assert.equal(email.from, env.FEEDBACK_FROM);
  assert.deepEqual(email.to, [env.FEEDBACK_TO]);
  assert.equal(email.reply_to, "reader@example.net");
  assert.equal(email.subject, "[MuBangumi 反馈] 问题反馈");
  assert.match(email.text, /收藏页面无法同步/);
  assert.match(email.text, /应用版本：2\.4\.1\+4031/);
  assert.match(email.text, /平台：android/);
  assert.equal(email.html, undefined);
});

test("optional contact and device information are omitted", async () => {
  const capture = {};
  const response = await handleFeedback(request({
    category: "suggestion",
    message: "希望增加评分筛选",
    email: "",
    includeDeviceInfo: false,
    appVersion: "should-not-appear",
    buildNumber: "0",
    platform: "hidden",
  }), env, successFetch(capture));
  assert.equal(response.status, 200);
  const email = JSON.parse(capture.init.body);
  assert.equal(email.reply_to, undefined);
  assert.match(email.text, /联系方式：未填写/);
  assert.doesNotMatch(email.text, /should-not-appear|hidden/);
});

test("honeypot returns success without sending email", async () => {
  let called = false;
  const response = await handleFeedback(request({ website: "spam" }), env, async () => {
    called = true;
    return Response.json({ id: "unexpected" });
  });
  assert.equal(response.status, 200);
  assert.equal(called, false);
});

test("rejects malformed or abusive requests before sending", async () => {
  const cases = [
    [request({}, { method: "GET" }), 405],
    [request({}, { headers: { "content-type": "text/plain" } }), 415],
    [request(null, { rawBody: "{" }), 400],
    [request(null, { rawBody: JSON.stringify({ unknown: true }) }), 400],
    [request({ category: "invalid" }), 400],
    [request({ message: "   " }), 400],
    [request({ message: "x".repeat(4001) }), 400],
    [request({ email: "reader@example.net\r\nBcc: victim@example.net" }), 400],
    [request({ includeDeviceInfo: "yes" }), 400],
    [request({}, { rawBody: "x".repeat(16 * 1024 + 1) }), 413],
  ];
  for (const [badRequest, status] of cases) {
    let called = false;
    const response = await handleFeedback(badRequest, env, async () => {
      called = true;
      return Response.json({ id: "unexpected" });
    });
    assert.equal(response.status, status);
    assert.equal(called, false);
  }
});

test("reports success only after Resend confirms an email id", async () => {
  for (const result of [
    new Response(null, { status: 302, headers: { Location: "https://example.com/" } }),
    new Response("rejected", { status: 422 }),
    Response.json({ unexpected: true }),
  ]) {
    const response = await handleFeedback(request(), env, async () => result);
    assert.equal(response.status, 502);
    assert.equal((await response.json()).ok, undefined);
  }
});

test("missing server configuration and transport failures do not report success", async () => {
  const unconfigured = await handleFeedback(request(), {}, successFetch({}));
  assert.equal(unconfigured.status, 503);
  const failed = await handleFeedback(request(), env, async () => {
    throw new Error("offline");
  });
  assert.equal(failed.status, 502);
});
