// Cloudflare Pages Function: POST /api/feedback
// Stores user feedback & structured word-bug reports in Cloudflare D1 (`env.DB`)
// and optional file attachments in Cloudflare R2 (`env.FILES`).
const KINDS = ["word_bug", "bug", "idea", "other"];
const PLATFORMS = ["macos", "ios", "windows", "linux", "android", "web"];
const MAX_FILES = 5;
const MAX_FILE = 25 * 1024 * 1024;
const MAX_TOTAL = 50 * 1024 * 1024;
const OK_EXT = /\.(png|jpe?g|gif|webp|heic|heif|mp4|mov|m4v|webm|txt|log|ips|crash|json|zip|pdf)$/i;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" }
  });

const clip = (v, n) => String(v || "").trim().slice(0, n);

export async function onRequestPost({ request, env }) {
  let d = {};
  let files = [];
  try {
    if ((request.headers.get("content-type") || "").includes("multipart/form-data")) {
      const form = await request.formData();
      d = Object.fromEntries([...form.entries()].filter(([, v]) => typeof v === "string"));
      files = form.getAll("files").filter(f => typeof f === "object" && f.size > 0);
    } else {
      d = await request.json();
    }
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  // Honeypot spam filter
  if (d.website) {
    return json({ ok: true });
  }

  const typedKeys = clip(d.typed_keys, 128);
  const actualOutput = clip(d.actual_output, 128);
  const expectedOutput = clip(d.expected_output, 128);
  const targetApp = clip(d.target_app, 128);
  const message = clip(d.message, 5000);
  if (message.length < 3 && !typedKeys && !actualOutput) {
    return json({ ok: false, error: "message" }, 400);
  }

  const email = clip(d.email, 254).toLowerCase();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
    return json({ ok: false, error: "email" }, 400);
  }

  if (
    files.length > MAX_FILES ||
    files.some(f => f.size > MAX_FILE || !OK_EXT.test(f.name)) ||
    files.reduce((sum, f) => sum + f.size, 0) > MAX_TOTAL
  ) {
    return json({ ok: false, error: "files" }, 400);
  }

  const kind = KINDS.includes(d.kind) ? d.kind : "other";
  const platform = PLATFORMS.includes(d.platform) ? d.platform : "web";
  const version = clip(d.version, 32) || null;
  const build = clip(d.build, 32) || null;
  const im = clip(d.im, 16) || null;
  const ua = clip(request.headers.get("user-agent"), 300);

  if (env.TURNSTILE_SECRET) {
    const verifyRes = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: new URLSearchParams({
        secret: env.TURNSTILE_SECRET,
        response: String(d.token || ""),
        remoteip: request.headers.get("CF-Connecting-IP") || ""
      })
    });
    const verifyData = await verifyRes.json().catch(() => ({ success: false }));
    if (!verifyData.success) {
      return json({ ok: false, error: "captcha" }, 403);
    }
  }

  if (env.DB) {
    const row = await env.DB.prepare(
      "INSERT INTO feedback (kind, platform, version, build, im, typed_keys, actual_output, expected_output, target_app, message, email, ua) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    )
      .bind(
        kind,
        platform,
        version,
        build,
        im,
        typedKeys || null,
        actualOutput || null,
        expectedOutput || null,
        targetApp || null,
        message,
        email || null,
        ua
      )
      .run();

    if (files.length && env.FILES) {
      const id = row.meta.last_row_id;
      const keys = [];
      for (const [i, f] of files.entries()) {
        const safeName = f.name.replace(/[^\w.\-]+/g, "_").slice(-80);
        const key = `feedback/${id}/${i + 1}-${safeName}`;
        await env.FILES.put(key, f.stream(), {
          httpMetadata: { contentType: f.type || "application/octet-stream" }
        });
        keys.push(key);
      }
      await env.DB.prepare("UPDATE feedback SET attachments = ? WHERE id = ?")
        .bind(JSON.stringify(keys), id)
        .run();
    }
  }

  return json({ ok: true });
}
