# 23 — World-class composing & AI-authoring: the plan

> North star ([[project-vision-ecosystem]]): *one shared contract lets any persona enter
> and feel like the others.* The owner's **#1 pain** ([[feedback-designer-authoring-pain]]):
> laying out screens is *"сложно / долго / непонятно"* — hard, slow, unclear. This doc is
> the concrete, prioritized plan to make **both** authoring surfaces world-class: the
> **visual composer** (`spec/compose/index.html`) and the **AI-authoring MCP**
> (`spec/mcp/server.mjs`) — and, crucially, to fuse them so a designer, a PM, or Claude all
> land in the same guard-railed contract.

**Relationship to existing docs.** This is the *umbrella* plan. It does not repeat:
[03](03-composer.md) (composer backlog), [08](08-composer-direct-manipulation.md) (Figma-like
canvas gestures — already fully specced), [17](17-mcp-ai-authoring.md) (the MCP tool set).
It (a) folds their field research into one prioritized roadmap, (b) adds **new** research on
the tools those docs didn't cover, and (c) specifies the two things still missing everywhere:
a concrete **design-lint rule set** and the **AI self-critique loop** that closes composer ↔
MCP into one quality-guaranteed pipeline.

Status: **plan.** Every proposal below is zero-new-dependency and derives from the one
contract (`spec/schema/sdui.schema.json`, `spec/tools/validate.mjs`).

---

## 1. The thesis: three layers, one contract, guaranteed quality

The owner fears misuse at scale ([[feedback-composer-guardrails]]): give people a fast
authoring tool and you also get fast *bad* screens. Every world-class tool we studied solves
this the same way — **quality is enforced by layers, not left to taste.** We already have the
bottom layer (schema validation). The plan adds the two above it, and makes all three fire in
*both* the visual composer and the MCP, so no matter who authors — human dragging on a canvas,
or Claude emitting JSON — the same gates apply.

```
        AUTHORS                         GATES (one implementation, two surfaces)
  ┌─────────────────┐
  │ Designer/PM      │──canvas──┐   ┌────────────────────────────────────────────┐
  │ (spec/compose)   │          ├──▶│ 1. VALIDATE  schema shape + dangling refs   │  (exists, best-in-class)
  ├─────────────────┤          │   │ 2. LINT      design-quality + a11y + tokens  │  ◀── §4, NEW
  │ Claude / Codex   │──JSON────┘   │ 3. CONFORM   cross-platform parity (Level-A) │  (exists in check.mjs, wire in)
  │ (spec/mcp)       │              └────────────────────────────────────────────┘
  └─────────────────┘                        │ every emit passes all three
                                             ▼  contract JSON a device renders identically
```

The single highest-leverage move in this whole plan is **building the lint engine once** (a
pure function over the contract, like `Validator`) and mounting it in *both* the composer's
inspector and the MCP's `lint_screen`. That is what turns "flexible" into "flexible **and**
safe."

---

## 2. What the best tools do — field research (with stars + URLs)

Star counts pulled live via the GitHub API on 2026-07-30.

### 2.1 Visual builders / SDUI playgrounds — what makes authoring *delightful*

| Tool | ★ / link | The delight lever we should steal |
|---|---|---|
| **tldraw** | 49.5k★ · [github.com/tldraw/tldraw](https://github.com/tldraw/tldraw) | The gold standard for *direct manipulation on a canvas* — buttery pointer-capture drags, snapping, selection chrome. Confirms [08](08-composer-direct-manipulation.md)'s overlay approach is the right one. |
| **GrapesJS** | 26.1k★ · [github.com/grapesjs/grapesjs](https://github.com/grapesjs/grapesjs) | Framework-free web builder with a **blocks panel** (drag proven snippets onto the canvas) + **layer manager** + **style manager**. The blocks panel is the missing piece in our composer (see §5 templates). |
| **Mitosis** | 13.9k★ · [github.com/BuilderIO/mitosis](https://github.com/BuilderIO/mitosis) | Builder's compiler: one component IR → many framework outputs. Mirrors our value prop (one JSON → iOS/Android/Aurora). Their lesson: **the IR is the product; editors are views onto it.** |
| **Builder.io** | 8.8k★ · [github.com/BuilderIO/builder](https://github.com/BuilderIO/builder) | Drag-drop visual editor bound to *real code components + data + APIs*; **Visual Copilot** makes designs interactive "using your actual code + data + APIs" via natural language ([builder.io/blog/figma-to-code-visual-copilot](https://www.builder.io/blog/figma-to-code-visual-copilot)). Our analogue: canvas nodes bound to real `$data`/`$state` bindings, not fakes. |
| **Plasmic** | 6.9k★ · [github.com/plasmicapp/plasmic](https://github.com/plasmicapp/plasmic) | "Design freedom without learning HTML/CSS" + **design tokens, components & variants, responsive tokens** as first-class ([plasmic.app/site-builder](https://www.plasmic.app/site-builder)). Confirms tokens must be pickable *everywhere*, not typed. |
| **DivKit** | 2.7k★ · [github.com/divkit/divkit](https://github.com/divkit/divkit) | The SDUI reference. Its **playground** ([divkit.tech/playground](https://divkit.tech/playground)) proves the **round-trip**: edit JSON → live cross-platform preview over websockets → same layout ships everywhere. And DivKit's **`templates`** block — reusable JSON fragments referenced by name — is the SDUI-native way to do "components/variants" (see §5). |
| **Webflow** | — · [help.webflow.com](https://help.webflow.com/hc/en-us/articles/33961243177875-Spacing-margin-and-padding) | On-canvas spacing bands (`⌘⇧D`), `⌥`-drag to scrub numeric inputs, clean-code output. Already captured in [08](08-composer-direct-manipulation.md); listed here for completeness. |
| **FlutterFlow** | — · [docs.flutterflow.io/marketplace](https://docs.flutterflow.io/marketplace/) | Live preview + a **Marketplace** of templates/components you drop in "in seconds." The template-economy lesson for §5. |

**The through-line:** delight = (1) *direct manipulation* on the canvas (tldraw/Webflow/Framer
— [08](08-composer-direct-manipulation.md) covers this), (2) *drop-in blocks/templates* so you
start from a proven pattern not a blank page (GrapesJS/FlutterFlow — §5), (3) *tokens &
components as first-class pickables* (Plasmic — §4/§5), and (4) a *live faithful preview*
(DivKit round-trip — already in our composer).

### 2.2 Figma / Photoshop features worth stealing — and how they map to our contract

The most important realization: **our contract already has the data model these features
operate on.** We're not inventing auto-layout; we're exposing what `vstack`/`hstack`/`modifiers`
already encode.

| Figma/PS feature | Source | Maps to our contract as |
|---|---|---|
| **Auto Layout** (frames that hug/fill content, gap, padding) | [designcode.io/figma-handbook-auto-layout](https://designcode.io/figma-handbook-auto-layout/) | Already native: `vstack`/`hstack` + `spacing` + `modifiers.padding` + `size.mode: hug\|fill\|fixed`. Composer just needs the *on-canvas handles* ([08](08-composer-direct-manipulation.md) §3.3). No contract change. |
| **Constraints** (pin/stretch on resize) | [uxmisfit.com auto-layout+constraints](https://uxmisfit.com/2021/09/27/figma-autolayout-constraints-complete-guide/) | `size.width/height.mode` (fill = stretch, fixed = pin, weight = proportional). Expose as a 9-point constraint picker in the inspector. |
| **Variables + Modes** (light/dark, density as swappable value sets) | [devot.team/blog/figma-responsive-design](https://devot.team/blog/figma-responsive-design) | Our `$token.*` **is** variables; **modes = the dark-token fold** already in the backend (`colorDark.*`, [17](17-mcp-ai-authoring.md) §6). Add a composer **mode toggle** that re-resolves tokens live (we already have a dark toggle — generalize it to any token mode). |
| **Components & Variants** (one source, many states) | [svitla.com auto-layout+variants](https://svitla.com/blog/hacks-creating-designs-with-auto-layout-and-variants-in-figma/) | **Gap today.** SDUI answer = DivKit-style **named templates** (§5.2): a reusable component fragment + a `variant` param. New contract feature, staged. |
| **Smart selection / snapping / measure** | [designcode.io/figma-handbook-smart-selection](https://designcode.io/figma-handbook-smart-selection/) | Overlay guides + token-value snapping — fully specced in [08](08-composer-direct-manipulation.md) §3.5. |
| **Inspect / Dev Mode** (copy resolved values, tokens used) | Figma Dev Mode MCP ([17](17-mcp-ai-authoring.md)) | Our **JSON pane** is the inspector; add a "resolved" view that shows computed px/hex beside each token ref. |
| **Component swap / instance** | — | `custom.*` components + templates; swap = change `type` while keeping props that overlap. |

**Design decision:** the two features that require *contract changes* — per-side padding
(`padding:{top,right,bottom,left}`) and **named templates/variants** — are the only net-new
schema work. Everything else is exposing model we already have. Prioritize accordingly.

### 2.3 Design-lint & guardrails — how quality is guaranteed at scale

Every serious design org runs a **linter** that enforces the system automatically. The
patterns to port:

- **Design Lint** (open-source Figma plugin) — flags "missing text, fill, stroke, and effects
  styles as well as incorrect border radius values"
  ([figma.com/community WCAG checkers hub](https://www.figma.com/community/accessibility/wcag-checkers)).
  → our analogue: literal color/spacing/radius where a `$token` exists.
- **YADL — Yet Another Design Linter** — "instantly checks padding, gap, radius, stroke width,
  fills, strokes, effects, and typography… font family, size, weight, line height, letter
  spacing consistency" ([figma.com/community/plugin/1496477931536811576](https://www.figma.com/community/plugin/1496477931536811576/yet-another-design-linter)).
  → the exact off-token surface our `lint_screen` should cover.
- **FigmaLint** — "AI-powered… audits components for design system compliance, accessibility,
  and developer readiness" ([figma.com/community/plugin/1521241390290871981](https://www.figma.com/community/plugin/1521241390290871981/figmalint)).
  → validates the "AI + lint" pairing we propose in §6.
- **Stark / Contrast** — WCAG contrast + color-blindness simulation + touch-target size
  ([browserstack.com best a11y plugins](https://www.browserstack.com/guide/best-figma-plugins-for-accessibility)).
  → our contrast + tap-target lint rules (§4).

**The standards to encode** (so rules aren't arbitrary):
- **Contrast:** text must hit **4.5:1** (normal) / **3:1** (large ≥24px, or ≥19px bold)
  ([W3C WCAG 2.2 SC 1.4.3](https://www.w3.org/TR/WCAG22/); [testparty.ai contrast guide](https://testparty.ai/blog/wcag-contrast-ratio-guide-2025)).
- **Tap targets:** WCAG 2.2 AA **Target Size (Minimum) = 24×24 CSS px** (SC 2.5.8); platform
  guidance is stricter — Apple HIG **44×44pt**, Material **48×48dp**. Lint to the platform
  numbers, cite the SC ([aaardvarkaccessibility.com 2.5.5](https://aaardvarkaccessibility.com/wcag-plain-english/2-5-5-target-size-enhanced/)).
- **Spacing:** the 4/8-pt grid — non-grid magic numbers are a smell (matches YADL's gap/padding
  checks).

### 2.4 AI authoring — how to make Claude/Codex emit *great* JSON fast

The research is unambiguous and directly actionable:

- **Structured intermediate representation + reflection loop.** *GameUIAgent* runs a six-stage
  pipeline: NL intent → **Design-Spec JSON** → post-process → render → **VLM quality review** →
  **Reflection Controller** that loops until good ([arxiv 2603.14724](https://arxiv.org/html/2603.14724v1)).
  Our Design-Spec JSON already exists — it's the contract. We're missing the *review + reflect*
  stages.
- **Self-critique beats one-shot.** *SCGG (Self-Critique looping for GUI Generation)*: an LLM
  that critiques its own output then refines produces measurably better GUIs than asking for a
  refinement directly ([arxiv 2412.11328, zero-shot GUI generation](https://arxiv.org/pdf/2412.11328)).
  → the MCP must give the model a *machine critique* to reflect on: that's `lint_screen`.
- **Only feed the relevant sub-schema.** To avoid hallucination on large schemas, "only
  user-selected sub-schemas are provided as context, enabling precise and modular editing"
  ([arxiv 2508.05192](https://arxiv.org/html/2508.05192v2)). → validates [17](17-mcp-ai-authoring.md)'s
  progressive-disclosure `get_component_schema`/`explain_component` over dumping the 700-line
  schema.
- **Intent clarification before generation.** Leading UI-gen work adds an *intent-clarification*
  step so the model asks the one disambiguating question instead of guessing
  ([arxiv 2412.20071](https://arxiv.org/html/2412.20071v3)). → `compose_screen` should return
  `clarify[]` when intent is under-specified, not silently pick.
- **Structured critique output + iteration limit.** Best practice: critique agent returns JSON,
  with hard iteration caps and quality thresholds to avoid infinite loops
  ([reflective loop pattern](https://medium.com/@vpatil_80538/reflective-loop-pattern-the-llm-powered-self-improving-ai-architecture-7b41b7eacf69)).
  → `lint_screen` already returns structured `{severity,path,rule,fix}`; the loop caps at N.
- **Component mapping is the differentiator.** Builder's Visual Copilot's headline advantage is
  mapping designs to *real* components ([builder.io/blog/best-figma-to-code-plugin](https://www.builder.io/blog/best-figma-to-code-plugin)).
  → `port_from_figma` must map Figma frames → our archetypes/templates, variables → `$token.*`.

### 2.5 Templates & starters — how top systems kill the blank page

- **FlutterFlow Marketplace** — pre-built templates/components applied "in seconds"
  ([docs.flutterflow.io/marketplace](https://docs.flutterflow.io/marketplace/)); a whole
  template economy ([templates.flutterflow.app](https://templates.flutterflow.app/)).
- **GrapesJS blocks panel** — drag proven snippets onto the canvas ([grapesjs.com](https://github.com/grapesjs/grapesjs)).
- **DivKit `templates`** — reusable JSON fragments referenced by name; the SDUI-native
  component mechanism ([pub.dev/packages/divkit](https://pub.dev/packages/divkit)).

→ We need **both**: a *blocks/snippets panel* in the composer (drop a hero, a rail, a form) and
a *pattern library* the MCP can search (`search_patterns`, [17](17-mcp-ai-authoring.md)), backed
by the same JSON fragments so a human and Claude reach for the identical proven building blocks.

---

## 3. Gaps today (both surfaces), consolidated

| Area | Composer (`spec/compose`) | MCP (`spec/mcp`) |
|---|---|---|
| Schema validation | ✅ live, same `Validator` | ✅ `validate_screen` |
| **Design-lint** | ❌ none (backlog in [03](03-composer.md)) | ❌ none |
| **Direct manipulation** | ⚠️ specced not built ([08](08-composer-direct-manipulation.md)) | n/a |
| **Templates / blocks** | ❌ no blocks panel | ⚠️ `scaffold_screen` (4 kinds only) |
| **Bind-aware editing** | ❌ types raw `$data.*` | ⚠️ no `bind_data` helper |
| **Components/variants** | ❌ | ❌ (no template mechanism) |
| **AI compose + critique loop** | n/a | ❌ only `validate`, no `compose`/`lint`/reflect |
| **Preview ↔ AI bridge** | ✅ live preview | ❌ no `preview_url` back into composer |
| **Conformance / parity gate** | ❌ not surfaced | ⚠️ `check.mjs` exists, not wired |

The two red columns that appear in *both* rows — **design-lint** and **AI compose+critique** —
are the highest-leverage builds because one implementation serves both surfaces.

---

## 4. The design-lint rule set (build once, mount in composer + MCP)

**Architecture.** A new `spec/tools/lint.mjs` exporting `class Linter { lint(doc, {tokens}) →
[{severity, path, rule, message, fix?}] }`, structured exactly like `Validator` — pure, zero-dep,
derives from the schema + tokens. Mounted as: composer inspector badges (inline, per-node) **and**
MCP `lint_screen`. `fix` is a div-patch ([13](13-div-patch-spec.md)) the composer can one-click
apply and the AI can auto-apply in its reflect loop.

**Severities:** `error` (blocks premium/ships bad UX), `warn` (off-system), `info` (nudge).

### The rules (v1 — concrete, each maps to a research source)

| Rule id | Severity | Fires when | Auto-fix |
|---|---|---|---|
| `token/literal-color` | warn | A `color`/`background` is a literal (`#FF0000`, `rgb(...)`) and a token resolves to the same/near value | replace with `$token.color.*` |
| `token/literal-spacing` | warn | `spacing`/`padding` is a raw number matching a `$token.spacing.*` value | replace with the token |
| `token/off-grid-spacing` | info | Raw spacing/padding not on the 4/8-pt scale (YADL parity) | snap to nearest token |
| `token/literal-radius` | warn | `cornerRadius` literal that matches `$token.radius.*` | replace with token |
| `a11y/contrast` | error | Resolved text vs background < **4.5:1** (or <3:1 for large ≥24px / ≥19px bold) — [WCAG 1.4.3](https://www.w3.org/TR/WCAG22/) | suggest nearest passing token pair |
| `a11y/tap-target` | warn | Tappable (`onTap`/`button`) whose resolved size < **44×44pt** (iOS) / **48dp** (Android) — [WCAG 2.5.8](https://aaardvarkaccessibility.com/wcag-plain-english/2-5-5-target-size-enhanced/) | add min-size modifier |
| `a11y/missing-label` | warn | `image`/icon-only `button` with no `accessibilityLabel` | prompt for label |
| `a11y/text-scale` | info | Font size hard-set below 11pt or dynamic-type opted out | use `$token.typography.*` |
| `layout/image-no-aspect` | warn | `image` without `aspectRatio`/fixed height → layout jump (CLS) | add `loader.aspectRatio` |
| `layout/list-no-empty` | warn | `list`/`async` list with no `empty` state | scaffold an empty state |
| `layout/unbounded-text` | info | Text in an `hstack` with no truncation and a sibling that can grow | add `lineLimit` |
| `action/button-no-ontap` | error | `button` with neither `onTap` nor disabled state | flag dead control |
| `action/dangling-binding` | error | `$state.x` read but never in `state`/never written (extends `Validator`'s `$data` check to `$state`) | declare/init the key |
| `premium/one-accent` | info | > 2 distinct accent colors on one screen ([[reference-premium-ui-playbook]] "one accent") | consolidate |
| `premium/rainbow` | warn | ≥ 4 saturated hues competing ([[feedback-design-standard]] "no rainbow") | reduce palette |
| `premium/spinner-for-content` | info | `spinner` used where a `skeleton` fits (content-shaped load) | swap to skeleton |
| `premium/hierarchy` | info | No single dominant type size — flat hierarchy | promote a hero element |

**Why these, and not more:** each is *deterministic* (no taste calls), *auto-fixable* or
*clearly explainable*, and *cited* to either WCAG or the owner's own standards
([[feedback-design-standard]], [[reference-premium-ui-playbook]]). Rules ship behind a `rules?`
filter so teams can tune severity, and each has an `explain_diagnostic` entry (the "teach, don't
just block" guardrail from [[feedback-composer-guardrails]]).

**Contrast math note:** the linter needs a token→RGB resolver (reuse the composer's `tok()`) and
the WCAG relative-luminance formula — ~20 lines, no dep. This unlocks both `a11y/contrast` and
`premium/*` palette rules.

---

## 5. Templates, blocks & the components/variants gap

### 5.1 Composer: a Blocks panel (GrapesJS pattern)

Add a left-rail **Blocks** tab beside Layers: a grid of proven fragments — *Hero image + title +
CTA*, *Section rail (horizontal scroll)*, *Form field group*, *Stat row*, *Empty state*, *Paywall
card*, *List cell*. Each block is a JSON subtree (validated + lint-clean by construction) you drag
onto the canvas; it reuses the existing `reparent` insert path from [08](08-composer-direct-manipulation.md).
Blocks live as files in `spec/patterns/*.json` so they're the **single source** shared with the MCP.

### 5.2 The contract change: named templates + variants (the components gap)

The one genuinely missing capability (§2.2). Adopt the **DivKit `templates` model**, SDUI-native:

```jsonc
{
  "version": "0.1",
  "screen": {
    "id": "shop",
    "templates": {                       // NEW: reusable, named component fragments
      "product_card": {
        "params": ["title", "price", "image", "variant"],   // variant: "compact" | "hero"
        "component": { "type": "vstack", "children": [ /* … uses $param.title etc. */ ] }
      }
    },
    "content": { "type": "list", "items": "$data.products.list",
      "template": { "type": "$template.product_card",       // instance
                    "bind": { "title": "$item.title", "variant": "compact" } } }
  }
}
```

- **Author once, instance many** — the Figma "component + variants" win, expressed as JSON.
- **Validator/lint extension:** resolve `$template.*` and `$param.*` refs like `$data.*` (a
  dangling template ref or unbound required param is an error). Renderers expand templates at
  parse time (same as DivKit) — **no per-platform renderer work beyond a resolve step.**
- **Staged:** ship the composer Blocks panel first (no contract change), then templates/variants
  as a schema addition once the fragment library proves the patterns.

### 5.3 MCP: the pattern library is the same files

`search_patterns` and `scaffold_screen`'s enriched archetypes ([17](17-mcp-ai-authoring.md) §3)
read `spec/patterns/*.json` — the identical fragments the composer's Blocks panel drops. **One
library, two doors.** This is the ecosystem-vision payoff: the designer's drag-drop block and
Claude's `search_patterns "hero"` return byte-identical, guaranteed-clean JSON.

---

## 6. The AI self-critique loop — the MCP's flagship capability

This is what the research (§2.4) says separates good AI authoring from great, and it's the one
thing [17](17-mcp-ai-authoring.md) implies but doesn't name as a primitive. Add it as an MCP
**prompt** `build_screen` that orchestrates existing/new tools into the *reflection loop*:

```
compose_screen(intent)            → draft JSON  (+ clarify[] if under-specified — intent clarification)
  ↓
validate_screen(draft)            → hard errors? patch & retry (cap 3)
  ↓
lint_screen(draft)                → structured diagnostics {severity,path,rule,fix}
  ↓
apply auto-fixes; for non-auto     → model reflects on the critique and revises   ← SCGG self-critique
  ↓  (loop until 0 errors + 0 lint-errors, or N=4 iterations — bounded)
check_conformance(draft)          → Level-A parity (wrap spec/conformance/check.mjs)
  ↓
preview_url(draft)                → hand back a live composer URL to SEE it
```

Key design points from the research:
- The critique the model reflects on is **machine-generated** (`lint_screen` JSON), not vibes —
  this is exactly why SCGG works ([arxiv 2412.11328](https://arxiv.org/pdf/2412.11328)).
- **Bounded**: iteration cap + "0 errors" threshold ([reflective loop pattern](https://medium.com/@vpatil_80538/reflective-loop-pattern-the-llm-powered-self-improving-ai-architecture-7b41b7eacf69)).
- **Intent clarification** up front prevents wasted loops ([arxiv 2412.20071](https://arxiv.org/html/2412.20071v3)).
- The eval harness = the conformance corpus ([09](09-conformance-fixtures.md)): "given intent X,
  does the loop's output pass Level-A + 0 lint-errors?" — measurable authoring quality.

### New/confirmed MCP tools this doc adds or sharpens (beyond [17](17-mcp-ai-authoring.md))

| Tool | Status vs [17] | Why it's here |
|---|---|---|
| `lint_screen` | **confirmed #1 priority** | The critique signal for the loop **and** the composer's guardrail. Shared `lint.mjs` (§4). |
| `compose_screen` | **add `clarify[]` output** | Intent-clarification step — returns questions when under-specified instead of guessing. |
| `suggest_fix` | **new** | Given a lint diagnostic id + screen, return the div-patch fix — lets the model apply critiques atomically. |
| `preview_url` | confirmed | Closes see-it loop; bridges MCP → composer (`/compose?doc=…`). |
| `bind_data` | confirmed | Guarantees `$data`/`$state` wiring — feeds the bind-aware inspector too. |
| `search_patterns` | confirmed, **shared files** | Same `spec/patterns/*.json` as composer Blocks (§5.3). |

---

## 7. Bridge the two surfaces (the ecosystem payoff)

The composer and MCP must feel like one tool:

1. **`preview_url` → composer deep-link.** MCP emits `/compose?doc=<base64|id>`; the composer
   loads it (it already restores from `localStorage` — add a URL/`?doc=` loader). Claude builds,
   the human *sees and tweaks* in the same faithful preview.
2. **Composer "Ask Claude" affordance.** An inspector button that packages the selected subtree +
   intent and (in a Claude Code / Desktop session) round-trips through `compose_screen`/`lint_screen`.
   The designer stuck on layout gets AI help *in place* — direct relief for the #1 pain.
3. **Shared lint = shared verdict.** The badge a designer sees on a node and the diagnostic Claude
   reflects on are the *same rule id* from the *same engine*. No drift, one source of truth for
   "is this good."

---

## 8. Prioritized roadmap (zero new deps, staged)

**Phase A — the quality engine (highest leverage, unblocks everything).**
1. `spec/tools/lint.mjs` — the rule set in §4 (start with `a11y/contrast`, `token/literal-*`,
   `action/button-no-ontap`, `layout/image-no-aspect`, `premium/one-accent`). Pure function +
   token→RGB + WCAG luminance.
2. Mount it: MCP `lint_screen` (+ `explain_diagnostic`, `suggest_fix`) **and** composer inline
   badges (backlog item already in [03](03-composer.md)).

**Phase B — kill the blank page.**
3. `spec/patterns/*.json` fragment library (hero/rail/form/stat/empty/paywall/cell).
4. Composer **Blocks panel** (drag to insert) + MCP `search_patterns` reading the same files.

**Phase C — the AI loop.**
5. `compose_screen` (with `clarify[]`) + the `build_screen` reflection prompt (§6), bounded, eval'd
   on the conformance corpus.
6. `preview_url` deep-link + composer `?doc=` loader (the bridge, §7.1).

**Phase D — direct manipulation & components.**
7. Ship [08](08-composer-direct-manipulation.md) top-5 (overlay + selection chrome, padding/gap
   handles, hover pre-highlight, drag-reorder, token snapping).
8. Contract: per-side padding, then named **templates/variants** (§5.2) + validator/lint support.

**Cross-cutting:** bind-aware inspector (autocomplete `$data`/`$state`), `check_conformance` wired
into both surfaces, `explain_*` teaching tools, mode toggle generalization.

---

## Top 8 authoring improvements to build, ranked

1. **`spec/tools/lint.mjs` — one design-lint engine, mounted in composer + MCP.** The single
   highest-leverage build: turns "valid" into "good," gives the AI its critique signal and the
   designer live guardrails from *one* rule set. Everything else compounds on it.
2. **The design-lint rule set (§4): contrast (WCAG 4.5:1), off-token color/spacing/radius, tap-target,
   button-no-onTap, image-no-aspect, one-accent.** Deterministic, auto-fixable, cited — this is the
   "guarantee quality at scale" the owner fears missing.
3. **AI self-critique loop (`build_screen`): compose → validate → lint → reflect → conform → preview,
   bounded.** The research-proven way (SCGG/GameUIAgent) to make Claude emit *great* JSON, not just
   valid JSON.
4. **Shared pattern/blocks library (`spec/patterns/*.json`) → composer Blocks panel + MCP
   `search_patterns`.** Kills the blank page for *both* personas from identical, guaranteed-clean
   fragments (GrapesJS/FlutterFlow pattern).
5. **`compose_screen` with intent-clarification (`clarify[]`) + `suggest_fix`.** Ask the one
   disambiguating question and apply critiques atomically — the flagship "talk to Claude, get a
   screen" tool.
6. **On-canvas direct manipulation (ship [08](08-composer-direct-manipulation.md) top-5).** Padding/gap
   drag-handles + selection chrome + hover + drag-reorder + token snapping — the Figma-defining feel
   that makes layout *fast and clear*.
7. **`preview_url` bridge + composer "Ask Claude" button.** Fuse the two surfaces so AI output is
   seen/tweaked in the faithful preview and a stuck designer gets AI help in place — the direct
   answer to "hard/slow/unclear."
8. **Named templates + variants in the contract (DivKit model).** The one missing Figma-grade
   capability — author a component once, instance it everywhere — expanded at parse time so it costs
   near-zero renderer work.

---

### Appendix — sources (research 2026-07-30; stars via GitHub API)

**Builders/SDUI:** tldraw 49.5k★ https://github.com/tldraw/tldraw · GrapesJS 26.1k★ https://github.com/grapesjs/grapesjs · Mitosis 13.9k★ https://github.com/BuilderIO/mitosis · Builder.io 8.8k★ https://github.com/BuilderIO/builder · Plasmic 6.9k★ https://github.com/plasmicapp/plasmic · DivKit 2.7k★ https://github.com/divkit/divkit · DivKit playground https://divkit.tech/playground · Plasmic site builder https://www.plasmic.app/site-builder · Builder Visual Copilot https://www.builder.io/blog/figma-to-code-visual-copilot · Webflow spacing https://help.webflow.com/hc/en-us/articles/33961243177875-Spacing-margin-and-padding · FlutterFlow marketplace https://docs.flutterflow.io/marketplace/ · FlutterFlow templates https://templates.flutterflow.app/

**Figma/Photoshop features:** Auto Layout https://designcode.io/figma-handbook-auto-layout/ · Constraints https://uxmisfit.com/2021/09/27/figma-autolayout-constraints-complete-guide/ · Variables & Modes https://devot.team/blog/figma-responsive-design · Variants https://svitla.com/blog/hacks-creating-designs-with-auto-layout-and-variants-in-figma/ · Smart selection https://designcode.io/figma-handbook-smart-selection/

**Design-lint & a11y:** Design Lint / WCAG hub https://www.figma.com/community/accessibility/wcag-checkers · YADL https://www.figma.com/community/plugin/1496477931536811576/yet-another-design-linter · FigmaLint https://www.figma.com/community/plugin/1521241390290871981/figmalint · Stark/Contrast list https://www.browserstack.com/guide/best-figma-plugins-for-accessibility · WCAG 2.2 https://www.w3.org/TR/WCAG22/ · Contrast guide https://testparty.ai/blog/wcag-contrast-ratio-guide-2025 · Target size 2.5.x https://aaardvarkaccessibility.com/wcag-plain-english/2-5-5-target-size-enhanced/

**AI authoring:** GameUIAgent https://arxiv.org/html/2603.14724v1 · Zero-shot GUI gen / SCGG https://arxiv.org/pdf/2412.11328 · Intent clarification https://arxiv.org/html/2412.20071v3 · Sub-schema context https://arxiv.org/html/2508.05192v2 · Reflective loop pattern https://medium.com/@vpatil_80538/reflective-loop-pattern-the-llm-powered-self-improving-ai-architecture-7b41b7eacf69 · Builder best figma-to-code https://www.builder.io/blog/best-figma-to-code-plugin
