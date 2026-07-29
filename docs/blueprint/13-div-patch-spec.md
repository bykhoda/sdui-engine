# 13 — Partial updates ("div-patch"): id-addressed screen mutation

The single biggest **perceived-perf** lever after caching ([04a](04a-techniques-ledger.md)):
update part of a live screen without refetching/re-rendering the whole thing. Modeled on
DivKit's `div-patch`, adapted to our contract.

> Serves "ideal client assembly": a like count, a row, a section updates instantly and
> in place — no full-screen flash, no scroll-position loss.

---

## 1. Why id-addressed (not JSON-Pointer)

Patches target nodes by **stable `id`**, not by tree path. Paths are brittle (any sibling
insert invalidates them); ids survive reordering. This is why every node needs a stable
id — the composer already mints/repairs unique `__id`s ([ensureIds](../../spec/compose/index.html)),
and authored screens should carry explicit `id`s on any node a server may patch. Nodes
without an id are simply not patch-targetable (fine — most aren't).

## 2. Patch shape (contract)

```jsonc
{
  "patch": {
    "mode": "transactional",              // "transactional" (all-or-nothing) | "partial" (apply what matches)
    "changes": [
      { "id": "cart-count", "items": [ /* 1 node */ ] },   // REPLACE the node
      { "id": "feed-row-42", "items": [] },                  // REMOVE the node
      { "id": "section-a", "items": [ n1, n2, n3 ] },        // REPLACE with several (splice into parent)
      { "id": "list", "op": "append", "items": [ newRow ] }  // optional ops: append/prepend/insertBefore/insertAfter
    ],
    "templates": { /* optional: templates the patched nodes reference */ },
    "state": { /* optional: state deltas applied atomically with the tree change */ }
  }
}
```

Semantics (match DivKit + our extensions):
- `items` **empty** = remove the target; **one** = replace; **many** = replace-with-several
  (spliced into the target's parent at the target's position).
- `op` (extension) allows list-friendly `append`/`prepend`/`insertBefore`/`insertAfter`
  without resending siblings — the common "load more" / "new message" case.
- `mode:"transactional"` = if ANY change's `id` is missing, apply nothing (and report);
  `"partial"` = apply matches, skip misses. Default transactional.
- `templates`/`state` applied **atomically** with the tree change (one render pass).

## 3. Delivery

- As a `request`/`refresh` **response body** (server returns a patch instead of a full
  screen), and/or
- via a **push channel** (WebSocket/SSE) for live screens (prices, chat) — the transport
  is out of contract scope; the patch payload is in scope.

Renderers diff-apply the patch to the retained node tree and re-render only affected
subtrees (SwiftUI/Compose already do minimal re-render given stable ids → cheap).

## 4. Interaction with the rest

- **Stable ids** are the prerequisite (this doc + ensureIds + authoring guidance).
- **Cache** (11): a patch updates the cached last-good entry too, so a re-open shows the
  patched state.
- **Conformance** (09): patch application is a Level-A fixture — `screen.json` + a
  `patch` + `expect.tree` — run on the JS reference and all three renderers; identical
  resulting tree required. Empty/one/many/append/missing-id/transactional-rollback all
  covered.
- **Animation**: an optional `animate` flag on a change → the replace cross-fades /
  the insert slides in (reuses the `animation` modifier semantics).

## 5. Build sequence
1. Schema: `Patch` def + `changes[]` + ops + modes; a `patch` response type on `request`.
   Regen types.
2. JS reference `applyPatch(tree, patch)` (pure) + conformance fixtures (empty/one/many/
   ops/transactional). CI, no devices.
3. iOS apply-patch over the retained tree behind an id→node index; then Android, Aurora —
   each passing the same fixtures.
4. Authoring: composer surfaces node `id` on patch-eligible nodes + a "copy as patch
   target" affordance; docs on when to add ids.

## 6. Ordering vs other work
Lands **after** conformance harness exists (so it's provably identical from day one) and
**with/after** stable-id authoring guidance. High value, but gated on the id discipline
being real across authored screens — otherwise patches miss.
