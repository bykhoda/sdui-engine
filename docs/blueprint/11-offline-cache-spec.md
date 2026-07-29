# 11 — Offline cache & screen-resolution spec

Contract-level, so all three renderers cache and fall back **identically**. Lifts
Beagle's proven hash+TTL+LRU+304 protocol off HTTP headers into the contract, and adds
the bundled-fallback floor (see [04](04-benchmark-and-docs.md), [04a](04a-techniques-ledger.md)).

> Serves "never a broken/half screen": the client always has *something* correct to show.

---

## 1. Screen resolution chain (the order a renderer tries)

```
network → local cache (last-good) → bundled fallback (shipped) → generic error stub
```

- **network** — fetch per the source's cache policy (below).
- **local cache** — the last successfully fetched+validated payload for this key.
- **bundled fallback** — structured SDUI JSON shipped in the app bundle, keyed by
  `screen.id`; renders offline even on first launch (empty cache). The clean form of
  "hardcode a JSON in the filesystem" — still contract JSON, never native hardcode.
- **error stub** — a built-in, themed "couldn't load" screen (itself SDUI) with a retry
  action; last resort only.

Every payload entering the chain is **validated before render** (a corrupt/stale doc is
skipped, not rendered) — same guarantee as live fetches.

## 2. Cache policy (contract)

New optional `cache` object on a `DataSource` / screen fetch:

```jsonc
{
  "cache": {
    "policy": "staleWhileRevalidate",   // default; see below
    "ttlSeconds": 300,                   // fresh window
    "key": "screen:{id}:{locale}",       // templated; bindings allowed
    "scope": "user",                     // "user" | "device" | "shared"
    "hash": true,                        // store a content hash for 304-style revalidate
    "maxEntries": 200                     // per-scope LRU cap (eviction)
  }
}
```

**Policies** (superset of the existing `networkOnly|cacheFirst|cacheThenNetwork`):
| policy | behavior |
|---|---|
| `networkOnly` | never read cache (writes last-good for fallback only) |
| `cacheFirst` | serve cache if present+unexpired, else network |
| `cacheThenNetwork` | serve cache immediately, then replace with network when it lands |
| `staleWhileRevalidate` *(default)* | serve cache instantly (even if stale), revalidate in background; if server says unchanged, keep it; if changed, swap |
| `networkFirst` | try network (with timeout), fall back to cache on failure |

## 3. Revalidation (304-style, contract-level)

When `hash:true`, the client stores a content hash of the cached body and sends it on
revalidate (`If-None-Match`-style, but contract-defined so non-HTTP transports work).
Server returns "unchanged" → the client keeps the cached entry and just bumps its
freshness; else it returns the new body. Cheap, and the biggest perceived-perf lever
after `div-patch`. Ties to [04a](04a-techniques-ledger.md) §B.

## 4. Storage (identical behavior, native engines)

| Platform | Store | Notes |
|---|---|---|
| iOS | **GRDB** (SQLite) | one `cache_entries` table: key, scope, body(JSON), hash, storedAt, ttl, lastAccess |
| Android | **Room** (+ DataStore for small meta) | same schema |
| Aurora | **QSqlDatabase** (SQLite) | same schema |

Single logical schema, three native bindings. LRU eviction by `lastAccess` per scope
when over `maxEntries`. `scope:"user"` entries are cleared on sign-out; `device`/
`shared` persist. Encrypt at rest for `scope:"user"` (Keychain/Keystore-wrapped key).

## 5. Bundled fallback

- Location: `<bundle>/sdui-fallback/<screen-id>.json` (+ a manifest). Loaded + validated
  at build time by a CI step (a broken fallback fails the build).
- Contract: `screen.fallback` = a bundled screen id or an inline screen; plus an optional
  global registry mapping ids → fallback ids. Per-screen override wins.
- `$env.offline` binding is `true` when a fallback/cache-stale render is showing, so a
  banner ("Offline — showing saved") can be authored in the contract.

## 6. Invalidation & control

- Actions: `refresh { sources }` re-pulls (already in the contract); add `invalidateCache
  { key | scope }` for explicit busting.
- Server can push a `minVersion`/`purge` hint (ties to `requireVersion`) to force-drop
  stale caches after a breaking release.

## 7. One shared test suite

A mock server scenario file drives: cold cache → network; warm cache → instant + revalidate
unchanged/changed; network fail → cache; cache empty + offline → bundled fallback; TTL
expiry; LRU eviction; sign-out clears `user` scope. All three renderers + the JS reference
run it as [conformance fixtures](09-conformance-fixtures.md) (Level A for policy decisions,
Level B for what actually renders). Identical outcomes = pass.

## 8. Build sequence
1. Schema: add `cache` object + `screen.fallback` + `invalidateCache` action; regen types.
2. JS reference cache-policy resolver + mock-server revalidation + fixtures (pure, CI).
3. iOS GRDB store behind a `ScreenCache` protocol; wire the resolution chain + `$env.offline`.
4. Android Room; Aurora QSql — same protocol, pass the same fixtures.
5. Bundled-fallback manifest + CI validation of fallbacks.
