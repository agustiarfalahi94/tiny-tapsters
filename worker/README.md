# Pollie's proxy

A Cloudflare Worker that holds the Gemini API key so the APK does not.

## Why this exists

`String.fromEnvironment('GEMINI_API_KEY')` compiles the key into `libapp.so` as
a plain string. Anyone who downloads a release APK can run
`strings libapp.so | grep AIza` and have it in seconds — the repo being private
does not help, because the signed APK is attached to public GitHub releases.
Everyone also shared one free-tier quota, so two people using Pollie competed
for it.

With the Worker in front, the app ships only a URL, which is not a secret. The
model, the system prompt and the safety settings all move server-side too, so
changing any of them is a deploy rather than an app release.

## First-time setup

You need a Cloudflare account. The free plan is enough — 100,000 Worker
requests a day, no card required.

1. **Create the account** at <https://dash.cloudflare.com/sign-up>. Confirm the
   email; you do not need to add a domain.

2. **Install the tools and log in.** From this directory:

   ```bash
   npm install
   npx wrangler login
   ```

   That opens a browser to authorise the CLI.

3. **Give the Worker the key.** This is interactive and the key never touches a
   file:

   ```bash
   npx wrangler secret put GEMINI_API_KEY
   ```

   Paste the key at the `Enter a secret value:` prompt. The terminal shows
   nothing as you paste, which is expected.

   Check it landed with `npx wrangler secret list` — the entry must be *named*
   `GEMINI_API_KEY`. If the key itself appears as the name, it was pasted at
   the wrong prompt: secret names are not hidden, so delete that entry and
   redo this step.

4. **Deploy.**

   ```bash
   npx wrangler deploy
   ```

   It prints a URL like `https://pollie.<your-subdomain>.workers.dev`. That is
   what the app needs. The first deploy also asks you to pick a `workers.dev`
   subdomain; that name is public and account-wide.

   The certificate for a brand-new subdomain takes a few minutes to issue, so
   the address can fail to connect at first. That is normal — wait and retry.

5. **Point the app at it.** Build with:

   ```bash
   flutter build apk --release \
     --dart-define=POLLIE_ENDPOINT=https://pollie.<your-subdomain>.workers.dev
   ```

   And set `POLLIE_ENDPOINT` as a repository variable in GitHub so CI does the
   same. `lib/services/pollie_service.dart` also carries the URL as its
   compile-time default, so set it there once and normal builds just work.

6. **Rotate the old key.** Every APK ever released still carries the old one,
   so it must be replaced, not merely retired: create a new key in Google AI
   Studio, put *that* one in the Worker (step 3), then delete the old key.
   Finally delete the `GEMINI_API_KEY` secret from the GitHub repository — CI
   no longer needs it.

## Day to day

```bash
npm run dev        # run it locally against the real Gemini API
npm run typecheck  # tsc --noEmit
npm run deploy     # ship it
npx wrangler tail  # live logs from the deployed Worker
```

## What it exposes

Both endpoints are `POST` and both require an `X-Install-Id` header — a random
UUID the app generates. It identifies nothing about the child; it exists only
so the rate limiter can tell two installs apart.

| Route | Purpose |
|---|---|
| `/ping` | One cheap generation. Proves Gemini answers *and* that quota remains — this is what turns Pollie's face from 😴 to 😊, so it cannot just report that the Worker is up. |
| `/chat` | Takes `{ messages: [{ role, text }] }`, streams the reply back as newline-delimited JSON, one `{"text": "..."}` per line. |

Over a limit both return `429`, and the body says *which* limit was hit:

| Body | Meaning | `Retry-After` |
|---|---|---|
| `{"error":"rate"}` | a per-minute cap — ours, or Google's | `30` |
| `{"error":"quota"}` | Google's response named a per-*day* limit | `3600` |

Only the second is Pollie being out of words for the day. Reporting every 429
that way told a child to come back tomorrow when the answer was thirty seconds
away, which is why `rateLimited()` reads Google's error body before deciding
(the `rateLimited()` function in `src/index.ts`).

## Model updates and recovery

`src/index.ts` owns the HTTP handlers, prompt, safety settings and
newline-delimited JSON protocol. `src/gemini.ts` owns model selection,
stable-model discovery, catalog caching and upstream request/stream deadlines.

`GEMINI_MODEL` is an optional Worker variable; the default is
`gemini-flash-lite-latest`. Google updates this
[alias](https://ai.google.dev/gemini-api/docs/models#latest) server-side, and it
may move to stable, preview, or experimental versions. Pollie keeps its prompt,
strict safety settings, and short output limit on every model attempt.

On `404`, `503`, or a timeout before headers, the Worker discovers compatible stable text-generation
Flash-Lite models from Google's Models API. It tries at most two distinct
alternatives, newest numeric version first, with a one-hour catalog cache.
Preview, full Flash, image, audio, and live models are excluded from fallback.
Discovery shares in-flight lookups; a fallback `404` refreshes the catalog once
within the same retry budget. Catalog membership does not guarantee access; generation attempts remain
bounded. Quota, invalid-key, and bad-request responses do not rotate models.
Streaming is only retried before any response is forwarded to the app.
The budget is 12 seconds per header attempt, five seconds total for catalog
discovery, and 35 seconds overall. A timeout may still consume provider quota;
the three-attempt cap also covers these failures.

Requests omit deprecated sampling parameters. Thought parts are excluded from
text and spoken output. API changes, quota exhaustion, and credentials still
need operator attention: no automatic selector can guarantee compatibility with
every future API revision. Review Google's
[migration guide](https://ai.google.dev/gemini-api/docs/generate-content/latest-model)
and [deprecations](https://ai.google.dev/gemini-api/docs/deprecations).

Run `npm test` and `npm run typecheck` before `npm run deploy`. The weekly
**Gemini health** GitHub workflow validates live `/ping` and streamed `/chat`
using a synthetic greeting, or run `node tool/gemini_health.mjs`. It needs no
Gemini secret in GitHub and spends two generation requests per run. Action
failures use your GitHub notification settings.

For rollback, set `GEMINI_MODEL` to a known working Flash-Lite version and
redeploy, or use `npx wrangler rollback` to restore the previous deployment.
Worker deployment and publishing an APK are separate steps.

## Historical notes

- The model is `gemini-flash-lite-latest`. An earlier version pinned
  `gemini-2.5-flash` with `thinkingConfig: { thinkingBudget: 0 }`; both halves
  failed for the key/configuration tested at the time. Model availability and
  thinking controls vary by model; do not treat that observation as a rule
  for every current model. In August 2026, lite answered in about 600 ms and full flash in
  about 1800 ms — and Pollie says two short sentences to a four-year-old.
- An alias, not a version pin, because the pin is exactly what broke: models
  are retired faster than a toddler app gets rebuilt.
- Upstream failures return the status and message Google gave, not a bare
  "unreachable". The first version swallowed them, which made a misconfigured
  key indistinguishable from a retired model.
- Cloudflare's bot protection rejects requests whose client looks automated
  with error 1010. The app sends its own `User-Agent` so it never trips this.
- `KidSafety` still guards input and output *in the app*. The Worker is not a
  replacement for it — a proxy the app trusts is not the same as a guard the
  child is behind.
