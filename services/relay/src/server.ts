import express, { Request, Response, NextFunction } from "express";
import rateLimit from "express-rate-limit";
import cors from "cors";

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "1mb" }));

// CORS setup
const corsOriginsEnv = process.env.CORS_ORIGIN?.trim();
let corsOrigins: string | string[] = "*";
if (corsOriginsEnv && corsOriginsEnv !== "*") {
  corsOrigins = corsOriginsEnv.split(",").map((s) => s.trim()).filter(Boolean);
}
app.use(
  cors({
    origin: corsOrigins,
  })
);

// Simple per-IP rate limit for the relay endpoint
const limiter = rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true });
app.use("/v1/relay", limiter);

// Minimal auth: shared token header. Replace with JWT/device auth later.
app.use((req: Request, res: Response, next: NextFunction) => {
  const token = req.header("x-app-token");
  const expected = process.env.APP_SHARED_TOKEN;
  if (!expected || !token || token !== expected) {
    return res
      .status(401)
      .json({ error: "Unauthorized: missing or invalid x-app-token" });
  }
  return next();
});

app.post("/v1/relay", async (req: Request, res: Response) => {
  const upstreamUrl = "https://api.openai.com/v1/responses";
  const openaiKey = process.env.OPENAI_API_KEY || process.env.openai_api_key;
  if (!openaiKey) {
    return res
      .status(500)
      .json({ error: "server_misconfig", detail: "OPENAI_API_KEY not set" });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60_000);

  const started = Date.now();
  try {
    const r = await fetch(upstreamUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify(req.body ?? {}),
      signal: controller.signal,
    } as any);

    const ct = r.headers.get("content-type") || "application/json";
    const bodyText = await r.text();

    // Verbose logging without leaking secrets
    console.log(
      JSON.stringify({
        at: "/v1/relay",
        method: req.method,
        status: r.status,
        duration_ms: Date.now() - started,
        upstream_ct: ct,
        req_body_bytes: Buffer.byteLength(JSON.stringify(req.body ?? {})),
        resp_body_bytes: Buffer.byteLength(bodyText),
      })
    );

    res.status(r.status).type(ct).send(bodyText);
  } catch (e: any) {
    const msg = String(e?.message || e);
    const aborted = e?.name === "AbortError";
    console.error(
      JSON.stringify({
        at: "/v1/relay",
        method: req.method,
        error: msg,
        aborted,
        duration_ms: Date.now() - started,
      })
    );
    res
      .status(aborted ? 504 : 500)
      .json({ error: aborted ? "upstream_timeout" : "relay_failed", detail: msg });
  } finally {
    clearTimeout(timeout);
  }
});

// Token-protected endpoint to provide the current OpenAI API key to clients.
app.get("/v1/key", async (_req: Request, res: Response) => {
  const openaiKey = process.env.OPENAI_API_KEY || process.env.openai_api_key;
  if (!openaiKey) {
    return res.status(500).json({ error: "server_misconfig", detail: "OPENAI_API_KEY not set" });
  }
  // Prevent caches from storing the secret response
  res.setHeader("Cache-Control", "no-store");
  // Do not log the full key; emit only a short fingerprint
  const fp = `${openaiKey.slice(0, 6)}...${openaiKey.slice(-4)}`;
  console.log(JSON.stringify({ at: "/v1/key", provided: true, key_fingerprint: fp }));
  return res.status(200).json({ openai_api_key: openaiKey });
});

// Error handler for malformed JSON and other errors
app.use((err: any, _req: Request, res: Response, _next: NextFunction) => {
  if (err?.type === "entity.too.large") {
    return res
      .status(413)
      .json({ error: "payload_too_large", detail: "limit 1mb" });
  }
  if (err instanceof SyntaxError) {
    return res.status(400).json({ error: "bad_json", detail: String(err) });
  }
  console.error(JSON.stringify({ at: "error_mw", error: String(err) }));
  return res.status(500).json({ error: "server_error" });
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(
    JSON.stringify({
      msg: "relay up",
      port,
      cors_origins: corsOrigins,
      rate_limit_per_min: 60,
      upstream: "openai_responses",
    })
  );
});
