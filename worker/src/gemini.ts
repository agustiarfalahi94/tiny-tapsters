interface GeminiEnv {
  GEMINI_API_KEY: string;
  GEMINI_MODEL?: string;
}

const MODELS_URL = 'https://generativelanguage.googleapis.com/v1beta/models';
const DEFAULT_MODEL = 'gemini-flash-lite-latest';
const REQUEST_TIMEOUT_MS = 35_000;
const HEADER_TIMEOUT_MS = 12_000;
const CATALOG_TIMEOUT_MS = 5_000;
const CATALOG_TTL_MS = 60 * 60 * 1000;
const MAX_CATALOG_PAGES = 3;
const MAX_CACHE_KEYS = 8;
const STABLE_LITE = /^models\/(gemini-(\d+(?:\.\d+)*)-flash-lite(?:-(\d+))?)$/;

interface CatalogEntry {
  expiresAt: number;
  models: Promise<string[]>;
}

// Hashes isolate key rotations without retaining the API key in cache identifiers.
const catalogCache = new Map<string, CatalogEntry>();

export async function callGemini(
  env: GeminiEnv,
  method: string,
  body: unknown,
): Promise<Response> {
  const deadline = Date.now() + REQUEST_TIMEOUT_MS;
  const preferred = (env.GEMINI_MODEL?.trim() || DEFAULT_MODEL).replace(/^models\//, '');
  const init: RequestInit = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': env.GEMINI_API_KEY,
    },
    body: JSON.stringify(body),
  };
  const generate = (model: string) => timedFetch(
    `${MODELS_URL}/${encodeURIComponent(model)}:${method}`, init, deadline,
  );

  let response = await generate(preferred);
  if (!canFallback(response)) return response;

  let alternatives = await availableModels(env.GEMINI_API_KEY, deadline);
  const tried = new Set([preferred]);
  let refreshed = false;
  for (let attempt = 1; attempt < 3; attempt++) {
    const model = alternatives.find(candidate => !tried.has(candidate));
    if (!model) break;
    if (Date.now() >= deadline) break;
    await response.body?.cancel().catch(() => {});
    tried.add(model);
    response = await generate(model);
    // A successful stream is handed to the caller once, even if it later fails.
    if (!canFallback(response)) break;
    if (response.status === 404 && !refreshed && attempt < 2) {
      refreshed = true;
      alternatives = await availableModels(env.GEMINI_API_KEY, deadline, true);
    }
  }
  return response;
}

function canFallback(response: Response): boolean {
  return response.status === 404 || response.status === 503;
}

async function availableModels(apiKey: string, requestDeadline: number, refresh = false): Promise<string[]> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(apiKey));
  const cacheKey = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  const now = Date.now();
  if (refresh) catalogCache.delete(cacheKey);
  for (const [key, entry] of catalogCache) {
    if (entry.expiresAt <= now) catalogCache.delete(key);
  }
  let entry = catalogCache.get(cacheKey);
  if (!entry) {
    if (catalogCache.size >= MAX_CACHE_KEYS) {
      catalogCache.delete(catalogCache.keys().next().value!);
    }
    entry = {
      expiresAt: now + CATALOG_TTL_MS,
      models: listModels(apiKey, Math.min(requestDeadline, now + CATALOG_TIMEOUT_MS)),
    };
    catalogCache.set(cacheKey, entry);
  }
  try {
    return await entry.models;
  } catch {
    if (catalogCache.get(cacheKey) === entry) catalogCache.delete(cacheKey);
    return [];
  }
}

async function listModels(apiKey: string, deadline: number): Promise<string[]> {
  const versions = new Map<string, number[]>();
  const seenTokens = new Set<string>();
  let pageToken = '';
  for (let page = 0; page < MAX_CATALOG_PAGES; page++) {
    const url = new URL(MODELS_URL);
    url.searchParams.set('pageSize', '1000');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await timedFetch(url.toString(), {
      method: 'GET', headers: { 'x-goog-api-key': apiKey },
    }, deadline);
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error('Gemini catalog unavailable');
    }
    const body = await response.json() as {
      models?: { name?: string; supportedGenerationMethods?: string[] }[];
      nextPageToken?: string;
    };
    if (!Array.isArray(body.models)) throw new Error('Invalid Gemini catalog');
    for (const model of body.models) {
      const match = typeof model?.name === 'string' ? STABLE_LITE.exec(model.name) : null;
      if (!match || !Array.isArray(model.supportedGenerationMethods)
        || !model.supportedGenerationMethods.includes('generateContent')) continue;
      versions.set(match[1], [...match[2].split('.').map(Number), Number(match[3] ?? 0)]);
    }
    pageToken = typeof body.nextPageToken === 'string' ? body.nextPageToken : '';
    if (!pageToken || seenTokens.has(pageToken)) break;
    seenTokens.add(pageToken);
  }
  return [...versions.keys()].sort((left, right) => {
    const a = versions.get(left)!;
    const b = versions.get(right)!;
    for (let index = 0; index < Math.max(a.length, b.length); index++) {
      const difference = (b[index] ?? 0) - (a[index] ?? 0);
      if (difference) return difference;
    }
    return left.localeCompare(right);
  });
}

// Keep the deadline alive through body reads; fetch alone stops waiting at headers.
async function timedFetch(url: string, init: RequestInit, deadline: number): Promise<Response> {
  if (Date.now() >= deadline) return new Response('Gemini request timed out', { status: 503 });
  const abort = new AbortController();
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let output: ReadableStreamDefaultController<Uint8Array> | undefined;
  let finished = false;
  const timeout = () => {
    if (finished) return;
    finished = true;
    abort.abort();
    output?.error(new Error('Gemini request timed out'));
    void reader?.cancel().catch(() => {});
  };
  let timer = setTimeout(timeout, Math.min(HEADER_TIMEOUT_MS, deadline - Date.now()));
  const finish = () => { finished = true; clearTimeout(timer); };

  try {
    const response = await fetch(url, { ...init, signal: abort.signal });
    clearTimeout(timer);
    if (finished) {
      void response.body?.cancel().catch(() => {});
      return new Response('Gemini request timed out', { status: 503 });
    }
    if (!response.body) { finish(); return response; }
    reader = response.body.getReader();
    timer = setTimeout(timeout, Math.max(0, deadline - Date.now()));
    const body = new ReadableStream<Uint8Array>({
      start(controller) { output = controller; },
      async pull(controller) {
        try {
          const chunk = await reader!.read();
          if (finished) return;
          if (chunk.done) { finish(); controller.close(); }
          else controller.enqueue(chunk.value);
        } catch {
          if (finished) return;
          finish();
          controller.error(new Error('Gemini stream interrupted'));
        }
      },
      async cancel(reason) {
        finish();
        abort.abort();
        await reader!.cancel(reason);
      },
    });
    return new Response(body, {
      status: response.status, statusText: response.statusText, headers: response.headers,
    });
  } catch (error) {
    finish();
    const timedOut = abort.signal.aborted || (error instanceof Error && error.name === 'AbortError');
    return new Response(timedOut ? 'Gemini request timed out' : 'Gemini request failed', {
      status: timedOut ? 503 : 502,
    });
  }
}
