/**
 * Pollie's proxy.
 *
 * The Gemini key lives here as a Worker secret instead of inside the APK,
 * where `strings libapp.so | grep AIza` recovers it in seconds. The app talks
 * only to this Worker, which means the key, the model choice and the system
 * prompt can all change without shipping a release.
 */

export interface Env {
  GEMINI_API_KEY: string;
  POLLIE_RATE_LIMIT: RateLimit;
}

interface RateLimit {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

interface ChatMessage {
  role: 'user' | 'model';
  text: string;
}

/**
 * The "lite" alias, deliberately.
 *
 * An earlier version pinned `gemini-2.5-flash` with `thinkingConfig:
 * { thinkingBudget: 0 }` to stop the model reasoning before every "hello".
 * Both halves of that turned out to be wrong: 2.5-flash is no longer served to
 * new API keys at all (404), and `thinkingBudget` is rejected as an invalid
 * argument by every current model. Measured against this key, the lite alias
 * answers in roughly 600ms and full flash in about 1800ms — and Pollie says
 * two short sentences to a four-year-old, which is exactly what lite is for.
 *
 * An alias rather than a version pin, because the pin is what broke: models
 * are retired faster than a toddler app gets rebuilt. Changing it is a deploy,
 * not an app release.
 */
const MODEL = 'gemini-flash-lite-latest';

const SYSTEM_PROMPT = `You are Pollie, a warm, friendly companion who talks to a young child.
Rules:
- Talk like a normal, warm person would: relaxed, casual, natural. Never
  sound like a robot, a script, or a narrator.
- Keep replies short: usually 2-3 sentences, sometimes just one. Use simple
  words a 4-year-old understands.
- Reply in the language named below, always, even if the child mixes in words
  from another one.
- You may use ONE emoji occasionally, but not in every reply and never as
  decoration on every sentence.
- Never use asterisks, roleplay sounds, or *action* markers — just plain
  speech.
- Never mention that you are an AI or a model.
- SAFETY (most important): NEVER discuss sex, dating, romance, violence,
  drugs, death, or anything adult. NEVER use bad words, insults, or slurs.
  If the child says something rude or inappropriate, gently say "That's not
  a nice thing to say!" and change the subject to something fun.
- If the child asks to do something dangerous or unsafe, gently say no and
  suggest a safe, fun alternative instead.
- For stories and songs, keep them very short and sweet.`;

/** Strictest blocking on every category, on the child's input and Pollie's output. */
const SAFETY_SETTINGS = [
  'HARM_CATEGORY_HARASSMENT',
  'HARM_CATEGORY_HATE_SPEECH',
  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
  'HARM_CATEGORY_DANGEROUS_CONTENT',
].map((category) => ({ category, threshold: 'BLOCK_LOW_AND_ABOVE' }));

const GENERATION_CONFIG = {
  temperature: 0.9,
  // Generous for two short sentences, and small enough that the stream ends
  // promptly. No thinkingConfig: current models reject it outright, and lite
  // does not stop to reason before a greeting anyway.
  maxOutputTokens: 200,
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== 'POST') {
      return json({ error: 'method not allowed' }, 405);
    }

    // Every install sends a random id. It identifies nothing about the child —
    // it exists so one user cannot drain the quota everyone shares.
    const installId = request.headers.get('X-Install-Id');
    if (!installId || installId.length < 8 || installId.length > 64) {
      return json({ error: 'missing install id' }, 400);
    }

    const allowed = await env.POLLIE_RATE_LIMIT.limit({ key: installId });
    if (!allowed.success) {
      // Retry-After tells the app this is a pause, not the end of the day.
      return json({ error: 'rate' }, 429, { 'Retry-After': '30' });
    }

    if (url.pathname === '/ping') return ping(env);
    if (url.pathname === '/chat') return chat(request, env);
    return json({ error: 'not found' }, 404);
  },
};

/**
 * Cheapest possible round trip that still proves Gemini answers *and* that the
 * quota is not exhausted — which is exactly what turns Pollie's face from
 * sleeping to smiling, so a mere "the Worker is up" would be a lie.
 */
async function ping(env: Env): Promise<Response> {
  const response = await callGemini(env, 'generateContent', {
    contents: [{ role: 'user', parts: [{ text: 'Reply with just the word: OK' }] }],
    generationConfig: { ...GENERATION_CONFIG, temperature: 0, maxOutputTokens: 20 },
    safetySettings: SAFETY_SETTINGS,
  });

  if (response.status === 429) return rateLimited(response);
  if (!response.ok) return upstreamError(response);

  const body = (await response.json()) as GeminiResponse;
  const text = textOf(body);
  return json({ ok: text.trim().length > 0 });
}

/** Streams the reply back as newline-delimited JSON: one `{"text": "..."}` per line. */
async function chat(request: Request, env: Env): Promise<Response> {
  let messages: ChatMessage[];
  let language = 'en';
  try {
    const body = (await request.json()) as {
      messages: ChatMessage[];
      language?: string;
    };
    messages = body.messages;
    if (body.language === 'id') language = 'id';
  } catch {
    return json({ error: 'bad request' }, 400);
  }
  if (!Array.isArray(messages) || messages.length === 0) {
    return json({ error: 'bad request' }, 400);
  }

  const upstream = await callGemini(env, 'streamGenerateContent?alt=sse', {
    // The SDK used to serialise a system instruction with `role: 'system'`,
    // which this API rejects. `systemInstruction` is the supported field.
    systemInstruction: {
      parts: [
        {
          text:
            SYSTEM_PROMPT +
            (language === 'id'
              ? '\n\nLANGUAGE: reply only in Bahasa Indonesia.'
              : '\n\nLANGUAGE: reply only in English.'),
        },
      ],
    },
    contents: trimHistory(messages).map((m) => ({
      role: m.role === 'model' ? 'model' : 'user',
      parts: [{ text: m.text }],
    })),
    generationConfig: GENERATION_CONFIG,
    safetySettings: SAFETY_SETTINGS,
  });

  if (upstream.status === 429) return rateLimited(upstream);
  if (!upstream.ok) return upstreamError(upstream);
  if (!upstream.body) return json({ error: 'unreachable' }, 502);

  return new Response(toNdjson(upstream.body), {
    headers: {
      'Content-Type': 'application/x-ndjson; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

/**
 * Server-sent events in, one JSON object per line out.
 *
 * The app parses lines, not an SSE dialect — the less protocol the phone has
 * to understand, the less there is to go wrong on a bad connection.
 */
function toNdjson(body: ReadableStream<Uint8Array>): ReadableStream<Uint8Array> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = '';

  return body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split('\n');
        // The last piece may be half a line; keep it for the next chunk.
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          if (!line.startsWith('data:')) continue;
          const payload = line.slice(5).trim();
          if (!payload || payload === '[DONE]') continue;
          try {
            const text = textOf(JSON.parse(payload) as GeminiResponse);
            if (text) {
              controller.enqueue(encoder.encode(JSON.stringify({ text }) + '\n'));
            }
          } catch {
            // A malformed chunk mid-stream is not worth failing the reply over.
          }
        }
      },
    }),
  );
}

interface GeminiResponse {
  candidates?: { content?: { parts?: { text?: string }[] } }[];
}

function textOf(body: GeminiResponse): string {
  return (body.candidates?.[0]?.content?.parts ?? [])
    .map((part) => part.text ?? '')
    .join('');
}

/** The last 20 turns. A toddler chat never needs more, and the request stays small. */
function trimHistory(messages: ChatMessage[]): ChatMessage[] {
  return messages.length <= 20 ? messages : messages.slice(-20);
}

/**
 * Calls Gemini, retrying once when the failure looks temporary.
 *
 * A model that is briefly overloaded (503) or a transient 500 used to surface
 * to the child as "Oops, I got lost" and end the conversation. One quick retry
 * turns most of those into a normal answer.
 */
async function callGemini(
  env: Env,
  method: string,
  body: unknown,
): Promise<Response> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:${method}`;
  const init = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': env.GEMINI_API_KEY,
    },
    body: JSON.stringify(body),
  };

  const first = await fetch(url, init);
  if (first.status < 500) return first;
  await new Promise((resolve) => setTimeout(resolve, 400));
  return fetch(url, init);
}

/**
 * Tells a per-minute limit apart from the day's allowance.
 *
 * Google's free tier caps requests per minute *and* per day, and returns 429
 * for both. Reporting every one of them as "out of words for today" told a
 * child to come back tomorrow when the answer was thirty seconds away. The
 * error body names which limit was hit.
 */
async function rateLimited(response: Response): Promise<Response> {
  let detail = '';
  try {
    detail = await response.text();
  } catch {
    detail = '';
  }
  const daily = /per\s*day|PerDay|RequestsPerDay/i.test(detail);
  return json(
    { error: daily ? 'quota' : 'rate' },
    429,
    { 'Retry-After': daily ? '3600' : '30' },
  );
}

/**
 * Passes Google's own complaint through instead of swallowing it.
 *
 * The first version returned a bare "unreachable" for every upstream failure,
 * which made a misconfigured key indistinguishable from a wrong model name or
 * a network fault — undiagnosable from outside. The app still shows the child
 * a friendly message; this detail is for whoever is reading the response.
 */
async function upstreamError(response: Response): Promise<Response> {
  let detail = '';
  try {
    detail = (await response.text()).slice(0, 500);
  } catch {
    detail = '(no body)';
  }
  return json(
    { error: 'unreachable', upstreamStatus: response.status, detail },
    502,
  );
}

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}
