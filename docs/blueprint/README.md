# SDUI Blueprint — the road to "ideal"

> **North star.** One JSON contract → three pixel-identical native renderers
> (**iOS / Android / Aurora OS**), offline-capable, fully configurable, with the
> native platform docs embedded and an MCP + visual composer on-ramp. Built to a
> bar where **large enterprises ship production Aurora apps** on it.
>
> This folder is the working hub where we collect every audit, doc study, and
> decision. Keep it honest: it is the measurable definition of "done".

---

## Status dashboard (2026-07-29)

| Front | State | Verdict |
|---|---|---|
| **Contract / spec** | schema is single source of truth; validator derives from it; MCP live | Solid foundation |
| **iOS renderer** | 30/30 components, 22/24 actions; `swift build` green; 0 unsafe patterns | **Reference — polished, minor tail** |
| **Android renderer** | 24/30 components, 19/24 actions; builds in CI | **29 discrepancies vs iOS** → [01](01-parity-android.md) |
| **Aurora renderer** | 14/30 components, ~0/24 actions (no runtime) | **Cannot launch as committed** → [02](02-launch-aurora.md) |
| **Web composer** | schema-driven builder; live validation; binding preview just fixed | **Raw → hardening** → [03](03-composer.md) |
| **Offline / local cache** | not designed yet | **Missing pillar** → [04](04-benchmark-and-docs.md) |
| **Embedded platform docs** | not present | **Missing pillar** → [04](04-benchmark-and-docs.md) |

Regenerate the hard numbers with `node spec/tools/parity.mjs > PARITY.md`.

---

## The seven pillars of "ideal"

1. **One contract, three identical renderers.** Any screen JSON renders
   pixel-for-pixel the same on iOS, Android, Aurora. Divergence is a bug.
   → tracked in [01 Android parity](01-parity-android.md), [02 Aurora](02-launch-aurora.md).
2. **Everything configurable.** Every knob (spacing, swipe geometry, colors,
   timeouts) lives in the contract — zero hardcoded magic, zero костыли.
3. **Offline-first / local cache.** A device DB caches screens + data so apps are
   server-built yet resilient; identical cache semantics on every platform.
   → [04](04-benchmark-and-docs.md).
4. **Docs embedded.** Apple HIG/SwiftUI, Android/Compose, Aurora/Qt/Silica
   references live in-repo, mapped to our components. → [04](04-benchmark-and-docs.md).
5. **Benchmark-driven.** We port proven techniques from DivKit / Beagle / Epoxy so
   JSON→UI behavior is defined, not accidental. → [04](04-benchmark-and-docs.md).
6. **On-ramps for every persona.** MCP (talk-to-Claude), visual composer (build by
   hand), Swagger + validator (backend), Figma tokens (design). → [03](03-composer.md).
7. **Provable quality.** Validator = CI = engine; snapshot/conformance fixtures;
   parity matrix gates drift. Nothing ships unverified.

---

## Files in this hub

| File | Purpose |
|---|---|
| [00-current-state.md](00-current-state.md) | Ground-truth audit of all fronts, first-hand + agent-verified |
| [01-parity-android.md](01-parity-android.md) | Every Android-vs-iOS discrepancy, prioritized, with file:line |
| [02-launch-aurora.md](02-launch-aurora.md) | Why Aurora won't launch + the fix + action-runtime plan |
| [03-composer.md](03-composer.md) | Web composer gaps, done/todo, fidelity plan |
| [04-benchmark-and-docs.md](04-benchmark-and-docs.md) | Offline cache design, embedded docs, benchmark repo study |
| [04a-techniques-ledger.md](04a-techniques-ledger.md) | **DivKit/Beagle deep-dive** + cache design + techniques ledger (cited) |
| [05-roadmap.md](05-roadmap.md) | Prioritized sequence to "ideal", with milestones |
| [06-collapsing-scroll.md](06-collapsing-scroll.md) | **Collapsing/parallax scroll** — gap analysis vs best-practice + world-class rebuild plan |

## Working agreement
- **Contract-first, validation-before-render.** No renderer feature without a
  schema field + validator rule + parity-matrix entry.
- **Verify, don't assume.** iOS builds locally; Android on CI push; Aurora needs
  the SDK. State honestly what was checked where.
- **No silent scope cuts.** If a thing is deferred, it's written here, not dropped.
