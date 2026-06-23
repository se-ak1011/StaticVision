// Supabase Edge Function: openai-proxy
//
// Holds the OpenAI API key server-side (as a Supabase secret) and forwards
// chat-completion requests to OpenAI. The StaticVision app calls this instead
// of talking to OpenAI directly, so the key never ships inside the binary.
//
// JWT verification is enabled by default, so only authenticated Supabase users
// can invoke it. The request body is passed through to OpenAI unchanged, and the
// OpenAI response is returned verbatim.
//
// Deploy:
//   supabase functions deploy openai-proxy
//   supabase secrets set OPENAI_API_KEY=sk-...
//
// Local test:
//   supabase functions serve openai-proxy --env-file supabase/.env.local

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!OPENAI_API_KEY) {
    return json({ error: "OPENAI_API_KEY is not configured on the server" }, 500);
  }

  let body: string;
  try {
    body = await req.text();
  } catch {
    return json({ error: "Invalid request body" }, 400);
  }

  try {
    const openaiRes = await fetch(OPENAI_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body,
    });

    const responseBody = await openaiRes.text();
    return new Response(responseBody, {
      status: openaiRes.status,
      headers: { "Content-Type": "application/json" },
    });
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
