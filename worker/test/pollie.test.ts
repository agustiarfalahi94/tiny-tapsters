import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/index';

const API = 'https://generativelanguage.googleapis.com/v1beta/models';
const ALIAS = 'gemini-flash-lite-latest';
const HOUR = 60 * 60 * 1000;
type Part = { text?: string; thought?: boolean };
type Call = { url: URL; init: RequestInit };

function reply(parts: Part[] = [{ text: 'OK' }], modelVersion = 'gemini-3.5-flash-lite') {
  return { candidates: [{ content: { parts }, finishReason: 'STOP' }], modelVersion };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status });
}

function catalog(names: string[], nextPageToken?: string) {
  return json({
    models: names.map((name) => ({ name: `models/${name}`, supportedGenerationMethods: ['generateContent'] })),
    nextPageToken,
  });
}

function sse(body: unknown) {
  return new Response(`data: ${JSON.stringify(body)}\n\ndata: [DONE]\n\n`, {
    headers: { 'Content-Type': 'text/event-stream' },
  });
}

describe('Pollie Gemini resilience', () => {
  let worker: (typeof import('../src/index'))['default'];
  let env: Env;
  let calls: Call[];

  beforeEach(async () => {
    vi.resetModules();
    worker = (await import('../src/index')).default;
    env = { GEMINI_API_KEY: 'test-key-a', POLLIE_RATE_LIMIT: { limit: async () => ({ success: true }) } };
    calls = [];
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  function upstream(handler: (call: Call) => Response | Promise<Response>) {
    vi.stubGlobal('fetch', async (input: string | URL | Request, init: RequestInit = {}) => {
      const call = { url: new URL(String(input)), init };
      calls.push(call);
      return handler(call);
    });
  }

  function request(path = '/ping', body: unknown = {}) {
    return worker.fetch(new Request(`https://pollie.test${path}`, {
      method: 'POST', headers: { 'X-Install-Id': 'test-install-id' }, body: JSON.stringify(body),
    }), env);
  }

  function generations() {
    return calls.filter((call) => call.init.method === 'POST');
  }

  function models() {
    return generations().map((call) => call.url.pathname.split('/').pop()!.split(':')[0]);
  }

  function lists() {
    return calls.filter((call) => call.url.pathname === '/v1beta/models');
  }

  it('refreshes a retired cached model and finds its replacement within three attempts', async () => {
    let retired = false;
    upstream(({ url, init }) => {
      if (init.method !== 'POST') return catalog([retired ? 'gemini-3.9-flash-lite' : 'gemini-3.5-flash-lite']);
      if (url.pathname.includes(ALIAS) || (retired && url.pathname.includes('3.5-flash-lite'))) return json({}, 404);
      return json(reply());
    });
    expect(await (await request()).json()).toEqual({ ok: true });
    retired = true;
    expect(await (await request()).json()).toEqual({ ok: true });
    expect(lists()).toHaveLength(2);
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite', ALIAS,
      'gemini-3.5-flash-lite', 'gemini-3.9-flash-lite']);
  });

  it('uses the moving Lite alias without catalog traffic on success', async () => {
    upstream(() => json(reply()));
    expect(await (await request()).json()).toEqual({ ok: true });
    expect(models()).toEqual([ALIAS]);
    expect(lists()).toHaveLength(0);
    expect(generations()[0].url.search).toBe('');
    expect(new Headers(generations()[0].init.headers).get('x-goog-api-key')).toBe('test-key-a');
  });

  it('discovers on 404 and ranks only stable text Lite models numerically across pages', async () => {
    upstream(({ url, init }) => {
      if (init.method === 'POST') return url.pathname.includes(ALIAS) ? json({ error: 'missing' }, 404) : json(reply());
      if (!url.searchParams.has('pageToken')) return catalog([
        'gemini-3.9-flash-lite', 'gemini-3.8-flash-lite-preview', 'gemini-20-flash',
        'gemini-30-flash-lite-tts', 'gemini-30-flash-lite-image', 'gemini-30-flash-lite-live',
        'gemini-30-flash-lite-experimental', 'gemini-30-flash-lite-exp', ALIAS,
      ], 'page & two');
      return json({ models: [
        { name: 'models/gemini-3.10-flash-lite', supportedGenerationMethods: ['generateContent'] },
        { name: 'models/gemini-40-flash-lite', supportedGenerationMethods: ['embedContent'] },
        { name: 'models/gemini-50-flash-lite' },
      ] });
    });
    expect(await (await request()).json()).toEqual({ ok: true });
    expect(models()).toEqual([ALIAS, 'gemini-3.10-flash-lite']);
    expect(lists().map((call) => call.url.searchParams.get('pageToken'))).toEqual([null, 'page & two']);
    for (const call of lists()) {
      expect(call.url.origin + call.url.pathname).toBe(API);
      expect(call.url.searchParams.get('pageSize')).toBe('1000');
      expect(call.url.searchParams.has('key')).toBe(false);
      expect(new Headers(call.init.headers).get('x-goog-api-key')).toBe('test-key-a');
    }
  });

  it('uses a distinct stable Lite model on 503', async () => {
    upstream(({ init, url }) => init.method !== 'POST' ? catalog(['gemini-3.5-flash-lite'])
      : url.pathname.includes(ALIAS) ? json({ error: 'overloaded' }, 503) : json(reply()));
    expect(await (await request()).json()).toEqual({ ok: true });
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite']);
  });

  it('still falls back when an overloaded model has an unreadable error body', async () => {
    upstream(({ init, url }) => {
      if (init.method !== 'POST') return catalog(['gemini-3.5-flash-lite']);
      if (!url.pathname.includes(ALIAS)) return json(reply());
      return new Response(new ReadableStream<Uint8Array>({
        start(controller) { controller.error(new Error('error body interrupted')); },
      }), { status: 503 });
    });
    expect(await (await request()).json()).toEqual({ ok: true });
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite']);
  });

  it('caps generation at three distinct models including a configured preferred model', async () => {
    env = { ...env, GEMINI_MODEL: 'gemini-3.10-flash-lite' } as Env;
    upstream(({ init }) => init.method === 'POST' ? json({ error: 'overloaded' }, 503)
      : catalog(['gemini-3.10-flash-lite', 'gemini-3.9-flash-lite', 'gemini-3.9-flash-lite', 'gemini-3.5-flash-lite', 'gemini-2.5-flash-lite']));
    expect(await (await request()).json()).toMatchObject({ error: 'unreachable', upstreamStatus: 503 });
    expect(models()).toEqual(['gemini-3.10-flash-lite', 'gemini-3.9-flash-lite', 'gemini-3.5-flash-lite']);
    expect(lists()).toHaveLength(1);
  });

  it.each([
    ['RequestsPerDay', 'quota', '3600'], ['requests per minute', 'rate', '30'],
  ])('keeps 429 %s mapping without retries or discovery', async (detail, error, retryAfter) => {
    upstream(() => json({ error: detail }, 429));
    const response = await request();
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe(retryAfter);
    expect(await response.json()).toEqual({ error });
    expect(calls).toHaveLength(1);
  });

  it.each([400, 401, 403, 500])('does not retry upstream %s', async (status) => {
    upstream(() => json({ error: 'rejected' }, status));
    expect(await (await request()).json()).toMatchObject({ error: 'unreachable', upstreamStatus: status });
    expect(calls).toHaveLength(1);
  });

  it.each([400, 401, 403, 429])('stops if a fallback returns %s', async (status) => {
    upstream(({ url, init }) => init.method !== 'POST' ? catalog(['gemini-3.5-flash-lite', 'gemini-2.5-flash-lite'])
      : url.pathname.includes(ALIAS) ? json({}, 404) : json({ error: 'rejected' }, status));
    await (await request()).text();
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite']);
  });

  it('caches discovery for one hour and isolates API keys', async () => {
    vi.useFakeTimers();
    upstream(({ url, init }) => init.method !== 'POST' ? catalog(['gemini-3.5-flash-lite'])
      : url.pathname.includes(ALIAS) ? json({}, 404) : json(reply()));
    for (const elapsed of [0, HOUR - 1]) {
      vi.setSystemTime(elapsed);
      expect(await (await request()).json()).toEqual({ ok: true });
    }
    expect(lists()).toHaveLength(1);
    env.GEMINI_API_KEY = 'test-key-b';
    await (await request()).text();
    expect(lists()).toHaveLength(2);
    env.GEMINI_API_KEY = 'test-key-a';
    vi.setSystemTime(HOUR);
    await (await request()).text();
    expect(lists()).toHaveLength(3);
  });

  it('caps each catalog lookup at three pages, including one forced refresh', async () => {
    upstream(({ init }) => init.method === 'POST' ? json({}, 404)
      : catalog(['gemini-3.5-flash-lite'], `page-${lists().length}`));
    await (await request()).text();
    expect(lists()).toHaveLength(6);
    expect(generations()).toHaveLength(2);
  });

  it('stops catalog pagination when a token repeats', async () => {
    upstream(({ init }) => init.method === 'POST' ? json({}, 404) : catalog([], 'same-token'));
    await (await request()).text();
    expect(lists()).toHaveLength(2);
    expect(generations()).toHaveLength(1);
  });

  it('preserves the original failure when no eligible Lite model exists', async () => {
    upstream(({ init }) => init.method === 'POST' ? json({ error: 'missing preferred' }, 404)
      : catalog(['gemini-3.8-flash', 'gemini-3.8-flash-lite-preview', 'gemini-3.8-flash-lite-tts']));
    expect(await (await request()).json()).toMatchObject({ upstreamStatus: 404, detail: '{"error":"missing preferred"}' });
    expect(models()).toEqual([ALIAS]);
  });

  it('does not cache failed catalog requests or retry catalog authorization failures', async () => {
    upstream(({ init }) => init.method === 'POST' ? json({}, 404) : json({}, 403));
    await (await request()).text();
    await (await request()).text();
    expect(lists()).toHaveLength(2);
    expect(models()).toEqual([ALIAS, ALIAS]);
  });

  it('preserves chat safety, prompt, language, history, and NDJSON through both fallbacks', async () => {
    upstream(({ init }) => {
      if (init.method !== 'POST') return catalog(['gemini-3.10-flash-lite', 'gemini-3.5-flash-lite']);
      return generations().length < 3 ? json({}, generations().length === 1 ? 404 : 503)
        : sse(reply([{ thought: true, text: 'Private reasoning' }, { text: 'Hai! 🦜' }], 'gemini-3.5-flash-lite'));
    });
    const messages = Array.from({ length: 22 }, (_, index) => ({ role: index % 2 ? 'model' : 'user', text: `turn ${index}` }));
    const response = await request('/chat', { language: 'id', messages });
    expect(response.headers.get('Content-Type')).toBe('application/x-ndjson; charset=utf-8');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(await response.text()).toBe('{"text":"Hai! 🦜"}\n');
    expect(models()).toEqual([ALIAS, 'gemini-3.10-flash-lite', 'gemini-3.5-flash-lite']);
    const bodies = generations().map((call) => JSON.parse(call.init.body as string));
    expect(bodies[1]).toEqual(bodies[0]);
    expect(bodies[2]).toEqual(bodies[0]);
    expect(bodies[0].safetySettings).toEqual([
      { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_LOW_AND_ABOVE' },
      { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_LOW_AND_ABOVE' },
      { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_LOW_AND_ABOVE' },
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_LOW_AND_ABOVE' },
    ]);
    expect(bodies[0].systemInstruction.parts[0].text).toContain('NEVER discuss sex, dating, romance, violence,');
    expect(bodies[0].systemInstruction.parts[0].text).toContain('LANGUAGE: reply only in Bahasa Indonesia.');
    expect(bodies[0].generationConfig).toEqual({ maxOutputTokens: 200 });
    expect(bodies[0].contents).toHaveLength(20);
    expect(bodies[0].contents[0]).toEqual({ role: 'user', parts: [{ text: 'turn 2' }] });
    expect(generations().every((call) => call.url.search === '?alt=sse')).toBe(true);
  });

  it('keeps the ping token cap and safety settings without sampling or thinking config', async () => {
    upstream(() => json(reply()));
    await (await request()).text();
    const body = JSON.parse(generations()[0].init.body as string);
    expect(body.generationConfig).toEqual({ maxOutputTokens: 20 });
    expect(body.safetySettings).toHaveLength(4);
    expect(body.safetySettings.every((setting: { threshold: string }) => setting.threshold === 'BLOCK_LOW_AND_ABOVE')).toBe(true);
  });

  it('does not count thought-only ping output as an answer', async () => {
    upstream(() => json(reply([{ thought: true, text: 'Reasoning only' }])));
    expect(await (await request()).json()).toEqual({ ok: false });
  });

  it('returns unreachable when a ping body fails after headers without retrying or exposing details', async () => {
    upstream(() => new Response(new ReadableStream<Uint8Array>({
      start(controller) { controller.error(new Error('test-key-a body interrupted')); },
    })));
    const response = await request();
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: 'unreachable' });
    expect(calls).toHaveLength(1);
  });

  it('preserves the empty safety reason and does not retry a successful thought-only stream', async () => {
    upstream(() => sse({ ...reply([{ thought: true, text: 'Reasoning only' }]), promptFeedback: { blockReason: 'SAFETY' } }));
    expect(await (await request('/chat', { messages: [{ role: 'user', text: 'Hello' }] })).text())
      .toBe('{"empty":true,"reason":"prompt:SAFETY"}\n');
    expect(calls).toHaveLength(1);
  });

  it('never retries after spoken text has started streaming', async () => {
    let source!: ReadableStreamDefaultController<Uint8Array>;
    upstream(() => new Response(new ReadableStream<Uint8Array>({ start(controller) { source = controller; } })));
    const response = await request('/chat', { messages: [{ role: 'user', text: 'Hello' }] });
    const reader = response.body!.getReader();
    source.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(reply([{ text: 'Hello!' }]))}\n\n`));
    expect(new TextDecoder().decode((await reader.read()).value)).toBe('{"text":"Hello!"}\n');
    source.error(new Error('stream interrupted'));
    await expect(reader.read()).rejects.toThrow('stream interrupted');
    expect(calls).toHaveLength(1);
  });

  it('recovers from a 12-second header timeout using a distinct stable Lite model', async () => {
    vi.useFakeTimers();
    upstream(({ init }) => {
      if (init.method !== 'POST') return catalog(['gemini-3.5-flash-lite']);
      if (generations().length > 1) return json(reply());
      return new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(new Error('test-key-a should never reach the client')));
      });
    });
    const pending = request();
    await vi.waitFor(() => expect(calls).toHaveLength(1));
    await vi.advanceTimersByTimeAsync(12_000);
    const response = await pending;
    expect(await response.json()).toEqual({ ok: true });
    expect(calls[0].init.signal?.aborted).toBe(true);
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite']);
    expect(lists()).toHaveLength(1);
  });

  it('reports a header timeout without exposing fetch errors if discovery has no alternatives', async () => {
    upstream(({ init }) => {
      if (init.method !== 'POST') return catalog([]);
      throw new DOMException('test-key-a must not reach the client', 'AbortError');
    });
    const response = await request();
    expect(await response.json()).toEqual({ error: 'unreachable', upstreamStatus: 503, detail: 'Gemini request timed out' });
    expect(models()).toEqual([ALIAS]);
    expect(lists()).toHaveLength(1);
  });

  it('does not retry non-timeout network errors or expose their details', async () => {
    upstream(() => { throw new Error('test-key-a connection failed'); });
    expect(await (await request()).json()).toEqual({ error: 'unreachable', upstreamStatus: 502, detail: 'Gemini request failed' });
    expect(calls).toHaveLength(1);
  });

  it('bounds catalog body reads to five seconds and keeps the original model failure', async () => {
    vi.useFakeTimers();
    upstream(({ init }) => init.method === 'POST' ? json({ error: 'missing preferred' }, 404)
      : new Response(new ReadableStream<Uint8Array>()));
    const pending = request();
    await vi.waitFor(() => expect(lists()).toHaveLength(1));
    await vi.advanceTimersByTimeAsync(5_000);
    expect(await (await pending).json()).toMatchObject({ upstreamStatus: 404, detail: '{"error":"missing preferred"}' });
    expect(lists()[0].init.signal?.aborted).toBe(true);
    expect(generations()).toHaveLength(1);
  });

  it('caps the whole request at 35 seconds even when all three models are slow', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    let startedAt = 0;
    upstream(({ init }) => new Promise((resolve, reject) => {
      if (calls.length === 1) startedAt = Date.now();
      const delay = init.method === 'POST' ? 11_000 : 4_000;
      const timer = setTimeout(() => resolve(init.method === 'POST' ? json({}, 503)
        : catalog(['gemini-3.5-flash-lite', 'gemini-2.5-flash-lite'])), delay);
      init.signal?.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('aborted')); });
    }));
    const pending = request();
    await vi.waitFor(() => expect(calls).toHaveLength(1));
    await vi.advanceTimersByTimeAsync(11_000);
    await vi.waitFor(() => expect(lists()).toHaveLength(1));
    await vi.advanceTimersByTimeAsync(4_000);
    await vi.waitFor(() => expect(generations()).toHaveLength(2));
    await vi.advanceTimersByTimeAsync(11_000);
    await vi.waitFor(() => expect(generations()).toHaveLength(3));
    await vi.advanceTimersByTimeAsync(35_000 - (Date.now() - startedAt));
    expect(await (await pending).json()).toMatchObject({ upstreamStatus: 503, detail: 'Gemini request timed out' });
    expect(Date.now() - startedAt).toBe(35_000);
    expect(models()).toEqual([ALIAS, 'gemini-3.5-flash-lite', 'gemini-2.5-flash-lite']);
    expect(generations()[2].init.signal?.aborted).toBe(true);
  });

  it('bounds an already-started stream to the total deadline without another generation', async () => {
    vi.useFakeTimers();
    upstream(() => new Response(new ReadableStream<Uint8Array>()));
    const response = await request('/chat', { messages: [{ role: 'user', text: 'Hello' }] });
    const body = response.text();
    const failed = expect(body).rejects.toThrow('Gemini request timed out');
    await vi.advanceTimersByTimeAsync(35_000);
    await failed;
    expect(calls).toHaveLength(1);
    expect(calls[0].init.signal?.aborted).toBe(true);
  });

  it('keeps local rate limiting ahead of all upstream traffic', async () => {
    env.POLLIE_RATE_LIMIT.limit = async () => ({ success: false });
    upstream(() => json(reply()));
    const response = await request();
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('30');
    expect(await response.json()).toEqual({ error: 'rate' });
    expect(calls).toHaveLength(0);
  });
});
