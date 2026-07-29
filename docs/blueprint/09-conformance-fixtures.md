# 09 — Conformance fixtures: making "identical on every platform" provable

**The single highest-leverage lever in this whole project.** Today "iOS, Android and
Aurora render the same JSON identically" is a *claim*, checked by eyeballing. DivKit's
real superpower (see [04a](04a-techniques-ledger.md)) is that it is *testable*: one
shared corpus of fixtures every client must pass. This doc specifies ours.

> North star this serves: *a screen assembles on the client perfectly and identically
> everywhere.* Without a shared corpus, every new component/modifier silently drifts.

---

## 1. What a fixture is

A directory under `spec/conformance/fixtures/<id>/`:

```
fixtures/button-onTap-toast/
  screen.json      # a minimal SDUI screen (or fragment) exercising ONE thing
  tokens.json      # tokens it resolves against (or a $ref to a shared set)
  state.json       # optional seed state / data / env / item
  expect.json      # platform-neutral assertions about the result
  steps.json       # optional: an interaction script (tap node X, then assert)
```

Fixtures are **small and single-purpose** (one component, one modifier, one action,
one binding rule) — plus a handful of **whole-screen** fixtures (the 25 shared app
screens) as integration coverage.

## 2. Two conformance levels

**Level A — contract conformance (pure, fast, run everywhere incl. CI-JS).**
No rendering. Tests the deterministic contract logic that MUST be bit-identical:
- **Validation**: does `screen.json` pass/fail the schema exactly as `expect.validation` says.
- **Binding resolution**: `$token/$data/$state/$item/$env` + expressions resolve to the
  exact strings/values in `expect.bindings` (given `state.json`).
- **Condition evaluation**: each `Condition` → the boolean in `expect`.
- **Action interpretation**: running `steps.json` (e.g. "dispatch action A") yields the
  exact `expect.effects` — state mutations, navigation stack ops, analytics events,
  toast messages — as an ordered list. (This is why iOS/Android/Aurora field names were
  reconciled: `delay.seconds`, `scrollTo.target`, etc.)
- **div-patch application** (once adopted): applying a patch to a tree → `expect.tree`.

Level A is checkable by a **reference JS implementation** (`spec/conformance/check.mjs`)
AND by each native platform's unit tests loading the same fixtures. Same fixture, same
asserted output, three languages.

**Level B — render/layout conformance (per-platform snapshot).**
Pixels differ by device, so we DON'T assert pixels. We assert **layout facts** within a
tolerance, captured from each platform's real render:
- node **draw order** and parent/child structure of the realized view tree,
- each node's **resolved modifiers** (padding, spacing, corner, color hex, font
  size/weight, opacity) — the values, not the bitmap,
- **measured geometry** within tolerance (relative order/alignment, size ratios), not
  absolute pt,
- **visibility** under a given state (`presentWhen`, conditional children),
- **accessibility** label/role/value per node (VoiceOver ⇄ TalkBack parity).

Each platform has a test that renders the fixture headlessly and emits a normalized
`actual.json`; the harness diffs it against `expect.render.json`. Reference screenshots
(PNG) are kept per platform for human review but are NOT the pass/fail gate (that's the
normalized facts) — this avoids flaky pixel diffs while still catching real drift.

## 3. Assertion schema (`expect.json`)

```jsonc
{
  "validation": { "valid": true },              // or { valid:false, errorContains:"…" }
  "bindings": { "$state.count": "3", "title": "Hello Ann" },
  "conditions": [{ "expr": {"exists":"$state.user"}, "value": true }],
  "effects": [                                   // ordered outcome of steps.json
    { "type": "setState", "key": "open", "value": true },
    { "type": "analytics", "event": "cta_tap" },
    { "type": "navigate", "to": "detail", "transition": "push" }
  ],
  "render": {                                    // Level B, per fixture (optional)
    "tree": ["vstack", ["text#title", "button#cta"]],
    "modifiers": { "title": { "font": {"size":22,"weight":700}, "color":"#111111" } },
    "geometry": { "cta": { "belowOf":"title", "fillsWidth":true } },
    "a11y": { "cta": { "role":"button", "label":"Continue" } }
  }
}
```

Everything is platform-neutral. A renderer either produces these facts or it's
non-conformant — no interpretation room.

## 4. Harness & layout

```
spec/conformance/
  fixtures/<id>/…            # the corpus
  schema/expect.schema.json  # validates expect.json itself
  check.mjs                  # Level-A reference runner (Node, zero-dep)
  README.md
ios/Tests/ConformanceTests   # loads fixtures, runs Level A + B, asserts
android/sdui/src/test/…/Conformance
aurora/tests/conformance     # (Qt Test / a QML harness)
```

- `check.mjs` walks every fixture, runs Level A, prints a table + non-zero exit on any
  miss. Runs in the existing `contract` CI job (fast, no devices).
- Each platform's test target runs the SAME fixtures in its own language for Level A
  (proves the native interpreter matches the reference) + Level B render facts.
- **CI gate:** a fixture failing on ANY platform (or the JS reference) is red. Adding a
  component/modifier/action WITHOUT a fixture is also flagged (coverage check vs the
  schema enum — every `Action` kind, every `Modifiers` key, every component type must
  have ≥1 fixture).

## 5. Seed corpus (first pass)

1. **Per component** (29): one minimal fixture each rendering with representative props.
2. **Per modifier** (the full `Modifiers` set incl. the 8 just reconciled): padding,
   spacing, shadow, material, blur, rotation, pulse, scale, opacity, cornerRadius,
   frame/size, safeArea, presentWhen, hitSlop — each asserting resolved values.
3. **Per action** (24): dispatch → `expect.effects`. Especially `sequence`/`parallel`/
   `condition`/`delay` ordering, `setState`/`increment` math, `navigate` transitions.
4. **Binding rules**: token refs, dark-mode (`colorDark`), `$data`/`$state`/`$item`/
   `$env`, expressions, missing-key fallbacks.
5. **Whole-screen**: the 25 shared content screens (already schema-valid) as Level-A +
   Level-B integration fixtures.

## 6. Golden generation & review

- Author `screen.json` + `state.json`; run `check.mjs --emit` to *propose* an
  `expect.json` from the JS reference; a human reviews and commits it (goldens are
  reviewed, never blindly regenerated — a diff to a golden is a design decision).
- Level-B `actual.json` from each platform is emitted by the test in an `--update` mode;
  reviewed on first add and whenever an intentional visual change lands.

## 7. Sequence to build (small, incremental)

1. ✅ **DONE 2026-07-29** — `check.mjs` (Level A) running in the `contract` CI job with
   7 seed fixtures, all green. **All four core Level-A aspects implemented:**
   **validation** (reuses the production `Validator`), **bindings** + **conditions**
   (`binding.mjs`, a faithful port of `BindingEngine`/`Condition`), and **effects**
   (`action.mjs`, a faithful port of `ActionInterpreter` — analytics-first ordering,
   sequence/parallel, condition branching, setState/increment state mutation, navigate/
   toast/etc. as ordered effects). Only `render` (Level B) remains. Next: `expect.schema.json`,
   grow the corpus to full per-component/modifier/action coverage + the coverage gate,
   then port these same fixtures into the iOS/Android/Aurora test targets.
2. ✅ **iOS DONE 2026-07-29** — `SDUIConformanceTests` runs bindings/conditions/effects
   against the SAME fixtures through the real `BindingEngine`/`Condition`/`ActionInterpreter`
   (via a recording `ActionHost`); green in `swift test` (31 tests total). **This already
   paid off:** it caught a bug in the JS reference — `action.mjs` was mutating `ctx` on
   `setState`/`increment`, but iOS runs against a *snapshot* (a write doesn't feed forward
   into a later condition in the same sequence). Reference corrected to match native.
   **Design note:** whether `setState` *should* feed forward within one action run is a
   real product question — but all engines currently agree it doesn't, which is what
   conformance enforces. Next: Android, then Aurora, run the same fixtures.
3. Grow the corpus to full per-component/modifier/action coverage + the coverage gate.
4. Level B render-facts on iOS first (reference renderer), then Android/Aurora.
5. Tie the **composer preview** to the same corpus so "the composer looks like the
   device" becomes a *tested* property, not a hope (see [08](08-composer-direct-manipulation.md)).

## 8. Why this ranks #1

Every other pillar (parity, new components, div-patch, the composer's fidelity) is only
*trustworthy* if a shared corpus proves it. It converts "should be identical" into a
red/green signal on every PR — the only scalable way to keep three renderers honest.
