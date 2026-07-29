# 04a — Techniques Ledger: DivKit & Beagle, Offline Cache, Recommendations

Staff-engineering research to inform our one-JSON-contract → native iOS/Android/Aurora renderers.
Every non-obvious claim is cited inline. Where a primary source was unreachable at research time
(July 2026) this is stated explicitly rather than guessed.

**Note on source reachability.** DivKit is actively maintained and its docs
([divkit.tech/docs](https://divkit.tech/docs/en/)) and schema (github.com/divkit/divkit) are fully
reachable and were read directly. Beagle was **archived by ZupIT in 2022**; its live docs
(`docs.usebeagle.io`) and several source paths now 404 or fail to connect. Beagle claims here are
sourced from surviving READMEs, mirrors, DeepWiki, and the GitHub repos; where a detail could not be
confirmed from a reachable primary source it is flagged as such.

---

## 1. DivKit (Yandex) deep-dive

DivKit is Yandex's open-source SDUI framework rendering one JSON to native Android, iOS, Web and
Flutter. It is the strongest reference for us because it is schema-first and cross-platform by
construction. Announcement / positioning:
[Yandex releases DivKit (Medium)](https://medium.com/yandex/yandex-releases-divkit-an-open-framework-for-server-driven-ui-cad519252f0f);
repo [github.com/divkit/divkit](https://github.com/divkit/divkit); current version 32.x
([DeepWiki overview](https://deepwiki.com/divkit/divkit/1-overview)).

### 1.1 The JSON contract shape
A payload has two top-level blocks: `templates` and `card` (the `card` holds a `div-data`).
[Templates concept](https://divkit.tech/docs/en/concepts/templates).

`div-data` (the screen root) has these keys
([div-data](https://divkit.tech/docs/en/concepts/divs/2/div-data)):
- `log_id` (required string) — logging/analytics id.
- `states` (required array) — each item is `{ state_id: int, div: <div> }`; a screen can carry
  several full-layout states and switch between them (see §1.6).
- `variables` — declared reactive values (§1.5).
- `variable_triggers` — condition→action reactions (§1.6).
- `timers` — `{ tick_actions, end_actions, duration, ... }`.
- `functions` — user-defined expression functions (args, body, return type), available identically
  on Android/iOS/Web.

Every visual node is a `div` with a discriminant `"type"` (`container`, `text`, `image`, `grid`,
`gallery`, `pager`, `tabs`, `state`, `video`, `input`, `select`, `custom`, …).

**ADOPT:** the two-block `{templates, card}` envelope and a discriminated-union `type` field on every
node. Keep a required `log_id`-equivalent on the root so analytics is contract-level, not bolted on.
Model `states` from day one — it is what makes local interactivity possible without a round trip.

### 1.2 Partial screen updates — `div-patch`
Delivered via the `download` action, which "loads additional data in `div-patch` format and updates
the current element" ([div-action-download](https://divkit.tech/docs/en/concepts/divs/2/div-action-download)).
The patch object ([div-patch](https://divkit.tech/docs/en/concepts/divs/2/div-patch); confirmed
against the schema `schema/div-patch.json`):

- `changes` (required, `minItems: 1`) — array of change ops.
- each change = `{ id (required), items: [<div>...] }`.
  - `id` names an **existing element** in the current tree.
  - `items` is the replacement content: **omit/empty → remove** the element; **one item → replace**;
    **many items → replace one node with several**.
- `mode`: `"transactional"` (all-or-nothing: any failing element aborts the whole patch) or
  `"partial"` (default; apply every valid change, report the rest).
- `on_applied_actions` / `on_failed_actions` — callbacks after the patch resolves.

This is a **targeted, id-addressed tree patch** — not RFC-6902 JSON Patch and not a full re-render.
It is the mechanism behind "update the cart badge / one card" without refetching the screen.

**ADOPT:** an id-addressed patch primitive with exactly these three semantics
(remove / replace-1 / replace-with-many) plus a `mode` enum. This is higher-level and safer than raw
JSON Patch (pointer paths are brittle across template inflation) and it is the single biggest lever
for perceived performance. Require stable node `id`s in our schema to make it addressable.

### 1.3 Templates / component aliasing
`templates` is a root map of `name → partial div definition`. A node references a template by putting
the template name in its `"type"` field (aliasing), then overrides/fills fields. Template parameters
are declared by prefixing a field name with `$`, e.g. a template field `"text": "$title"` means "bind
the caller's `title` here." Callers may override any inherited field. System type names
(`container`, `text`, …) are reserved and cannot be used as template names.
([Templates](https://divkit.tech/docs/en/concepts/templates).)

Payoff: templates "reduce the size of incoming JSON and reduce the number of possible errors and
typos" — the card sends only the varying params, the shape is defined once.

**ADOPT:** template inflation as a first-class, client-side expansion step (define-once, instantiate
via `type`, `$param` substitution, field override). It is our answer to payload bloat and to design
consistency: a "ProductCard" template guarantees every card is structurally identical. Reserve
built-in type names.

### 1.4 Expression / variable language
Expressions are wrapped in `@{ … }` inside any string field
([Expression DSL](https://divkit.tech/docs/en/concepts/expression-dsl)). Features:
- Variable refs by name (typed accessors: string/integer/number/boolean/color/url).
- Arithmetic (`+ - * / %`), logical (`! and or`), comparison
  (`equalTo`, `notEqualTo`, `moreThan`, `lessThan`, `>=`/`<=`), string concatenation via `+`.
- Ternary `ifElse` and a null-safe `tryExpression` (return left if valid else right).
- A large built-in function library (`decimalFormat`, date/time, string ops, etc.) plus user
  `functions` declared in `div-data`.
- Numbers always carry a decimal point (`1 → 1.0`); negatives render parenthesized `(-1)`.

Expressions are re-evaluated reactively when referenced variables change.

**ADOPT:** a single small expression grammar with a `@{}` sentinel, evaluated identically on every
platform from **one shared grammar spec** (see §1.7 — this is only safe if there is a conformance
suite). Ship a fixed, versioned function catalog. **ADAPT:** keep the function set deliberately
smaller than DivKit's at v1 — every function is a cross-platform correctness liability.

### 1.5 Variables — declaration & scope
Declared in `div-data.variables` as `{ name, type, value }` with 8 types: `string`, `integer`,
`number`, `boolean`, `color`, `url`, `dict`, `array`
([Variables](https://divkit.tech/docs/en/concepts/variables)). Names are alphanumeric+`_`/`.`, not
starting with a digit/dot. Variables can be **global (card root)** or **local (element scope)**; a
local shadows a global of the same name. Mutated at runtime via the `set_variable` action.

**ADOPT:** typed variables with root + element scope and explicit shadowing rules. The `color` and
`url` first-class types are worth copying — they let us validate at authoring time.

### 1.6 State & triggers
- **`div-state`** (a node with several named `state_id`→`div` variants) enables local, no-network UI
  switches (tabs, expand/collapse). Switched via `set_state`.
- **`variable_triggers`** on `div-data`: `{ condition, actions, mode }` where `mode` is
  `on_condition` (fire when condition flips false→true) or `on_variable` (fire on every variable
  change while condition holds) ([Variables](https://divkit.tech/docs/en/concepts/variables)).
- **`timers`**: recurring `tick_actions` + terminal `end_actions`.

**ADOPT:** `div-state`-style local states + declarative triggers. This is what keeps interaction
server-authored yet offline-capable. The `on_condition` vs `on_variable` distinction is a clean way
to express "edge" vs "level" reactions — copy it verbatim.

### 1.7 Sizing model
`width` / `height` are objects with a `type`
([Layout](https://divkit.tech/docs/en/concepts/layout),
[div-fixed-size](https://divkit.tech/docs/en/concepts/divs/2/div-fixed-size)):
- `"type": "fixed"` — explicit `{ value: int, unit: "dp" | "sp" }` (default width).
- `"type": "match_parent"` — fill parent; multiple siblings split remaining space by `weight`.
- `"type": "wrap_content"` — size to content (default height); supports `constrained`.
- `min_size` / `max_size` bounds on both.
- **Resolution order:** `fixed` and `wrap_content` claim space first, then `match_parent` divides the
  remainder by `weight`.

**ADOPT:** exactly this three-mode model (`fixed{value,unit}` / `match_parent` + `weight` /
`wrap_content` + `min/max`), and specify the resolution order **in the contract** so Yoga (Beagle),
our iOS/Android layout, and Aurora's Qt layout all agree. This is a place where "obvious" ambiguity
causes cross-platform drift.

### 1.8 Cross-platform behavioral parity — how DivKit enforces it
- **Schema is the single source of truth.** `schema/` defines every component; `api_generator/`
  generates platform code — `generators/kotlin`, `generators/swift`, `generators/type_script`
  ([DeepWiki overview](https://deepwiki.com/divkit/divkit/1-overview)). Models are generated, not
  hand-written per platform → structural drift is impossible by construction.
- **Shared test data.** `test_data/` and `test_data/regression_test_data/` hold JSON fixtures that
  **all clients consume**; "native evaluators consume shared test data" to verify identical behavior
  ([DeepWiki overview](https://deepwiki.com/divkit/divkit/1-overview); repo tree
  [github.com/divkit/divkit](https://github.com/divkit/divkit)). Expression evaluation especially is
  driven by the same fixtures on every runtime.
- Reference client renders + snapshot/regression tests per platform.

**ADOPT (highest priority):** schema → codegen for models on all three renderers, and a **shared
JSON fixture corpus** that every renderer must pass (structural + expression-eval + golden-image).
This is the only mechanism that makes "behaviorally identical" a testable claim rather than a hope.

---

## 2. Beagle (ZupIT) deep-dive

Cross-platform SDUI for iOS/Android/Web with a Kotlin **BFF DSL** on the backend. Archived 2022 —
treat as a source of ideas, not a living dependency. Repos:
[ZupIT/beagle](https://github.com/ZupIT/beagle),
[beagle-web-core](https://github.com/ZupIT/beagle-web-core),
[zup-archive/beagle-android](https://github.com/ZupIT/beagle-android),
[ZupIT/beagle-ios](https://github.com/ZupIT/beagle-ios). README mirror:
[tchigher/beagle-1](https://github.com/tchigher/beagle-1/blob/master/README.md).
*(Primary docs `docs.usebeagle.io` were unreachable during research; component/cache specifics below
are from READMEs, mirrors, and issue trackers and are flagged where confidence is lower.)*

### 2.1 Component contract
A Beagle tree node is an object with `_beagleComponent_` (the type, e.g. `beagle:container`,
`beagle:text`, `beagle:lazyComponent`), an `id`, and optionally `children` (or component-specific
slots like `child` / `pages`)
([beagle-web-core README](https://github.com/ZupIT/beagle-web-core);
[mirror README](https://github.com/tchigher/beagle-1/blob/master/README.md)). On the backend, Kotlin
classes are serialized with **Jackson**; on Android JSON is deserialized with **Moshi**; layout is
done by **Facebook Yoga (flexbox)**; theming via a `DesignSystem` interface
([mirror README](https://github.com/tchigher/beagle-1/blob/master/README.md)).

**ADAPT:** the `_beagleComponent_` + `id` + `children` shape is basically DivKit's `type` + node model
under different names — we already lean DivKit. **ADOPT** Beagle's explicit **Yoga/flexbox** layout
choice as a cross-platform equalizer (a real flexbox engine on each platform removes layout-math
divergence; Aurora/Qt would need a flex shim). **ADOPT** the `DesignSystem` indirection: components
reference **named** styles/tokens, not raw values — the client owns the visual vocabulary.

### 2.2 Context / binding / expressions
Beagle's headline feature is **context**: any component declares a `context` = `{ id, value }`; the
value is then referenced anywhere below via the expression `@{id}` (and `@{id.path.to.field}` for
nested access) ([Zup blog: Beagle Web concepts](https://medium.com/zup-it/server-driven-ui-com-beagle-web-motiva%C3%A7%C3%A3o-e-conceitos-iniciais-1f4af7f47e19)).
Contexts are **scoped by tree position** (a child sees ancestors' contexts). Values are mutated with
the built-in `beagle:setContext` action.

**ADOPT the idea, ADAPT the shape:** scoped, position-based reactive state with `@{}` binding is
excellent and matches DivKit's local-variable scoping. Since we are standardizing on DivKit-style
`variables`, adopt Beagle's *scoping ergonomics* (declare context on the subtree that owns it) rather
than a parallel `context` keyword.

### 2.3 Lazy loading — `beagle:lazyComponent`
`beagle:lazyComponent` renders a placeholder immediately and fetches its real subtree from a `path`,
swapping it in on arrival (with an `initialState`/loading placeholder shown meanwhile).
*(Component name confirmed via search snippets and READMEs; exact field names `path`/`initialState`
are from Beagle docs that were unreachable at research time — treat as high-level-correct,
verify field names against source before implementing.)*

**ADOPT:** a lazy-subtree primitive: `{ type: lazy, source: <url>, placeholder: <div> }`. It composes
perfectly with §1.2 patches (lazy = fetch a subtree; patch = mutate an existing one) and is essential
for long/expensive screens. **ADAPT** naming to our schema.

### 2.4 Server-driven navigation
Navigation is expressed as **actions**, not client routes: push/pop a view or a stack, or reset the
app/stack. The documented action family is `beagle:pushView`, `beagle:pushStack`, `beagle:popView`,
`beagle:popStack`, `beagle:popToView`, `beagle:resetStack`, `beagle:resetApplication`; a route is
either a **remote** `{ url }` (fetch a screen) or a **local** declared screen. Views are fetched from
the BFF as navigation happens ([mirror README](https://github.com/tchigher/beagle-1/blob/master/README.md);
navigation crash/route notes in issue tracker). *(Exact action id list corroborated across secondary
sources; primary spec page unreachable — verify before copying names.)*

**ADOPT:** navigation as first-class **actions** with a `route = remote(url) | local(screen)` union
and an explicit stack model (push/pop/reset). Server-authored navigation is a core SDUI capability we
must ship; DivKit under-specifies this (it leans on host-app URL handling), so **Beagle is the better
reference here.**

### 2.5 Caching / offline
Beagle ships a real **client-side cache protocol** layered on HTTP
([issue: Android cache behavior #835](https://github.com/ZupIT/beagle/issues/835); cache module in
[beagle-web-core](https://github.com/ZupIT/beagle-web-core)):
- The BFF returns a **`beagle-hash`** response header (a content hash of the screen JSON) plus a
  standard **`Cache-Control: max-age=…`**.
- The client persists the screen JSON keyed by URL in a **two-tier cache: in-memory + disk (LRU)**.
- On revalidation the client sends the stored `beagle-hash` back; if the content is unchanged the BFF
  answers **304 Not Modified** and the client serves the cached tree — an ETag-style protocol
  specialized for SDUI screens.
- Behavior is gated by a `beagleCacheEnabled`-style flag and the server-provided `max-age` (TTL).

*(Header/flag names are as documented by the framework; the canonical spec page was unreachable, so
confirm the exact string constants against `beagle-web-core`/`beagle-android` source before relying on
them.)*

**ADOPT (concept), STANDARDIZE (shape):** content-hash + TTL revalidation is exactly right. But rather
than couple to HTTP headers, lift it into our **contract-level cache policy** (§3) so Aurora/Qt (which
may not go through a browser HTTP stack) behaves identically.

### 2.6 Cross-platform consistency strategy — ADOPT/SKIP
Beagle's consistency rests on (a) **Yoga** giving identical flexbox math on every platform, and
(b) a shared **BeagleSchema** describing components
([BeagleSchema versions](https://openbase.com/swift/BeagleSchema/versions)). It did **not** have
DivKit's schema→codegen + shared-fixture regression rigor; parity was more manual, which (with the
archival) is a cautionary tale.
- **ADOPT:** Yoga-style shared layout engine; a published schema package.
- **SKIP:** relying on hand-maintained per-platform models and manual parity — adopt DivKit's
  generated-models + shared-fixture approach instead (§1.8).

---

## 3. Offline / local-cache patterns

### 3.1 What the two frameworks actually do
- **DivKit:** the framework core is a **renderer**, not a networking/cache layer — fetching and caching
  screen JSON is left to the host app. Its offline story is *composability*: `div-patch` for deltas
  and `templates` to shrink payloads, but no built-in disk cache spec
  ([DivKit docs](https://divkit.tech/docs/en/)). **Takeaway:** we must define the cache layer
  ourselves; DivKit gives us the update primitives to build on.
- **Beagle:** has an explicit cache protocol (§2.5): `beagle-hash` content hash + `Cache-Control`
  `max-age`, two-tier **memory + disk (LRU)**, 304-based revalidation
  ([issue #835](https://github.com/ZupIT/beagle/issues/835)). **Takeaway:** the right *shape* (hash +
  TTL + two tiers), wrong *coupling* (HTTP-header-specific).
- **General mobile SDUI practice:** standard policies are **cacheFirst / networkFirst /
  staleWhileRevalidate / networkOnly / cacheOnly**, mirroring service-worker strategies
  ([Offline-first caching strategies](https://www.magicbell.com/blog/offline-first-pwas-service-worker-caching-strategies)).

### 3.2 Cross-platform storage engines (per renderer)
| Concern | iOS | Android | Aurora OS (Qt/QML) |
|---|---|---|---|
| Structured store | **SQLite via GRDB** (or Core Data) | **Room** (SQLite) | **QSqlDatabase (SQLite)** |
| Small key/value (policy, hashes, TTLs) | UserDefaults / file | **DataStore (Preferences/Proto)** | QSettings / QML `LocalStorage` |
| Blob/JSON payloads | file cache in Caches dir | file cache / Room BLOB | file cache in app cache dir |
| Eviction | LRU + size cap (app-managed) | LRU + size cap (app-managed) | LRU + size cap (app-managed) |

QML also offers `LocalStorage` (a SQLite-backed offline API) for the QML layer specifically.

### 3.3 Recommended single cross-platform cache-policy contract
Ship the cache policy **in the screen/response contract** (not as per-platform HTTP config) so all
three renderers behave identically. Proposed shape:

```jsonc
{
  "cache": {
    "policy": "staleWhileRevalidate",   // cacheFirst | networkFirst | staleWhileRevalidate
                                         // | networkOnly | cacheOnly
    "ttlSeconds": 3600,                  // freshness window; after TTL entry is "stale"
    "key": "screen:home:v2:{userTier}",  // explicit, templated cache key (see below)
    "hash": "sha256-abc123…",            // server content hash → skip re-render if unchanged (ETag-like)
    "maxStaleSeconds": 86400,            // hard cap: serve stale up to this, then force network
    "scope": "user"                      // user | device | global — controls key namespacing & purge
  }
}
```

**Policy semantics (identical on every renderer):**
- `cacheFirst` — serve cache if present & within `ttlSeconds`, else network.
- `networkFirst` — try network (short timeout), fall back to cache on failure/offline.
- `staleWhileRevalidate` — **render cache instantly**, revalidate in background via `hash`, patch in
  the fresh tree if changed. *Default for most screens — best perceived performance.*
- `networkOnly` / `cacheOnly` — escape hatches for sensitive or fully-offline screens.

**Cache-key strategy:**
- Key = `screen-id + contract-version + explicit variance dimensions` (locale, user tier, theme,
  A/B bucket). Make variance **explicit in the key template** — never silently key on the whole URL,
  and never put PII in the key.
- `scope` namespaces keys and drives targeted invalidation (`purge(scope:"user")` on logout).

**Invalidation:**
- **TTL** (`ttlSeconds`) for time-based staleness; `maxStaleSeconds` as the offline hard-stop.
- **Content hash** (`hash`) for cheap revalidation — unchanged hash ⇒ reuse cached render, no re-parse.
- **Version bump** (`contract-version` in the key) to invalidate en masse on breaking schema changes.
- **Explicit push-purge** action (server tells clients to drop a key) for correctness-critical data.

**Data responses vs screen JSON:** apply the *same* policy object to data-bound endpoints
(e.g. `sendRequest` results feeding variables), so a screen and its data share one coherent freshness
model instead of two ad-hoc ones.

This gives us Beagle's proven hash+TTL protocol, generalized off HTTP headers into the contract, with
per-platform engines (GRDB / Room+DataStore / QSqlDatabase) behind one identical policy enum.

---

## 4. Techniques ledger

| Technique | DivKit | Beagle | Recommendation | Why |
|---|---|---|---|---|
| **Partial updates / patching** | `div-patch`: `changes[]` of `{id, items}`; `mode` transactional/partial; remove/replace-1/replace-many by id ([div-patch](https://divkit.tech/docs/en/concepts/divs/2/div-patch)) | Re-fetch view / `lazyComponent` swap; no fine-grained tree patch | **Adopt DivKit** id-addressed patch + `mode` enum | Cheapest perceived-perf win; id-addressing beats brittle JSON-Pointer paths |
| **Templates / aliasing** | `templates` map, alias via `type`, `$param` substitution + field override ([Templates](https://divkit.tech/docs/en/concepts/templates)) | Backend Kotlin DSL composes reusable views server-side | **Adopt DivKit** client-side template inflation | Shrinks payload, enforces structural consistency (one "ProductCard" shape) |
| **Expression language** | `@{}` DSL: arithmetic/logical/comparison, `ifElse`/`tryExpression`, built-in + user `functions` ([Expression DSL](https://divkit.tech/docs/en/concepts/expression-dsl)) | `@{context.path}` binding expressions | **Adapt** DivKit grammar, **smaller** function set at v1 | One grammar + shared eval fixtures; fewer functions = fewer parity bugs |
| **Sizing** | `width`/`height` = `fixed{value,unit}` / `match_parent`+`weight` / `wrap_content`+`min/max`; documented resolution order ([Layout](https://divkit.tech/docs/en/concepts/layout)) | Yoga flexbox (`flex`, `grow`, `basis`) | **Adopt DivKit** 3-mode model; **borrow** Beagle's shared engine idea | Contract-level resolution order prevents cross-platform layout drift |
| **State / variables** | typed `variables` (8 types incl. `color`/`url`), root+local scope, `div-state`, `variable_triggers` (`on_condition`/`on_variable`) ([Variables](https://divkit.tech/docs/en/concepts/variables)) | `context = {id,value}`, scoped by tree, `setContext` | **Adopt DivKit** typed vars + triggers; **borrow** Beagle scoping ergonomics | Typed vars validate at authoring; edge/level triggers are expressive & portable |
| **Actions** | `div-action://` URL scheme + `typed` actions: `set_variable`, `set_state`, `download`, `timer`, `scroll_to` ([Interaction](https://divkit.tech/docs/en/concepts/interaction)) | `beagle:setContext`, `beagle:sendRequest`, navigation actions | **Adopt** `typed`-action objects (not URL-encoded params) | Typed actions are self-validating and readable; URL params are error-prone |
| **Lazy load** | Load subtree via `download`/patch | `beagle:lazyComponent` with `path` + placeholder | **Adopt Beagle** lazy-subtree primitive | Essential for long/expensive screens; composes with patching |
| **Offline cache** | Host-app concern (not in framework) | `beagle-hash` + `Cache-Control` maxAge, memory+disk LRU, 304 revalidate ([#835](https://github.com/ZupIT/beagle/issues/835)) | **Adopt Beagle concept, standardize** into contract policy (§3) | Hash+TTL is proven; lifting off HTTP headers makes Aurora behave identically |
| **Fallback components** | Unknown `type` handling / `custom` slot | `_beagleComponent_` custom registry | **Adopt** explicit `fallback`/unknown-type policy in schema | Forward-compat: new server components must degrade, never crash old clients |
| **Conformance / golden tests** | Schema SoT + `api_generator` codegen (kotlin/swift/ts) + shared `test_data`/`regression_test_data` fixtures ([DeepWiki](https://deepwiki.com/divkit/divkit/1-overview)) | BeagleSchema + Yoga; manual parity (weaker) | **Adopt DivKit** — schema→codegen + shared fixture corpus all renderers must pass | Only way "behaviorally identical" becomes testable, not aspirational |
| **List diffing / virtualization** | `gallery`/`container` recycle natively; change-animations on size/position deltas | Yoga + native list recycling | **Adopt** native virtualization + stable `id`s for diffing | Stable ids let patch + list-recycler diff efficiently at scale |

---

## 5. Top 10 concrete recommendations (ranked)

1. **Make the JSON schema the single source of truth and codegen models for all three renderers.**
   Mirror DivKit's `api_generator` → generate Swift / Kotlin / Qt-C++(or QML) models from one schema
   so structural drift is impossible ([DeepWiki](https://deepwiki.com/divkit/divkit/1-overview)).

2. **Build a shared cross-platform fixture corpus** (`test_data/` + `regression_test_data/`
   equivalents) that every renderer must pass — structural parse, expression evaluation, and
   golden-image tests — so "identical behavior" is CI-enforced, not hoped for
   ([DivKit shared test data](https://deepwiki.com/divkit/divkit/1-overview)).

3. **Adopt DivKit's `div-patch` as our partial-update primitive:** `changes[]` of `{id, items}` with a
   `mode` (transactional/partial) and remove/replace-1/replace-many semantics; require stable node
   `id`s to make it addressable ([div-patch](https://divkit.tech/docs/en/concepts/divs/2/div-patch)).

4. **Adopt template inflation** (`templates` map, alias-by-`type`, `$param` substitution + override) —
   it cuts payload size and structurally guarantees component consistency; reserve built-in type names
   ([Templates](https://divkit.tech/docs/en/concepts/templates)).

5. **Standardize one cache-policy contract object** (`policy` enum + `ttlSeconds` + templated `key` +
   content `hash` + `scope`), defaulting to `staleWhileRevalidate`; back it with GRDB (iOS) /
   Room+DataStore (Android) / QSqlDatabase (Aurora) behind identical semantics (§3).

6. **Adopt Beagle-style server-driven navigation as first-class actions** (`pushView`/`pushStack`/
   `popView`/`reset*`) with a `route = remote(url) | local(screen)` union and an explicit stack model —
   DivKit under-specifies this ([Beagle README](https://github.com/tchigher/beagle-1/blob/master/README.md)).

7. **Ship typed actions, not URL-encoded params:** a `typed` action object
   (`set_variable`/`set_state`/`download`/`navigate`/`timer`) is self-validating and readable
   ([Interaction](https://divkit.tech/docs/en/concepts/interaction)).

8. **Adopt the exact three-mode sizing model** (`fixed{value,unit}` / `match_parent`+`weight` /
   `wrap_content`+`min/max`) **and write the resolution order into the contract** so iOS layout,
   Android layout, and Qt layout on Aurora cannot diverge ([Layout](https://divkit.tech/docs/en/concepts/layout)).

9. **Adopt typed variables + declarative triggers with `div-state`** (8 typed vars incl. `color`/`url`;
   `on_condition` vs `on_variable`) for offline-capable local interactivity; keep the expression
   function catalog small and versioned ([Variables](https://divkit.tech/docs/en/concepts/variables)).

10. **Define a mandatory fallback / unknown-component policy in the schema** plus a lazy-subtree
    primitive (Beagle `lazyComponent`), so new server components degrade gracefully on old clients and
    heavy screens load progressively — both are prerequisites for shipping SDUI safely at enterprise
    scale.

---

### Sources
- DivKit repo & README — https://github.com/divkit/divkit
- DivKit docs (templates, variables, expression DSL, div-data, layout, interaction, div-patch,
  div-action-download) — https://divkit.tech/docs/en/
- DivKit architecture (schema SoT, api_generator, shared test data) —
  https://deepwiki.com/divkit/divkit/1-overview
- Yandex DivKit announcement —
  https://medium.com/yandex/yandex-releases-divkit-an-open-framework-for-server-driven-ui-cad519252f0f
- Beagle repos — https://github.com/ZupIT/beagle · https://github.com/ZupIT/beagle-web-core ·
  https://github.com/ZupIT/beagle-ios · https://github.com/ZupIT/beagle-android
- Beagle README mirror — https://github.com/tchigher/beagle-1/blob/master/README.md
- Beagle Web concepts (context/expressions) —
  https://medium.com/zup-it/server-driven-ui-com-beagle-web-motiva%C3%A7%C3%A3o-e-conceitos-iniciais-1f4af7f47e19
- Beagle caching behavior — https://github.com/ZupIT/beagle/issues/835
- Offline-first caching strategies —
  https://www.magicbell.com/blog/offline-first-pwas-service-worker-caching-strategies

*Reachability caveats: Beagle's canonical docs (`docs.usebeagle.io`) and some `beagle-web-core` source
paths, plus `web.archive.org`, were unreachable at research time (July 2026). Beagle cache header
names (`beagle-hash`), the `lazyComponent` field names (`path`/`initialState`), and the exact
navigation-action id list are corroborated from READMEs/mirrors/secondary sources and should be
re-verified against `beagle-android`/`beagle-web-core` source before implementation.*
