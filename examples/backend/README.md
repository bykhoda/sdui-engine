# Your own SDUI backend — a clean reference

The whole app is JSON. This is the minimal, copy-me example of the backend a client
runs: it hands out **design tokens** and **screens**, and it **validates every screen
against the contract before serving it**, so the native app can never receive a payload
it can't render.

Zero dependencies. Node 18+.

```bash
node examples/backend/server.mjs        # → http://localhost:4000
# PORT=4055 node examples/backend/server.mjs   # pick a port
```

## The contract between client and backend

It's deliberately small and sequential — three request shapes, nothing else:

| Step | Request | Response |
|---|---|---|
| 1. Boot | `GET /tokens` | the shared design tokens the client resolves `$token.*` against |
| 2. Open a screen | `GET /screens/:id` | one **validated** SDUI document — the app renders it natively |
| 3. Navigate | a `navigate` action in the JSON fires `GET /screens/<to>` | the next screen |

Discovery/health: `GET /catalog` (the ids this backend serves) · `GET /health`.

```bash
curl localhost:4000/tokens
curl localhost:4000/screens/home
curl localhost:4000/screens/nope     # → 404, but still a *renderable* error screen
```

`GET /screens/home` returns exactly:

```jsonc
{ "version": "1.0",
  "screen": { "id": "home", "title": "Home",
    "content": { "type": "vstack", "spacing": "$token.spacing.md",
      "children": [
        { "type": "text", "value": "Welcome", "style": "$token.typography.largeTitle" },
        { "type": "button", "title": "Open detail",
          "onTap": { "action": "navigate", "to": "detail" } }
      ] } } }
```

The user taps **Open detail** → the client interprets the `navigate` action → `GET /screens/detail`.
Change any of this JSON on the server and it updates on every device — no app release.

## Two guarantees this reference gives you

1. **Validation before serving.** At boot the server runs every screen through the *same*
   `Validator` the contract's CI and clients use ([`spec/tools/validate.mjs`](../../spec/tools/validate.mjs)).
   An invalid screen is logged and **not served** — a bad edit fails loudly on your server
   instead of on a phone:
   ```
   ✓ home.json   → GET /screens/home
   ✗ broken.json is INVALID — NOT served:
       screen.content.children[0].value: required
   ```
2. **Always renderable.** A missing/failed screen returns a small SDUI **error screen**, never a
   raw 500 — the last link of the resolution chain (network → cache → bundled fallback → stub,
   see [`docs/blueprint/11-offline-cache-spec.md`](../../docs/blueprint/11-offline-cache-spec.md)).

## Add a screen

Drop a `screens/<id>.json` file. If it validates, it's live at `GET /screens/<id>` on the next
start — no code change. Author it by hand, with the [MCP server](../../spec/mcp) (`scaffold_screen`
/ `validate_screen`), or in the visual composer (`/compose`).

## Point a native client at it

The iOS/Android renderers take a screen document + tokens and render it. Fetch `GET /tokens`
once, then `GET /screens/<id>` per screen, and hand each response to `SDUIScreenView` (iOS) /
`SduiScreen` (Android); wire the host's `navigate` to fetch the next id. That's the whole
integration — see [`ios/README.md`](../../ios/README.md) / [`android/README.md`](../../android/README.md).

## Where to grow it (production)

This reference is intentionally tiny. A production backend adds, along the same shape:
per-source **caching + `ETag`/304** and **idempotency-key**ed writes
([networking spec](../../docs/blueprint/12-networking-spec.md)), a **`request`** endpoint for
mutations, **`$data`** sources resolved server-side or by the client, and **partial `div-patch`**
updates ([spec](../../docs/blueprint/13-div-patch-spec.md)). The MCP `generate_backend` tool
([plan](../../docs/blueprint/17-mcp-ai-authoring.md)) scaffolds these for you.
