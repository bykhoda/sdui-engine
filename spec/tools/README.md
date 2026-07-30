# `spec/tools` — the SDUI toolchain

Zero-dependency, pure-function tools over the one contract (`spec/schema/`). Each is a
CLI **and** an importable module, so the same logic drives CI, the MCP server
(`spec/mcp/`), and the visual composer (`spec/compose/`) — one source of truth, no drift.

| Tool | What it answers | Entry |
|---|---|---|
| `validate.mjs` | *Is this a legal contract?* — schema shape, unknown types, dangling `$data`/`$token` refs | `Validator`, `flattenTokenPaths` |
| `lint.mjs` | *Is this a **good** screen?* — off-token literals, WCAG contrast, tap-targets, dead controls, palette cohesion | `lint(doc, tokens)` |

Lint is the layer **above** validation (see `docs/blueprint/23-composer-and-authoring.md` §4):
validation gates legality, lint gates quality. Both are mounted in the MCP so Claude/Codex
get the same guardrails a designer sees inline in the composer.

## `lint.mjs`

```bash
# Lint one or many screens (defaults to spec/schema/tokens.example.json):
node spec/tools/lint.mjs ios/Sources/SDUIPlayground/Content/screens/*.json

# Pick a brand's tokens; fail CI on any error-severity finding:
node spec/tools/lint.mjs --tokens spec/schema/tokens.example.json --strict screen.json
```

```js
import { lint } from './spec/tools/lint.mjs';
const { findings } = lint(doc, tokens);
// findings: [{ rule, severity, path, message, fix? }]
```

Every finding is **deterministic** and either auto-fixable or clearly explainable — no
taste calls. `fix`, when present, is a minimal RFC-6902-style patch
(`{ op, path, value }`, `path` a JSON Pointer) the composer applies in one click and the
AI auto-applies in its reflect loop.

### The rule set (v1)

| Rule id | Severity | Fires when | Auto-fix |
|---|---|---|---|
| `token/literal-color` | warn | a raw hex equals a `$token.color.*` value | replace with the token |
| `token/literal-spacing` | warn | a raw `spacing`/`padding` number equals a `$token.spacing.*` value | replace with the token |
| `token/literal-radius` | warn | a raw `cornerRadius` equals a `$token.radius.*` value | replace with the token |
| `token/off-grid-spacing` | info | a raw spacing/padding off the 4/8-pt grid | — (nudge) |
| `a11y/contrast` | error / warn | text vs its **explicit** background below WCAG AA (4.5:1 normal, 3:1 large ≥24px/≥19px-bold). `error` below 3:1 (fails at any size), else `warn` | swap to the strongest same-role token that passes |
| `a11y/tap-target` | warn | a tappable control with a fixed side < 44pt effective (Apple HIG; WCAG 2.5.8) | add `hitSlop` to reach 44 |
| `action/button-no-ontap` | error | a `button` with no `onTap` — a dead control | — (flag) |
| `layout/image-no-aspect` | warn | an `image` with neither `loader.aspectRatio` nor a fixed height (layout jump / CLS) | add `loader.aspectRatio` |
| `premium/one-accent` | info | > 2 distinct accent **hues** on one screen | — (consolidate) |
| `premium/rainbow` | warn | ≥ 4 competing saturated hues | — (reduce palette) |

**Tuning notes (why it's useful, not noisy).** `a11y/contrast` is judged **only against an
explicitly-set opaque background**, never the implicit screen default: assuming white would
both flood on the design system's own muted-secondary pairings and false-positive wherever
the real backdrop is a gradient/image/material/translucent fill we can't resolve (white text
would read as white-on-white). Translucent fills (`#RRGGBBAA`, alpha < 255) are treated as
ambiguous for the same reason. A node's **own** opaque background is applied before judging
its own text (so a white-on-primary chip is measured against primary, not its gray track).

## `lint_screen` (MCP)

Registered in `spec/mcp/server.mjs` alongside `validate_screen`:

- **`lint_screen`** — `{ payload, minSeverity?: 'error'|'warn'|'info', rules?: string[] }`
  → `{ ok, summary: {error,warn,info}, findings }`. Run it after `validate_screen`; reflect
  on the findings and apply the `fix` patches.
- **`list_lint_rules`** — the catalogue above (id, severity, rationale) for discovery.

```jsonc
// .mcp.json
{ "mcpServers": { "sdui": { "command": "node", "args": ["spec/mcp/server.mjs"] } } }
```
