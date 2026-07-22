# Authoring screens

How to write a valid screen payload. Everything here is enforced by
[`spec/schema/sdui.schema.json`](../schema/sdui.schema.json) — write the JSON,
validate it, fix what the validator flags, ship it.

## The shape of a screen

```json
{
  "version": "0.1",
  "screen": {
    "id": "unique_snake_case_id",
    "title": "Optional nav title (may be a binding)",
    "data":    { "sources": [ /* requests, see §Data */ ] },
    "state":   { "someFlag": false },
    "refresh": { "sources": ["sourceId"] },
    "onAppear": { /* an action */ },
    "content": { /* ONE root component */ }
  }
}
```

Rules:
- `version` is required and currently `"0.1"`.
- `screen.id` is required, lowercase, `^[a-z][a-z0-9_.]*$`.
- `screen.content` is exactly one component (usually a `scroll` or `vstack`).

## Bindings — the `$` language

Any string may be a literal, a whole binding, or an interpolation.

| Namespace | Resolves to | Example |
|-----------|-------------|---------|
| `$data.<sourceId>.<path>` | a loaded network response | `$data.product.title` |
| `$token.<group>.<name>` | a shared design token | `$token.spacing.md` |
| `$env.<key>` | runtime env (locale, theme, platform) | `$env.locale` |
| `$state.<key>` | client-local screen state | `$state.page` |
| `$params.<key>` | navigation parameters passed to this screen | `$params.productId` |
| `$item.<path>` | current element inside a `list` template | `$item.id` |

Navigation `params` also fill `{key}` placeholders in request paths, e.g.
`"/products/{productId}"` is filled from `$params.productId`.

- **Whole binding** keeps the value's real type: `"value": "$data.product.price"`
  yields a number, not the string `"$data.product.price"`.
- **Interpolation** splices into text: `"Hello, $data.user.name"`.
- A missing binding resolves to empty/null — never an error, never a crash.

## Components (`type`)

Every component may carry `id`, `modifiers` (see §Modifiers) and `visibleWhen`
(a condition). Type-specific fields:

| type | key fields | notes |
|------|-----------|-------|
| `vstack` / `hstack` | `children[]`, `spacing`, `alignment` | vertical / horizontal stack |
| `zstack` | `children[]`, `alignment` | overlay |
| `scroll` | `child`, `axis`, `onReachEnd` | scroll container; `onReachEnd` drives pagination |
| `list` | `items` (binding to array) + `template`, or static `children[]`, `spacing`, `onReachEnd`, `reorder` | lazy, virtualised; `onReachEnd` paginates; `reorder: true` (with `items` bound to `$state.<key>`) enables drag-to-reorder, saved back to state |
| `grid` | `columns`, `items` + `template` or `children[]`, `spacing` | lazy grid |
| `text` | `value`, `style`, `color`, `lineLimit`, `alignment` | `style` is a typography token |
| `icon` | `name`, `color` | SF Symbol / shared icon name |
| `image` | `source`, `loader{placeholder,aspectRatio,contentMode}` | remote URL or `asset:name` |
| `button` | `title`, `style`, `icon`, `onTap`, `enabledWhen` | `style` is a button token |
| `textfield` | `bind` (state key), `placeholder` | two-way bound to `$state` |
| `toggle` | `bind` (state key), `title` | two-way bound to `$state` |
| `picker` | `bind` (state key), `title`, `options[{label,value}]` | two-way bound to `$state` |
| `progress` | `value` (0…1) | determinate progress bar |
| `chart` | `style` (`line`/`area`/`bar`), `color`, `values[]` or `points[{x,y}]` | native chart (Swift Charts on iOS, Canvas on Android) |
| `gradient` | `colors[]`, `direction` (`vertical`/`horizontal`/`diagonal`) | linear-gradient fill, e.g. an immersive `zstack` background |
| `rings` | `values[]` (0…1 each), `colors[]`, `lineWidth`, `gap` | concentric activity rings (Apple Fitness idiom) |
| `spinner` | `color`, `scale` | native circular activity indicator |
| `slider` | `bind` (state key, 0…1), `color`, `height`, `thumb` | draggable continuous control, two-way bound to `$state` |
| `async` | `source` (a data source), `loading`, `content`, `error` slots | fetch-then-render: spinner while loading, then `content` bound to `$data.<source.id>` |
| `spacer` | `minLength` | flexible gap |
| `divider` | `color` | hairline |
| `custom.*` | anything | rendered by a host-registered native view |

Use `custom.<name>` for anything the primitives can't express (maps, camera,
video). Put its props at the top level of the node; the host reads them.

**Platform parity:** the built-in vocabulary above renders natively on both iOS
(SwiftUI) and Android (Compose). `chart`, `gradient`, `rings` and `icon` draw via
Swift Charts / Canvas respectively — one payload, both platforms. Icons use the SF
Symbol name space; an Android host supplies an icon resolver to map names to
drawables (names surface as text until it does).

## Modifiers

Applied to any component under `modifiers`:

- `padding` — a number/token, or `{top,leading,bottom,trailing,horizontal,vertical}`
- `background`, `cornerRadius`, `opacity`
- `size` — explicit per-axis sizing `{width,height}`, each `{mode,value,min,max}`
  where `mode` is `fixed`/`hug`/`fill`/`weight`. **Prefer this over `frame`** — it
  lays out identically on iOS and Android.
- `frame` — `{width,height,maxWidth}` (interim; `maxWidth: "infinity"` to fill)
- `shadow` — `{color,radius,x,y}`
- `onTap`, `onLongPress` — an action
- `contextMenu` — `[{title,icon,role,action}]` (shown on long-press)
- `swipe` — `{leading:[…], trailing:[…]}` swipe-to-reveal actions, each
  `{title,icon,role,tint,action}` (leading = swipe right, trailing = swipe left)
- `animation` — `{curve,duration}` (plays on `$state` changes)
- `accessibility` — `{label,value,hint,role,hidden}` (`role`: button/image/header/link/none)

## Actions

Actions are declarative and composable. Every action is
`{ "action": "<kind>", ... }` and may carry an `analytics` tag that fires when
it runs.

| kind | fields | effect |
|------|--------|--------|
| `navigate` | `to`, `params`, `transition` (`push`/`sheet`/`fullScreenCover`/`replace`) | go to a screen |
| `dismiss` / `dismissRoot` | — | close current / whole stack |
| `openURL` / `openDeepLink` | `url` | open a link |
| `setState` | `key`, `value` | mutate client state |
| `refresh` | `sources[]` | reload data sources |
| `request` | `source`, `onSuccess`, `onError` | one-off request |
| `sequence` | `actions[]` | run in order |
| `parallel` | `actions[]` | run together |
| `condition` | `if`, `then`, `else` | branch on a condition |
| `showToast` | `message`, `style` | transient message |
| `scrollTo` | `target` (component `id`) | smooth-scrolls the screen to that component — e.g. jump to the first invalid field |
| `haptic` | `style` (`light`/`medium`/`heavy`/`success`/`warning`/`error`) | feedback |
| `share` | `text`, `url` | system share sheet |
| `custom` | `name`, `payload` | host-defined action |

Compose them: a buy button that vibrates, then opens checkout —

```json
{ "action": "sequence", "actions": [
  { "action": "haptic", "style": "success" },
  { "action": "navigate", "to": "checkout", "params": { "productId": "$data.product.id" }, "transition": "sheet" }
]}
```

## Conditions

Used by `visibleWhen`, `enabledWhen`, and the `condition` action. Exactly one
operator per object:

```json
{ "and": [
  { "exists": "$data.user.name" },
  { "not": { "equals": ["$env.locale", "en"] } }
]}
```

Operators: `equals`/`notEquals` (`[a, b]`), `exists` (ref), `not`, `and`, `or`.

## Data / networking

Requests are declared, not coded. The host maps `service` → base URL + auth, so
payloads never hardcode hosts.

```json
"data": {
  "mode": "parallel",
  "sources": [
    { "id": "product", "service": "catalog", "path": "/products/{productId}",
      "method": "GET", "query": { "lang": "$env.locale" },
      "policy": "cacheThenNetwork" }
  ]
}
```

- `mode`: `parallel` (default, concurrent) or `sequential`.
- `dependsOn: ["otherId"]` forces ordering; the earlier result is bindable as
  `$data.otherId.*` in the later request.
- `policy`: `networkOnly` / `cacheFirst` / `cacheThenNetwork`.
- Reference a response anywhere as `$data.<id>.<path>`.

## Worked examples

See [`product_detail.json`](../examples/product_detail.json) and
[`feed.json`](../examples/feed.json). Both validate against the schema and render
on the reference iOS runtime.

## Checklist

1. `version` present, `screen.id` matches `^[a-z][a-z0-9_.]*$`.
2. Exactly one `screen.content`.
3. Every `$data.*` you reference has a matching `data.sources[].id`.
4. Every `$token.*` exists in the token file.
5. Every action `kind` is valid; required fields present.
6. Run the validator: `node spec/tools/validate.mjs your-screen.json`.
