# 04 · Benchmark study · Offline cache · Embedded docs

The three "missing pillars" that turn this from a good renderer trio into an
enterprise platform. This doc is the research hub — sections get filled by focused
study passes (see [05 roadmap](05-roadmap.md)).

---

## A · Benchmark repo study (define behavior, don't reinvent)

Goal: for every JSON→UI behavior, adopt a proven mechanism so the three renderers
agree by design. Study these and record "what they do / what we adopt":

| Repo | Why | What to mine |
|---|---|---|
| **Yandex DivKit** | production RU SDUI, multi-platform (iOS/Android/web), used at scale | JSON schema shape, `div-patch` partial updates, templates/`div-template`, expression language, sizing model, state & actions, variable triggers |
| **Beagle (ZupIT)** | mature SDUI, cross-platform, strong contract | component contract, context/binding, lazy load, actions, server-driven navigation, caching |
| **Airbnb Epoxy / Server-driven** | list virtualization, diffing | list diff/patch, view pooling, section models |
| **Lona / Adaptive cards** | schema & tokens | token model, schema authoring ergonomics |

**Deliverable:** a "techniques ledger" table — technique · how DivKit/Beagle do it ·
our current state · adopt/skip · issue link. Feeds [[project-bestpractice-adoptions]].

Priority techniques already flagged (from earlier study): fallback components,
div-patch partial updates, templates/component aliases, conformance fixtures,
snapshot tests, model codegen. **Cross-platform conformance fixtures** are the single
highest-leverage item — a golden set of screens + expected layout facts that all
three renderers must pass, making "identical JSON everywhere" testable.

---

## B · Offline / local-cache database (the resilience pillar)

Requirement: apps are fully server-built yet work offline; **identical cache
semantics on iOS, Android, Aurora**. Design questions to resolve:

- **What is cached?** (1) screen documents (the contract JSON), (2) data-source
  responses (`screen.data.sources`), (3) resolved images/assets, (4) tokens.
- **Cache policy in the contract.** `data.sources[].policy` already hints
  `cacheThenNetwork`; formalize a policy enum: `networkOnly · cacheOnly ·
  cacheThenNetwork · networkThenCache · staleWhileRevalidate`, plus TTL and
  invalidation keys — **configurable per source** (pillar 2).
- **Storage engine per platform** (same semantics, native mechanism — no костыль):
  - iOS: a small store over the file system / SQLite (or GRDB); key by screen id +
    source id + params hash.
  - Android: Room/SQLite or DataStore; same keys.
  - Aurora: Qt `QSqlDatabase` (SQLite ships with Qt) or a QML `Storage`/LocalStorage.
- **Determinism.** The cache key algorithm + eviction + TTL must be spec'd once and
  implemented identically; add conformance tests that assert cache hits/misses given
  a fixed sequence.
- **Offline UX in the contract.** Skeleton/placeholder while revalidating; an
  `offline` state binding so screens can show a banner.

**Deliverable:** `spec/schema` additions for cache policy + a
`docs/blueprint/offline-cache-spec.md` defining keys/policies/TTL, then three
implementations behind one test suite. *Study DivKit/Beagle caching first (§A).*

**Screen resolution chain (incl. bundled fallback).** The full order a renderer
tries when loading a screen: **network → local cache (last-good) → bundled fallback
(shipped in the app) → generic error stub.** The **bundled fallback** is structured
SDUI JSON shipped in the app bundle at a known path, keyed by `screen.id` — so a
screen renders offline even on **first launch** (empty cache). This is the standard
enterprise "known-good floor" (the clean form of the "hardcode a JSON in the device
filesystem" pattern — still contract JSON, never native hardcode). Distinct from the
cache (dynamic, last successful response) — the fallback is static, shipped with the
release. Contract-driven + configurable: `screen.fallback` (a bundled screen id or
inline screen) + an optional global fallback registry; per-screen override. Renderers
also expose an `$env.offline` binding so a fallback/skeleton can say so. Design this
alongside the cache spec.

---

## B2 · Networking conventions — idempotency, retry, timeouts (MISSING)

Confirmed gap 2026-07-29: `grep` finds **zero** `idempotency/retry/backoff/timeout/
etag/if-match` in the schema or any renderer. The `request` action (mutations) is in
the schema but **unimplemented on all three platforms**; `saveFile` too. `DataSource`
has only a cache `policy`. For a world-facing enterprise repo this must meet standard
conventions — designed once in the contract, implemented identically everywhere:
- **Idempotency-Key** header on every mutating `request` (client-generated UUID,
  stable across retries) so a retried POST never double-charges/double-submits.
- **Retry with exponential backoff + jitter**, capped attempts, only for idempotent
  ops / safe status classes; surface a typed error otherwise.
- **Timeouts** (connect + overall) per source, configurable in the contract.
- **Conditional requests / ETag + If-None-Match / If-Match** for GET revalidation
  (304) and optimistic-concurrency writes (412) — ties into the Beagle-style content
  hash in [04a](04a-techniques-ledger.md) §B.
- Contract additions: `request { source, idempotencyKey?, retry{max,backoff}, onSuccess,
  onError }`, and per-`DataSource` `{ timeoutMs, retry, revalidate }`.
- **Deliverable:** a `docs/blueprint/networking-spec.md` + schema fields + one shared
  test suite (mock server drives retry/idempotency/304/412 scenarios) so all three
  renderers behave identically. Implement `request`/`saveFile` as part of this.

## C · Embedded platform docs (the reference pillar)

Requirement: Apple / Android / Aurora native docs live in-repo so authors and
contributors have the source-of-truth mapping without leaving the project.

Approach (avoid copyright pitfalls — **do not bulk-copy** proprietary docs; link +
summarize + map):
- `docs/platforms/ios/` — HIG + SwiftUI concept notes, **mapped to our components**
  (e.g. our `list` → SwiftUI `List`; our `material` → `Material`); official links.
- `docs/platforms/android/` — Compose equivalents (our `list` → `LazyColumn`, etc.).
- `docs/platforms/aurora/` — Qt Quick / Silica components + Aurora SDK build/deploy
  guide (this is the least-documented, highest-value one for the RU target).
- A **component ⇄ native mapping matrix**: for each of the 30 components, the iOS /
  Android / Aurora native widget it maps to + the doc link + parity notes. This is
  both documentation and the checklist that keeps renderers honest.

**Deliverable:** `docs/platforms/*` + a mapping matrix generated/maintained next to
`PARITY.md`. Start with the Aurora/Silica build+deploy guide (unblocks [02]).

---

## Open decisions to get from the owner
- Offline storage: adopt one abstraction (recommend SQLite everywhere) vs
  platform-idiomatic (Room/GRDB/QtSql)? (Semantics identical either way.)
- Docs: in-repo Markdown summaries + links (recommended, copyright-safe) vs a
  submodule/vendored copy?
- Benchmark: which repos are in-scope first — recommend **DivKit** (RU, closest
  analog) then **Beagle**.
