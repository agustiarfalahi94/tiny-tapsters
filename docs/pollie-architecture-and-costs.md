# Pollie: architecture, limits, costs and the decisions behind them

Written 2026-08-11. This exists so the same questions do not have to be
re-researched. Prices and model names age; the reasoning does not.

## How it works, and what it replaced

**Before.** The Gemini key was compiled into the APK via `--dart-define`, and
every installed copy called Google directly.

```
  Your phone   🔑 ──▶ Gemini
  Friend's     🔑 ──▶ Gemini      the same key, inside every copy
  Stranger's   🔑 ──▶ Gemini
```

`strings libapp.so | grep AIza` recovers a dart-defined key in seconds, and the
signed APK is attached to public GitHub releases — so the private repo never
protected it. The author's phone was **never** part of this; it was not a
server and no traffic passed through it.

**Now.** Every copy talks to a Cloudflare Worker, which holds the key.

```
  any phone ──▶ Worker (🔑, rate limit, prompt, safety) ──▶ Gemini
```

The app ships only a URL, which is not a secret. The model, system prompt and
safety settings live server-side, so changing any of them is a deploy rather
than a release everyone has to install.

## The key is still one key

Cloudflare cannot issue Gemini keys — only Google can, to *accounts*. There is
no mechanism, at any provider, to mint a key for a stranger who installed your
app. Per-user *keys* are not a thing; per-user *allowances* are, and that is
what the rate limiter approximates.

If one key's quota is ever genuinely exhausted, the answer is several projects
**you** own, pooled inside the Worker — not keys handed to users.

## Limits, as measured

| Limit | Value | Whose |
|---|---|---|
| Worker rate limit | 120 requests/minute per install id | ours, `wrangler.toml` |
| Gemini free tier | ~15–17 requests/minute, ~1,000/day, **shared by all users** | Google's |

Measured by hammering `/ping`: the 18th request inside a minute was refused.
Google's ceiling is the binding one, and ours never fires. Hitting it is what
makes Pollie say "let me catch my breath".

**Changing `limit` in `wrangler.toml` alone does nothing** — the binding keeps
the configuration it was created with. Bump `namespace_id` too.

## Costs

About **$0.00024 per message** (~600 input tokens of prompt and history, ~60
output tokens of reply).

| Users | Messages/day | Cost/month |
|---|---|---|
| One family | 100 | ~$0.70 |
| 10 | 1,000 | ~$7 |
| 100 | 5,000 | ~$35 |
| 100,000 (10% daily, 20 msgs) | 200,000 | ~$1,400 |

At 100k users the constraint is money, not keys. Levers, in order: enable
billing (removes the free-tier ceiling), per-install daily allowance, context
caching for the resent system prompt, then a business decision.

## Why Gemini and not something cheaper

DeepSeek, Qwen and Xiaomi's MiMo are all cheaper. None of them documents what
Gemini gives us: **per-request, developer-set safety thresholds** across
harassment, hate speech, sexual content and dangerous content. The app sets all
four to the strictest level, and that is the main reason an unsupervised
four-year-old may use it.

- **DeepSeek** — cheapest, but reviews describe its moderation as weak, and its
  own privacy policy says the service is not aimed at children and is not
  designed to process children's data. Traffic also goes to servers in China,
  which sits badly with this app's no-tracking promise.
- **Qwen** — documentation covers models and keys; safety is Alibaba's platform
  policy, not a dial we control.
- **MiMo** — pricing and benchmarks are published; no safety filtering
  documentation was found at all.

"Not documented" is not "unsafe", but it does mean trusting an unknown filter
and being unable to turn it up. The saving at family scale is pennies a month.

`KidSafety` still guards input and output in the app, independently of the
provider — but it is a word list, not a substitute.

## Model choice

`gemini-flash-lite-latest`, an **alias, not a pin**.

An earlier version pinned `gemini-2.5-flash` with
`thinkingConfig: { thinkingBudget: 0 }`. Both halves were wrong: that model is
no longer served to new API keys (404), and `thinkingBudget` is rejected as an
invalid argument by every current model. Everything failed until this was
found — which took the Worker being changed to report Google's actual error
instead of a bare "unreachable".

Measured on a real key: lite answers in ~600 ms, full flash in ~1800 ms.

Retirement matters. `gemini-2.5-flash-lite` retires 16 October 2026; the
successor is roughly 2.5× the input and 4× the output price. The alias follows
automatically, so the price changes without any code change.

## Charging users, if it ever comes to that

Cost is not the driver — even a heavy child costs about $0.22/month. Options:

- **One-time unlock, $2–4.** Best fit: covers years, no subscription to resent.
- **Free with a daily cap.** Simplest, costs little.
- **Subscription $1–2/month.** More revenue, poor fit for a small kids' app.

The real work is not the price: it is Google Play (developer account, billing,
tax, privacy policy). Today the app is handed around as an APK file.

## The install id, and why it is not persistent

Each launch generates a random id, sent to the Worker so the rate limiter can
tell installs apart. It identifies nothing about the child and is not stored.

Making it survive restarts was considered and **rejected for family use**:

- The app currently writes **nothing** to the device — an unusually clean
  property, and easy to state truthfully.
- A permanent random id on a child's device is a tracking identifier, treated
  as personal data of a child under COPPA and GDPR, and would have to be
  disclosed if the app is ever published.
- It needs a storage dependency the project has otherwise declined.
- It does not even work as a control: reinstalling or clearing data resets it.

It becomes necessary only if the app goes public and someone is paying per
message — and even then it is a soft control.
