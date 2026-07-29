# 12 — Networking conventions spec (idempotency, retry, timeout, revalidation)

World-convention networking, defined once in the contract, implemented identically on
iOS/Android/Aurora. Closes the confirmed gap ([04](04-benchmark-and-docs.md) §B2): today
`grep` finds zero `idempotency/retry/backoff/timeout/etag` anywhere, and the `request`
(mutations) + `saveFile` actions are unimplemented on every platform.

> Serves "ideal client assembly": a mutation is never double-applied, a flaky network
> degrades gracefully, and a request never hangs forever.

---

## 1. Per-source transport policy (contract)

```jsonc
{
  "source": { "id": "cart", "url": "/cart", "method": "POST",
    "net": {
      "timeoutMs": 10000,               // overall deadline
      "connectTimeoutMs": 4000,
      "retry": { "max": 3, "backoff": "exponential", "baseMs": 200, "jitter": true,
                 "retryOn": ["network", "5xx", "429"] },
      "idempotencyKey": "auto",         // "auto" (client UUID, stable across retries) | "$binding" | omitted
      "revalidate": "etag"              // ties to the cache hash (11)
    } }
}
```

- **Idempotency-Key**: for any mutating `request`, the client generates a UUID **once**
  and reuses it across every retry of that logical operation, sent as an
  `Idempotency-Key` header (Stripe/RFC-draft convention). A retried POST therefore never
  double-charges / double-submits. `auto` is the default for non-GET; authors may pin a
  key via binding for cross-session dedupe.
- **Retry + backoff + jitter**: only for idempotent ops / safe status classes
  (`retryOn`). Exponential `baseMs * 2^n` with full jitter, capped at `max`. A
  non-retryable failure surfaces a typed error immediately.
- **Timeouts**: both connect and overall; on breach → typed timeout error → the source's
  cache/fallback path (11) kicks in.
- **Revalidation**: `etag` reuses the cached content hash for 304-style conditional GETs.

## 2. `request` action (finally implemented)

```jsonc
{ "action": "request",
  "source": { "…": "…", "net": { "…": "…" } },
  "idempotencyKey": "auto",
  "onSuccess": { "action": "…" },     // e.g. setState/navigate, gets $response in ctx
  "onError":   { "action": "…" }      // gets $error { kind, status, message }
}
```

Runs the source through the transport policy; exposes `$response` / `$error` bindings to
the success/error sub-actions. Implement on all three (currently falls through to
"Unhandled"). Errors are **typed**: `network | timeout | http4xx | http5xx | decode |
cancelled` — so authors branch on `$error.kind`.

## 3. `saveFile` action (finally implemented)

Download/persist a payload to the platform's files with a document-picker or a scoped
app dir; typed result (`saved | cancelled | error`) via `$response`. iOS
`UIDocumentPicker` / Android SAF / Aurora transfer-engine. Same contract shape everywhere.

## 4. Errors, offline & observability

- A failed load routes into the resolution chain (11): cache → bundled fallback → stub.
- All requests emit structured logs/analytics (method, key, attempt, status, ms) through
  the existing analytics sink — one format across platforms.
- Respect a global `Retry-After` on 429.

## 5. One shared test suite

Mock-server scenarios as [conformance fixtures](09-conformance-fixtures.md): retry then
succeed; retry exhausted → typed error; idempotency-key stable across retries (server
asserts it saw one key, applied once); timeout → cache fallback; 304 revalidate keeps
cache; 429 + Retry-After. The JS reference + all three renderers must produce identical
`expect.effects`.

## 6. Build sequence
1. Schema: `net` policy object on `DataSource`; `request` fields (`idempotencyKey`,
   `onSuccess`/`onError`); `$response`/`$error` bindings; regen types.
2. JS reference transport (retry/backoff/idempotency/timeout) + mock server + fixtures.
3. iOS `URLSession`-based transport behind a `Transport` protocol; implement `request`/
   `saveFile`. Then Android (OkHttp), Aurora (Qt Network) — same protocol, same fixtures.
