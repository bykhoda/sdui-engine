# 17 — The AI-authoring MCP: one server an agent uses to build a whole app + backend

> North star ([[project-vision-ecosystem]]): *one shared contract lets any persona enter
> and feel like the others.* The MCP is the **on-ramp for the AI persona** — Claude/Codex
> as designer, PM, backender, frontender at once. Judge every tool below by: *does it let
> an agent go from intent → validated screens → a running backend the clients point at,
> with the contract as ground truth so it can never drift from what a device renders?*

The owner's phrasing — *"clients just have their own backends and everything works
beautifully"* — is the acceptance test. This doc designs the MCP that gets an agent there.

Status: **design.** Current server ([`spec/mcp/server.mjs`](../../spec/mcp/server.mjs) +
[`tools.mjs`](../../spec/mcp/tools.mjs)) ships 7 tools + 3 resource families. This is the
plan to grow it into a world-class authoring surface, staged, **zero-dependency**.

---

## 1. What we learned from the field (and how it maps here)

**Anthropic, *Writing effective tools for AI agents*** ([anthropic.com/engineering/writing-tools-for-agents](https://www.anthropic.com/engineering/writing-tools-for-agents)) — the most load-bearing source:

| Principle | What it means for our MCP |
|---|---|
| **Consolidate, don't wrap endpoints** — build `schedule_event`, not `list_users`+`create_event` | Ship *workflow* tools (`compose_screen`, `generate_backend`) that do a whole job, not one CRUD op per HTTP route. |
| **Namespace tools** (`asana_projects_search`) | Everything is one server (`sdui`) already namespaced by prefix; keep verbs consistent: `list_*`, `get_*`, `validate_*`, `lint_*`, `scaffold_*`, `compose_*`, `generate_*`. |
| **Return high-signal context, not raw dumps** — resolve UUIDs → human names | Errors and lints must name the **JSON path + the fix** (`screen.content.children[2].color: token "$token.color.primic" not defined — did you mean "$token.color.primary"?`), never a bare boolean. |
| **Token efficiency** — pagination + `response_format: concise \| detailed` | `list_components`/`explain_component` take a `verbosity` arg; the whole-schema resource stays a *resource* (attached on demand), not a tool that dumps 700 lines every call. |
| **Steering error messages** | Our `Validator` already emits precise paths; lint extends it with *suggestions* and *auto-fix patches*. |
| **Evaluation-driven** | Reuse the conformance corpus ([09](09-conformance-fixtures.md)) as the eval set: "given intent X, does the agent's screen pass Level-A?" |

**MCP production-design writeups** (Itential *Designing MCP servers*, the *Toolhost* pattern, modelcontextprotocol.info best-practices) converge on six ideas we adopt: **outcome-first tools, curated (small) surface area, bounded-context resources, prompt discipline, deterministic guardrails, structured failure handling.** Curated surface matters — too many overlapping tools *degrade* agent performance, so this doc groups ~24 tools into 6 clear buckets and stages them, rather than shipping all at once.

**High-star reference servers** (star counts approximate, research date 2026-07; GitHub API was rate-limited, figures from prior knowledge):
- **`modelcontextprotocol/servers`** ≈ 60k★ — [github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers). The canonical patterns for tools/resources/prompts over stdio.
- **`github/github-mcp-server`** ≈ 20k★ — [github.com/github/github-mcp-server](https://github.com/github/github-mcp-server). Toolsets you can enable/disable; consolidated high-level ops.
- **`GLips/Figma-Context-MCP`** (Framelink) ≈ 9k★ — [github.com/GLips/Figma-Context-MCP](https://github.com/GLips/Figma-Context-MCP). The design-to-code lesson: **don't hand the model the raw design tree** — distill it into a compact, layout-relevant shape the LLM can actually use. Our analogue: hand the agent the *catalog + examples + lints*, not raw schema soup.
- **Figma Dev Mode MCP** (official) — [github.com/figma/mcp-server-guide](https://github.com/figma/mcp-server-guide). Exposes `get_code`, `get_variable_defs` (tokens!), and a **rules/prompt** layer that steers the model toward the design system. We mirror this: tokens as a first-class resource + a design-lint that *enforces* them.
- **`divkit/divkit`** ≈ 2.6k★ — [github.com/divkit/divkit](https://github.com/divkit/divkit). The SDUI techniques we're porting (div-patch [13](13-div-patch-spec.md), cache [11](11-offline-cache-spec.md)); the MCP should expose *helpers* for those, since an agent won't invent them.

The through-line from Figma's MCP: the win isn't "more API surface", it's **giving the model the design system as context and a linter that keeps it honest.** That's exactly what a tokenized, schema-validated SDUI contract is built to do.

---

## 2. Design rules for THIS server

1. **The contract is the only source of truth.** Every tool derives from `spec/schema/sdui.schema.json` at load time (as `validate.mjs`/`tools.mjs` already do). No hand-listed vocabularies — add a component to the schema, it appears in `list_components`, `explain_component`, lint, and scaffolds automatically.
2. **Validate-before-anything.** No tool that *emits* a screen (`scaffold_*`, `compose_*`, `apply_patch`, `generate_backend`) returns without running the `Validator` on its output and refusing/annotating on failure. The agent physically cannot ship an invalid screen through this server.
3. **Layered guardrails, not just flexibility** ([[feedback-composer-guardrails]]): hard **validation** (schema) → **lint** (design-quality, [[feedback-design-standard]]) → **conformance** (cross-platform parity [09](09-conformance-fixtures.md)). Each is a tool.
4. **Zero-dependency, stdio JSON-RPC** — keep the property that made this server trustworthy: no npm tree, runs from any cwd, logs to stderr only. Any tool that needs a process (serve, preview) *spawns node* or returns a ready-to-run scaffold rather than pulling a framework.
5. **Progressive disclosure.** Cheap orientation tools (`list_*`) are always loaded; the 700-line schema and long docs are **resources**, attached only when the agent asks. Verbose tools accept `verbosity: concise|detailed`.
6. **Outputs are the deliverable, structured.** Tools return `{ ok, data, diagnostics[], next[] }`-shaped JSON so the agent gets a result *and* a nudge toward the next step ("screen valid — preview at …, or `generate_backend` to serve it").

---

## 3. The tool set

Grouped into six buckets. **Bold = new.** Each row: input → output, purpose. `verbosity` (concise|detailed, default concise) is implicit on the read-heavy tools per the token-efficiency rule.

### A. Authoring

| Tool | Input | Output | Purpose |
|---|---|---|---|
| `scaffold_screen` *(exists — enrich)* | `kind` (blank/list/form/**detail/dashboard/onboarding/profile/settings/paywall**), `id`, `title`, **`tokens?`** | a valid starter screen doc | Launch pad. Enrich with more premium archetypes ([[reference-premium-ui-playbook]]) — each emits a rails/hero/one-accent layout, not a bare stack. |
| **`compose_screen`** | `intent` (NL, e.g. "a product-detail with hero image, price, add-to-cart that POSTs /cart"), `data?` (sources), `style?` | a valid screen doc + `diagnostics` | The flagship *outcome-first* tool. Turns an intent into an assembled, token-clean, validated screen by combining archetype + component knowledge + examples. Always validates before returning. |
| **`add_component`** | `screen`, `targetId` (parent), `component` (or `intent`), `at?` (index) | updated screen + validation | Structured tree edit so the agent doesn't reserialize a huge doc to add one node — cheaper + less error-prone. |
| **`bind_data`** | `screen`, `nodeId`, `field`, `binding` (`$data.*`/`$state.*`/`$item.*`), or `source` to declare | updated screen; auto-checks the binding resolves | Data-binding helper: wires a node to a source/state and *guarantees* the `$data.<id>` has a matching source (the cross-ref the `Validator` already enforces). |
| **`apply_patch`** | `screen`, `patch` (div-patch shape [13](13-div-patch-spec.md)) | patched screen + validation | Exercise/author id-addressed partial updates; validates the result tree. Teaches the agent the patch format it would otherwise never produce. |
| `get_example` *(exists)* | `id` | full example doc | Examples-as-context (the single strongest LLM lever). |
| `list_examples` *(exists — enrich)* | `tags?`, `verbosity` | id + title (+ **one-line "demonstrates" + tags**) | Searchable gallery so the agent picks the closest starting point. |
| **`search_patterns`** | `query` (e.g. "collapsing header", "infinite scroll", "swipe actions") | matching example/snippet ids + the minimal JSON for that pattern | Recipe lookup for the signature interactions ([[feedback-signature-interactions]]) an agent won't reinvent (collapsing scroll [06](06-collapsing-scroll.md), pager, swipe, chart-scrub). |

### B. Validation / Lint

| Tool | Input | Output | Purpose |
|---|---|---|---|
| `validate_screen` *(exists)* | `payload`, `checkTokens?` | `{ ok, errors[] }` (path-precise) | The gate. Schema shape + unknown types + dangling `$data` + `$token` typos. Unchanged — it's already best-in-class. |
| **`lint_screen`** | `payload`, `tokens?`, `rules?` | `{ diagnostics[]: {severity, path, rule, message, fix?} }` | **Design-lint** ([[feedback-design-standard]], [[feedback-composer-guardrails]]): off-token literal colors/spacing (`#FF0000` where a `$token` exists), low text-contrast pairs, non-native spacing (magic numbers not on the 4/8pt scale), missing accessibility labels on tappables, images without `aspectRatio` (layout jump), lists without an `empty` state, buttons with no `onTap`. Each diagnostic carries a **fix patch** so the agent can auto-apply. |
| **`explain_diagnostic`** | `rule` | why it matters + the good/bad JSON | Turns a lint code into teaching context (the composer-guardrail "explain, don't just block"). |
| **`check_conformance`** | `payload` (or fixture `id`) | Level-A result: bindings/conditions/effects vs the shared corpus [09](09-conformance-fixtures.md) | Runs the screen through the JS reference (`spec/conformance/check.mjs`) so the agent knows it'll behave *identically on iOS/Android/Aurora*, not just parse. The parity guarantee, on tap. |
| **`get_component_schema`** | `type` | the resolved `*Props` JSON-Schema for one component | Precise field-level truth for one node without loading the whole 700-line schema (progressive disclosure). |

### C. Docs / Introspection

| Tool | Input | Output | Purpose |
|---|---|---|---|
| `list_components` *(exists)* | `verbosity` | type, required, purpose, fields | Never guess a component name. |
| `list_actions` *(exists)* | — | kind + required fields | The closed action vocab. |
| `list_tokens` *(exists)* | — | groups + flat valid set | The design system, as data. |
| **`explain_component`** | `type`, `examples?` | purpose + every field (typed) + a minimal valid usage + which examples use it | The "read the manual for one thing" tool — richer than `list_components`, cheaper than the schema. Mirrors Figma MCP's `get_code` per-node focus. |
| **`explain_binding`** | `namespace` (`$data`/`$state`/`$token`/`$env`/`$params`/`$item`) | the rules + interpolation + worked examples | Bindings are the #1 authoring confusion; give it a dedicated tool. |
| **`capability_matrix`** | `capability?` | per-platform support (iOS/Android/Aurora) from [10](10-capability-matrix.md)/`PARITY.md` | So the agent won't author a screen leaning on something Android can't render yet — sets honest expectations. |

### D. Backend / Serving

| Tool | Input | Output | Purpose |
|---|---|---|---|
| **`generate_backend`** | `target` (node/python/go), `screens` (ids or docs), `features?` (cache/fallback/patch/idempotency/hot-reload), `services?` (name→baseURL) | a complete, ready-to-run backend project (files as a map) | **The "their own backend" tool.** Emits a screen server: routes, a screen store, per-source cache/fallback ([11](11-offline-cache-spec.md)), the transport conventions ([12](12-networking-spec.md)), a boot-time validation gate, hot-reload, and an OpenAPI doc — see §5. Node is zero-dep and first-class; Python/Go are templated. |
| **`add_route`** | `backend?`, `id`, `method`, `screenOrHandler` | route file/patch | Add one endpoint (a new screen, a `/submit/*` mutation) to a generated backend. |
| **`generate_openapi`** | `screens`, `services` | an `openapi.yaml` `$ref`-ing the schema | Give the backend a typed, Swagger-explorable surface (mirrors `spec/openapi.yaml`) — backend-dev-DX north star ([[project-backend-dx-goal]]). |
| **`mock_data`** | `screen` | a fixture JSON for every `$data.<id>` the screen references | So a generated backend can serve believable data immediately; unblocks preview without a real DB. |
| **`serve_dev`** | `screens?`, `port?` | spawns `spec/tools/serve.mjs` (or the generated server); returns URL | One call to get a live mock backend the app/simulator points at. |

### E. Storage / Data

| Tool | Input | Output | Purpose |
|---|---|---|---|
| **`screen_store`** | `op` (put/get/list/delete), `id`, `doc?`, `store?` (fs/sqlite) | store result | Persist authored screens the way a real backend would — a flat `screens/*.json` dir by default, or a single-table SQLite store matching the on-device cache schema ([11](11-offline-cache-spec.md) §4). Every `put` validates first. |
| **`design_cache_key`** | `source`/`screen` | the resolved cache key + policy + TTL per [11](11-offline-cache-spec.md) | Helper so the agent configures caching correctly instead of guessing the templated-key format. |
| **`plan_state`** | `screen` | the `$state` shape + which nodes read/write each key | Surfaces the client-side state graph so the agent wires two-way bindings (textfield/toggle/slider/ticker) without dangling keys. |

### F. Preview

| Tool | Input | Output | Purpose |
|---|---|---|---|
| **`preview_url`** | `screen` (doc or id) | a URL into the web composer (`/compose`) preloaded with the payload | Render-in-the-loop: the agent (or the human watching) *sees* the screen it built, in the same engine-faithful composer. Closes the "did it actually look right" gap ([[reference-premium-ui-playbook]]). |
| **`snapshot`** | `screen` | a normalized Level-B render-facts JSON (tree/modifiers/geometry/a11y) | Non-visual "screenshot" the agent can reason over — draw order, resolved colors, contrast — to self-critique without a device. Ties to [09](09-conformance-fixtures.md) Level B. |

**Curation note:** that's ~24 tools. Per the "small surface" rule we **stage** them (§6) and gate the rarely-used ones behind a `toolsets` flag (the github-mcp-server pattern) so a default session sees a tight, high-leverage set (~10), not all 24.

---

## 4. Resources — the contract as ambient context

Resources are *attached on demand*, not dumped per call — the progressive-disclosure win. Extend the current 3 families:

| URI | Type | Purpose |
|---|---|---|
| `sdui://schema` *(exists)* | JSON | The full JSON-Schema contract. |
| `sdui://tokens` *(exists)* | JSON | The design token set ($token.* targets). |
| `sdui://guide` *(exists)* | md | `spec/docs/authoring.md`. |
| `sdui://examples/<id>` *(exists)* | JSON | Each example screen. |
| **`sdui://reference/components`** | md | Generated component reference (`gen-reference.mjs` output) — human-grade field docs. |
| **`sdui://reference/actions`** / **`/modifiers`** | md | Same, for the closed action + modifier vocab. |
| **`sdui://patterns/<id>`** | JSON | Minimal snippet per signature interaction (collapsing header, pager, swipe, infinite scroll, chart-scrub). |
| **`sdui://parity`** | md | `PARITY.md` + capability matrix — what's safe cross-platform. |
| **`sdui://backend/<target>`** | md | The backend blueprint (§5) as a readable spec the agent can cite while generating. |
| **`sdui://specs/cache`**, **`/networking`**, **`/patch`** | md | Docs [11](11-offline-cache-spec.md)/[12](12-networking-spec.md)/[13](13-div-patch-spec.md) — so `generate_backend`'s output matches the real contract, not an invented one. |

Resources should be **small and bounded** (the Itential/Toolhost lesson): one concern each, so the agent attaches exactly what a task needs.

---

## 5. Prompts — guided flows

MCP *prompts* are reusable, parameterized playbooks the user picks from a menu. Ship a handful of high-value ones (prompt discipline: few, sharp):

| Prompt | Args | The flow it runs |
|---|---|---|
| **`build_screen`** | `intent`, `platform?` | orient (`list_components`/examples) → `compose_screen` → `lint_screen` → auto-apply fixes → `validate_screen` → `preview_url`. The end-to-end authoring loop. |
| **`scaffold_backend`** | `screens`, `target`, `features` | attach `sdui://backend/*` + cache/networking specs → `generate_backend` → `mock_data` → `serve_dev` → hand back the URL + run instructions. Delivers "their own backend." |
| **`add_pagination`** | `screen` | attach `sdui://patterns/infinite-scroll` → set `limit` binding + `paginateOnScroll` + `onReachEnd` → validate. |
| **`add_offline_support`** | `screen`/`backend` | apply cache policy + bundled fallback + `$env.offline` banner per [11](11-offline-cache-spec.md); wire the resolution chain in the backend. |
| **`make_it_premium`** | `screen` | run `lint_screen` + [[reference-premium-ui-playbook]] pass: rails/hero/scrim/one-accent, token-clean, motion honored. Turns a correct screen into a *beautiful* one. |
| **`port_from_figma`** | `figma_selection` | (bridges the Figma MCP) map frames→archetypes, variables→tokens, then `compose_screen` + lint. The designer-authoring-pain relief ([[feedback-designer-authoring-pain]]). |

---

## 6. The backend-scaffold blueprint — what "their own backend" is

`generate_backend` emits a **complete screen server**. Its contract (readable at `sdui://backend/node`):

**Shape**
```
their-backend/
  server.mjs            # the HTTP server (zero-dep, node:http) — routes below
  screens/*.json        # the screen store (one doc per id) — authored via screen_store
  tokens.json           # the design tokens served at /tokens (+ dark variant)
  fallback/*.json       # bundled last-resort screens (validated at boot) — [11]
  sdui/                 # copied-in: schema + validate.mjs (the ONE validator)
  openapi.yaml          # generated typed surface (Swagger UI at /docs)
  README.md             # run + deploy instructions
```

**Routes** (mirrors `spec/openapi.yaml`, so any client already speaks it):
- `GET /screens/:id?v=&params=` — resolve a screen. **Version-negotiated** (newest ≤ `v`), **validated at boot** (a broken screen 404s, never renders), **cache-policy aware** (serves per-source policy [11](11-offline-cache-spec.md), sends the content hash for 304-style revalidate).
- `GET /tokens?theme=` — the design system; `dark` folds `colorDark.*`.
- `POST /submit/:form` — the endpoint `request` actions hit; applies the **idempotency-key + retry-safe** convention [12](12-networking-spec.md) (dedupe on the `Idempotency-Key` header so a retried POST never double-applies).
- `POST /patch/:id` (opt-in) — returns a **div-patch** [13](13-div-patch-spec.md) instead of a full screen for live updates.
- `GET /healthz`, `GET /docs`, `GET /openapi.yaml`.

**Guarantees baked in** (the four pillars the agent would otherwise miss):
1. **Validation gate** — every screen is run through the *same* `Validator` the device + CI use, at boot and on hot-reload. Invalid never ships.
2. **Resolution chain** — network → cache (last-good) → bundled fallback → error stub ([11](11-offline-cache-spec.md) §1). The client always has something correct.
3. **Transport conventions** — idempotency, retry/backoff, timeouts, ETag revalidation ([12](12-networking-spec.md)) on the mutation + fetch paths.
4. **Hot-reload** — edit a `screens/*.json`, the server re-validates and re-serves; the app re-fetches. Author↔see loop with no restart.

**Minimal Node reference sketch** (what `generate_backend --target node` emits, abridged — real output is complete + commented):

```js
import { createServer } from 'node:http';
import { readFileSync, readdirSync, watch } from 'node:fs';
import { Validator, flattenTokenPaths } from './sdui/validate.mjs';

const tokens = JSON.parse(readFileSync('./tokens.json', 'utf8'));
const tokenPaths = flattenTokenPaths(tokens);
const store = new Map();        // id -> validated screen doc
const fallback = new Map();     // id -> validated bundled screen

function load(dir, into) {       // validate-at-boot gate (pillar 1)
  for (const f of readdirSync(dir).filter(f => f.endsWith('.json'))) {
    const doc = JSON.parse(readFileSync(`${dir}/${f}`, 'utf8'));
    const errs = new Validator(tokenPaths).validate(doc);
    if (errs.length) { console.error(`✗ ${f}`, errs); continue; }   // never serve invalid
    into.set(doc.screen.id, doc);
  }
}
load('./screens', store); load('./fallback', fallback);
watch('./screens', () => load('./screens', store));   // hot-reload (pillar 4)

const seenKeys = new Set();      // idempotency (pillar 3)

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const json = (code, body) => (res.writeHead(code, {'content-type':'application/json'}),
                                res.end(JSON.stringify(body)));
  const m = url.pathname.match(/^\/screens\/([a-z][\w.]*)$/);
  if (m) {                        // resolution chain (pillar 2)
    const doc = store.get(m[1]) ?? fallback.get(m[1]);
    return doc ? json(200, doc) : json(404, { error: 'no screen', detail: m[1] });
  }
  if (url.pathname === '/tokens') return json(200, foldTheme(tokens, url.searchParams.get('theme')));
  const s = url.pathname.match(/^\/submit\/([\w.]+)$/);
  if (s && req.method === 'POST') {
    const key = req.headers['idempotency-key'];
    if (key && seenKeys.has(key)) return json(200, { ok: true, deduped: true });
    if (key) seenKeys.add(key);
    return json(200, { ok: true, id: `${s[1]}_${Date.now()}` });
  }
  if (url.pathname === '/healthz') return json(200, { ok: true });
  json(404, { error: 'not found', detail: url.pathname });
}).listen(process.env.PORT ?? 8787);
```

That's ~60 lines, zero deps, and it *dogfoods the one validator* — the same property that makes `serve.mjs` trustworthy. Python (stdlib `http.server`) and Go (`net/http`) targets follow the same shape from templates + a ported minimal validator (or a `POST /validate` call back to the MCP's during dev).

---

## 7. Prioritized implementation plan

Staged so each phase is independently useful, zero new deps, and the surface stays curated.

**Phase 0 — polish what ships (days).** Bump the protocol string to `2025-11-25`; add `verbosity` to `list_components`/`list_examples`; enrich `list_examples` with `demonstrates`+`tags`; add the generated-reference + `parity` resources. Low-risk, immediate token-efficiency + orientation wins.

**Phase 1 — the quality gate (highest leverage).**
1. **`lint_screen`** — the single biggest new value: turns "valid" into "good" ([[feedback-design-standard]]), with fix-patches. Extends the existing `Validator` machinery, no deps.
2. **`explain_component`** + **`get_component_schema`** — per-node truth, progressive disclosure.
3. **`compose_screen`** — the flagship authoring tool (built on scaffold archetypes + examples + lint). This is the "talk to Claude, get a screen" moment.

**Phase 2 — backend generation (delivers the owner's vision).**
4. **`generate_backend --target node`** + **`mock_data`** + **`serve_dev`** — "clients just have their own backends." Node first (zero-dep), reusing `serve.mjs` as the seed.
5. **`generate_openapi`**, **`screen_store`** — the backend-DX north star ([[project-backend-dx-goal]]).

**Phase 3 — parity + preview confidence.**
6. **`check_conformance`** (wrap `check.mjs`) + **`capability_matrix`** — the cross-platform guarantee, on tap.
7. **`preview_url`** + **`snapshot`** — see-it / self-critique loop.

**Phase 4 — advanced contract features.**
8. **`apply_patch`** ([13](13-div-patch-spec.md)), **`design_cache_key`** ([11](11-offline-cache-spec.md)), **`search_patterns`**, Python/Go backend targets, the `port_from_figma` prompt.

**Cross-cutting:** register prompts (`build_screen`, `scaffold_backend`, `add_pagination`) as each backing tool lands; keep the CI handshake gate green; add a `toolsets` flag so a default session exposes the ~10 core tools and opts into the rest.

---

### Appendix — sources
- Anthropic, *Writing effective tools for AI agents* — https://www.anthropic.com/engineering/writing-tools-for-agents
- Anthropic, *Effective context engineering for AI agents* — https://www.anthropic.com/engineering/effective-context-engineering-for-agents
- MCP best practices — https://modelcontextprotocol.info/docs/best-practices/ ; *Writing effective tools for agents* tutorial — https://modelcontextprotocol.info/docs/tutorials/writing-effective-tools/
- `modelcontextprotocol/servers` (≈60k★) — https://github.com/modelcontextprotocol/servers
- `github/github-mcp-server` (≈20k★, toolsets pattern) — https://github.com/github/github-mcp-server
- `GLips/Figma-Context-MCP` / Framelink (≈9k★) — https://github.com/GLips/Figma-Context-MCP
- Figma official MCP guide (`get_code`/`get_variable_defs`/rules) — https://github.com/figma/mcp-server-guide
- `divkit/divkit` (≈2.6k★, div-patch/cache techniques) — https://github.com/divkit/divkit
- Itential, *Designing MCP servers for infrastructure* (6 principles) — https://www.itential.com/resource/blog/designing-mcp-servers-for-infrastructure/
- *Design patterns in MCP: the Toolhost pattern* — https://glassbead-tc.medium.com/design-patterns-in-mcp-toolhost-pattern-59e887885df3

*(Star counts approximate — research date 2026-07-30; GitHub API rate-limited during authoring.)*
