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
(`src/index.ts:287-305`).

## Notes

- The model is `gemini-flash-lite-latest`. An earlier version pinned
  `gemini-2.5-flash` with `thinkingConfig: { thinkingBudget: 0 }`; both halves
  were wrong. 2.5-flash is no longer served to new API keys at all, and
  `thinkingBudget` is rejected as an invalid argument by every current model.
  Measured against a real key, lite answers in about 600 ms and full flash in
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
