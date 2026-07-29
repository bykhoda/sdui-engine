# 10 — Capability coverage matrix (maximal universalization)

Makes *"express every native mobile technique as one contract, identical on every
platform"* **measurable** instead of a slogan. One row per capability; a cell says how
far each renderer implements the shared contract for it.

**Legend:** ✅ implemented + at parity · 🟡 partial / approximate · ⬜ not started ·
🔬 spec/plan only · — n/a. **Truth for components/actions/modifiers is the generated
[`PARITY.md`](../../PARITY.md)** (`node spec/tools/parity.mjs`); this doc adds the wider
native surface parity.mjs doesn't yet track, and is hand-maintained until it does.

> Rule: a capability is "done" only when it is ✅ on all three **and** has a
> [conformance fixture](09-conformance-fixtures.md). Anything else is in progress.

---

## A. UI components (contract: `components`)
Source of truth: PARITY.md. Summary as of 2026-07-29: iOS 29/29 · Android ~18/29 ·
Aurora ~12/29. The gap list per platform lives in [01](01-parity-android.md) /
[02](02-launch-aurora.md). Each component needs a per-component conformance fixture.

## B. Layout, scroll & signature motion
| Capability | iOS | Android | Aurora | Notes |
|---|---|---|---|---|
| stacks / grid / zstack / list | ✅ | 🟡 | 🟡 | sizing model must match (fixed/fill/wrap) |
| **collapsing scroll** (header/hero/pinned/behavior) | 🟡 | ⬜ | ⬜ | iOS double-title fixed 2026-07-29; P1/P2 polish + port pending — [06](06-collapsing-scroll.md) |
| swipe-to-reveal row actions | ✅ | ⬜ | ⬜ | Android #2 |
| press-feedback (scale+dim+haptic) | ✅ | 🟡 | ⬜ | Android in-flight |
| pager / story rings / segmented player | ✅ | 🟡 | 🟡 | parity + composer |
| interactive chart scrub | ✅ | ⬜ | ⬜ | Android #19 |
| shared-element / hero transitions | ⬜ | ⬜ | ⬜ | not started |
| skeleton / shimmer loaders | ✅ | 🟡 | ⬜ | |

## C. Modifiers (contract: `Modifiers`)
Schema reconciled 2026-07-29 (added blur/rotation/pulse/zoomable/presentWhen/
presentStyle/onDoubleTap/hitSlop). Per-modifier conformance fixtures pending.
| Modifier | iOS | Android | Aurora |
|---|---|---|---|
| padding/frame/size/cornerRadius/opacity/scale | ✅ | 🟡 | 🟡 |
| background / material (×6) | ✅ | 🟡 | 🟡 |
| shadow (color/offset/radius) | ✅ | 🟡 | ⬜ |
| blur / rotation / pulse | ✅ | 🟡 | ⬜ |
| swipe / contextMenu / onTap / onLongPress / onDoubleTap | ✅ | 🟡 | 🟡 |
| zoomable / presentWhen / hitSlop / animation | ✅ | ⬜ | ⬜ |
| accessibility (label/role/value/hidden) | ✅ | 🟡 | ⬜ |

## D. Actions (contract: `Action`, 24 kinds)
iOS ✅ full interpreter. Android 🟡 (most; some Unhandled). Aurora 🟡 (full runtime
added 2026-07-29, unbuilt). **`request` / `saveFile` unimplemented on ALL** — need the
data + file layers. Per-action `expect.effects` fixtures pending.

## E. Data & networking
| Capability | iOS | Android | Aurora | Notes |
|---|---|---|---|---|
| `$data` sources + binding | 🟡 | 🟡 | ⬜ | Aurora ctx.data always {} |
| cache policy (networkOnly/cacheFirst/cacheThenNetwork) | 🟡 | 🟡 | ⬜ | field exists; behavior thin |
| **offline cache DB** (last-good, TTL, LRU, 304) | ⬜ | ⬜ | ⬜ | 🔬 [04a](04a-techniques-ledger.md) |
| **bundled fallback + resolution chain** | ⬜ | ⬜ | ⬜ | 🔬 [04](04-benchmark-and-docs.md) |
| **idempotency-key / retry+backoff / timeout / ETag** | ⬜ | ⬜ | ⬜ | 🔬 [04](04-benchmark-and-docs.md) §B2 |
| **div-patch partial updates** | ⬜ | ⬜ | ⬜ | 🔬 [04a](04a-techniques-ledger.md) |

## F. Native capabilities
| Capability | iOS | Android | Aurora | Notes |
|---|---|---|---|---|
| haptics | ✅ | 🟡 | ⬜ | Aurora ngfd stub |
| share sheet | 🟡 | 🟡 | ⬜ | Aurora needs transfer-engine |
| permissions (camera/location/notif) | ⬜ | ⬜ | ⬜ | `requestPermission` unimpl everywhere |
| push notifications | ⬜ | ⬜ | ⬜ | |
| deep links / universal links | 🟡 | 🟡 | 🟡 | openDeepLink routes; registration undocumented |
| biometrics (Face/Touch/fingerprint) | ⬜ | ⬜ | ⬜ | |
| camera / photo / media picker | ⬜ | ⬜ | ⬜ | |
| files / saveFile / document picker | ⬜ | ⬜ | ⬜ | `saveFile` unimpl everywhere |
| secure storage / keychain | ⬜ | ⬜ | ⬜ | |
| maps | ⬜ | ⬜ | ⬜ | |
| background tasks / refresh | ⬜ | ⬜ | ⬜ | |

## G. System / platform features
| Capability | iOS | Android | Aurora | Notes |
|---|---|---|---|---|
| dark mode (`colorDark`) | ✅ | 🟡 | 🟡 | |
| Dynamic Type / font scaling | 🟡 | 🟡 | ⬜ | collapsing title was hardcoded 42pt |
| Reduce Motion | 🟡 | ⬜ | ⬜ | pager honors it on iOS |
| localization / RTL | ⬜ | ⬜ | ⬜ | |
| force-update / requireVersion | 🟡 | ⬜ | ⬜ | `requireVersion` unimpl on Android/Aurora |
| Live Activity / Dynamic Island / widgets | ⬜ | — | — | iOS-specific; needs contract shape |
| app icons / launch / loaders | 🟡 | 🟡 | 🟡 | custom loaders roadmap |

---

## How to use this
- Update the cell + PARITY.md whenever a capability lands; flip to ✅ only with a
  passing [conformance fixture](09-conformance-fixtures.md) on all three.
- The **⬜/🔬 rows in E/F/G are the real remaining scope** — this is the honest size of
  "maximal universalization". Sequenced in [05-roadmap](05-roadmap.md).
- Long-term: extend `spec/tools/parity.mjs` to emit rows D–G automatically from the
  renderers + a capability registry, so this matrix stops being hand-maintained.
