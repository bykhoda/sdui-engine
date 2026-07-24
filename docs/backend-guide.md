# Running SDUI in production — a practical guide

Straight answers to the questions people actually ask when they wire this into a real product: where screens live, how you store images and icons, how versioning works, how it plays with UIKit, and whether Figma is safe to connect. No hand-waving.

## Try a whole app from JSON in 60 seconds

You don't need Swift or Kotlin to build a real screen. Everything below is language-neutral.

```
# 1. Run the mock backend (zero dependencies, just Node).
node spec/tools/serve.mjs
#    → http://localhost:8787   Swagger UI at /docs

# 2. Explore the contract in your browser — every endpoint, every field,
#    "Try it out" against the live mock:
open http://localhost:8787/docs

# 3. Point the app at it and it renders your JSON as a native screen:
#    GET /screens/feed  ·  /screens/signup_submit  ·  /screens/product_detail
```

The mock validates every screen with the same validator your CI runs, so a broken
payload 404s loudly instead of shipping. The contract itself is `spec/openapi.yaml`
(OpenAPI 3.1) — it reuses `spec/schema/sdui.schema.json`, so the API surface and the
payload shape can never drift.

**Author confidently, in any stack:**

- **Validate a payload** before you serve it (catches unknown types/actions, dangling
  `$data` refs, and — with `--tokens` — token typos):
  ```
  node spec/tools/validate.mjs --tokens spec/schema/tokens.example.json my_screen.json
  ```
- **Generate typed models** so your endpoints return the right shape:
  ```
  node spec/tools/codegen.mjs                    # → spec/types/sdui.d.ts (TypeScript)
  ```
  For Go, Python, Kotlin, Java, Rust… point `openapi-generator` or `quicktype` at
  `spec/openapi.yaml` (or the JSON Schema directly) and generate a client for your stack.
- **Copy a starting point** from `spec/examples/` — a feed, a form that POSTs, a
  data-loaded detail page, an async screen. They're all valid and runnable.

## Build screens by talking to Claude (MCP)

There's a zero-dependency MCP server at `spec/mcp/server.mjs`. Point any Claude client
at it and Claude gets the whole toolchain as native tools, so anyone — designer, PM,
backend, or a curious first-timer — can just describe a screen and get valid contract
JSON back, checked against the same schema a device renders.

The repo ships `.mcp.json`, so **Claude Code picks it up automatically** in this project.
For Claude Desktop, add to `claude_desktop_config.json` (use an absolute path):

```json
{ "mcpServers": { "sdui": { "command": "node", "args": ["/abs/path/spec/mcp/server.mjs"] } } }
```

Tools it exposes: `validate_screen` (the important one — validates before you ship),
`list_components` / `list_actions` / `list_tokens` (so Claude never invents fields),
`get_example`, and `scaffold_screen` (a valid starter for a list/form/detail). It also
serves the schema, tokens, authoring guide, and every example as MCP resources. Typical
loop: *"scaffold a signup form, add a marketing opt-in, validate it"* → paste the JSON
into the mock server → see it on device.

## Where do the screens live?

Your backend returns two kinds of JSON:

- **`tokens.json`** — the design system (colors, spacing, radii, type). One per theme, rarely changes.
- **Screen payloads** — one document per screen, keyed by a screen id (`cart`, `product`, `home`).

A minimal setup is a folder of JSON files behind a CDN. A real setup is a table:

```
screens(id, version, platform_min, locale, payload_jsonb, published_at)
```

The app asks for `GET /screens/cart?v=0.1&locale=en`, you return the row. Cache it at the edge. When a designer changes the screen, you write a new row and purge the cache — no app release. That is the whole point.

Keep the payloads small. If a screen needs data (a product, a price), don't bake it into the payload — declare a `data` source in the screen and let the app fetch it. The payload describes the *shape*; the data source fills it.

## Versioning — yes, on the backend

The contract has a `version` field (`"0.1"`). The rule: **the app refuses a payload whose major version it doesn't understand.** So version on the server, not in the binary.

How to roll it:

1. Every screen row carries the contract version it targets.
2. The app sends the contract version it supports (`v=0.1`) with each request.
3. Your endpoint returns the newest screen row that is `<=` the app's version. Old app, old screen. New app, new screen. Nobody breaks.
4. When you add a breaking component, bump the minor (`0.2`) and keep serving `0.1` payloads to older installs until they update.

This is also your safety net: if a new screen misbehaves in the wild, flip the row back to the previous version and the fleet heals on next launch. No hotfix, no review queue.

For A/B tests and feature flags, branch server-side: return payload A or B based on the user bucket. The app doesn't know or care.

## Images — keep them out of the app bundle

Don't ship images in the binary. You'll never change them without a release, and the bundle bloats.

- Store originals in object storage (S3, R2, GCS). Put a CDN in front.
- Return **URLs** in the payload. The `image` component loads any `https` URL, caches it on device, and shows a placeholder while it loads.
- Serve sized variants (`@2x`, `@3x`, WebP) and pick per device with a query param your backend understands.
- Swapping a hero image is a storage write, not a deploy.

## Icons

Two honest cases:

- **System icons** — the `icon` component uses the SF Symbol name space on iOS. On Android a host-side resolver maps the same name to a drawable; until it's wired, the name shows as text. Symbol names are free to use inside Apple platforms.
- **Your brand icons** — treat them like images: upload to storage, reference by URL through the `image` component, or register them in the host's icon resolver so one contract name works on both platforms. Don't hardcode them in the app.

## Custom components — the escape hatch to real Swift/Kotlin

You do **not** express everything in JSON. When you need something the built-ins can't do — a map, a camera view, your own charting library, a signature pad — you write it natively once and register it:

```swift
registry.register("custom.map") { component, ctx in
    AnyView(MyMapView(lat: component.prop("lat")?.doubleValue ?? 0))
}
```

Then the server sends `{ "type": "custom.map", "lat": 40.7 }` and it renders your real Swift view, driven by JSON like any built-in. Same idea on Compose. This is how you map your existing component library — the one your Figma is built on — to SDUI: each Figma component becomes one `custom.<name>` you already ship.

## Playing with UIKit

The renderer is SwiftUI, but it drops into a UIKit app cleanly:

- Wrap a screen in `UIHostingController(rootView: SDUIScreenView(...))` and push it like any view controller.
- Going the other way — a UIKit view inside an SDUI screen — is a `custom.*` component whose builder returns a `UIViewRepresentable`.
- Navigation (`navigate`, `dismiss`) is handed to your host delegate, so you route with your existing `UINavigationController` / coordinator. The engine never owns your nav stack.

## Threading — you won't fight it

This was a design goal, so it's worth being clear: the contract never mentions GCD, `NSOperation`, or threads. Concurrency lives in the runtime:

- Data loading runs off the main actor (`async`/`await` + a `TaskGroup` for parallel sources).
- Rendering and actions are `@MainActor` — UI state is only ever touched on the main thread, so there are no data races to debug.
- JSON parsing for a pushed screen happens off-main; the screen shows a skeleton until it's ready.

You describe *what* happens; the runtime decides *where* it runs.

## Figma — how, and is it safe

The flow: export your Figma **Variables** (W3C Design Tokens JSON, or the Tokens Studio plugin) and run `spec/tools/figma-tokens.mjs` to produce `tokens.json`. Wire that into CI so every merge regenerates it. A designer changing a color in Figma re-themes the whole product on the next launch.

On safety: the conversion is a **local, offline, read-only** script. It reads a file you exported and writes `tokens.json`. It does not talk to Figma's API, needs no token, and sends nothing anywhere. If you'd rather pull live from the Figma API, that runs on your CI with your own scoped token — nothing about it ships in the app.

## A sane way to start

1. Serve one screen (`tokens.json` + one screen payload) from a static file. Render it with `SDUIScreenView`.
2. Move it behind an endpoint with the version rule above.
3. Add a data source so the screen pulls live content.
4. Register your first `custom.*` component for something the built-ins don't cover.
5. Point tokens at your Figma export.

At that point you're shipping UI from the server, versioned, themed from design, with your own native components mixed in — which is the whole idea.
