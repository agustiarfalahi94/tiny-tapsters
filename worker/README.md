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

   Paste the key when prompted.

4. **Deploy.**

   ```bash
   npx wrangler deploy
   ```

   It prints a URL like `https://pollie.<your-subdomain>.workers.dev`. That is
   what the app needs.

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

Over the rate limit, both return `429 {"error":"quota"}`, which the app already
shows as Pollie being out of words for the day.

## Notes

- The model is pinned to `gemini-2.5-flash` with `thinkingBudget: 0`. Thinking
  cannot be disabled on 3.x Flash, so the `gemini-flash-latest` alias would
  quietly start paying for a reasoning pass before every "hello" the day it
  moved on. Changing the pin is a one-line edit here.
- `KidSafety` still guards input and output *in the app*. The Worker is not a
  replacement for it — a proxy the app trusts is not the same as a guard the
  child is behind.
