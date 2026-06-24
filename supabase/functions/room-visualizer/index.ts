// Supabase Edge Function: room-visualizer
//
// Takes a room photo + a style prompt and returns a re-rendered "after" image
// using OpenAI's image model (gpt-image-1, /v1/images/edits). The OpenAI key
// stays server-side as a Supabase secret. JWT verification is on by default,
// so only authenticated app users can call it.
//
// Request  (JSON): { "image_base64": "...", "prompt": "...", "size": "auto" }
// Response (JSON): { "image_base64": "..." }   // the rendered image
//
// Deploy:
//   supabase functions deploy room-visualizer
//   (OPENAI_API_KEY secret is already set from the openai-proxy setup)
//
// NOTE: image generation requires your OpenAI org to be verified for gpt-image-1.

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const OPENAI_EDITS_URL = "https://api.openai.com/v1/images/edits";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!OPENAI_API_KEY) return json({ error: "OPENAI_API_KEY is not configured" }, 500);

  let payload: { image_base64?: string; prompt?: string; size?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { image_base64, prompt, size } = payload;
  if (!image_base64 || !prompt) {
    return json({ error: "Missing image_base64 or prompt" }, 400);
  }

  // Decode the base64 JPEG into bytes for multipart upload.
  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(image_base64), (c) => c.charCodeAt(0));
  } catch {
    return json({ error: "image_base64 is not valid base64" }, 400);
  }

  const form = new FormData();
  form.append("model", "gpt-image-1");
  form.append("prompt", prompt);
  form.append("size", size ?? "auto");
  form.append("quality", "medium");        // "high" looks better but is slower/pricier
  form.append("input_fidelity", "high");   // preserve the room's structure
  form.append("image", new Blob([bytes], { type: "image/jpeg" }), "room.jpg");

  try {
    const res = await fetch(OPENAI_EDITS_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: form,
    });

    const data = await res.json();
    if (!res.ok) {
      return json({ error: data?.error?.message ?? "OpenAI image edit failed", detail: data }, res.status);
    }

    const b64 = data?.data?.[0]?.b64_json;
    if (!b64) return json({ error: "No image returned by OpenAI" }, 502);

    return json({ image_base64: b64 }, 200);
  } catch (err) {
    return json({ error: `Upstream request failed: ${err}` }, 502);
  }
});

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
