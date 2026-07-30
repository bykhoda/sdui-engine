# 16 — World-Class App Capability Roadmap

**Status:** Product-architecture synthesis, 2026-07-30. Branch `sdui-parity-and-fixes`.
**Thesis owner:** the north-star — *one shared JSON contract lets any persona build a
production app*. This doc is the demand-side companion to the supply-side plan in
[15-android-parity-and-features.md](15-android-parity-and-features.md): 15 says "make the
30 components we have identical on 3 platforms"; **16 says "here is the component/action/
motion vocabulary a client must be able to write so that JSON alone builds a
Dodo-Pizza / YouTube / Revolut-class app."**

Source: six parallel domain teardowns — food-delivery/QSR, big-tech media & social,
Apple's own apps, banking/fintech, scanners/productivity/telecom/super-apps, and a
motion/animation systems study — plus a curated high-star OSS sourcing list. Every
capability below carries its citation (repo + stars + URL) so an implementer can go
straight to the reference.

Baseline contract today (`spec/schema/sdui.schema.json`): **30 components · 24 actions ·
~24 modifiers.** Simple `$state.<key>` binding only; no expression language, no typed
variables, no templates, no partial-update, no declarative motion beyond a
`{curve,duration}` stub. That baseline is a strong *display + local-state* engine and a
weak *device-capability, live-data, and motion* engine — which is exactly the shape of
the gaps below.

---

## 1. Executive thesis

Three findings recur across all six domains, and they define the work:

1. **The contract can render a screen but cannot run an app.** The single most-cited gap
   is not a missing widget — it is that `request` is a **no-op on every platform**
   (15 §F1), the list pipeline (pagination/append/empty/onReachEnd) exists only on iOS
   (15 §F2), and there is no cursor pagination, no `$data` iteration/templates, no
   expression language, and no number/currency formatting in bindings. Until these land,
   a backend team can describe a menu but cannot build a cart, a feed, a balance, or a
   checkout. **This is P0 and it blocks every domain simultaneously.**

2. **A dozen high-leverage components are missing, and they cluster.** `video` unlocks
   YouTube/TikTok/Reels/X at once. `optionGroup + stepper + counter` unlock the entire
   QSR customizer-cart-balance revenue path with *zero* native-SDK dependency — pure
   contract + layout, so they land at parity fastest. `sheet` detents, `list` sections,
   `scanner`, and `map` unlock product-detail, grouped feeds, doc-scan/super-apps, and
   delivery-tracking respectively. Each maps cleanly to a native mechanism
   (AVPlayer/Media3, VisionKit/ML Kit, MapKit/MapLibre, StoreKit/Play Billing), preserving
   the "one JSON, identical native screens" promise.

3. **Motion is a stub, and motion is the product.** Every domain's "signature" reduces to
   the same short list: **shared-element/hero transitions** (⬜ everywhere in the matrix,
   named by media, Apple, food, banking, and motion teams as the biggest single gap), a
   **real spring spec** (our `spring` is a magic word with no damping/stiffness),
   **declarative entrance/exit + stagger**, **Lottie/Rive**, and a **global Reduce-Motion
   contract**. DivKit already expresses all of this in JSON; it is our direct benchmark and
   we are far behind it here.

The roadmap in §6 sequences these as **P0 unblock → P1 signature polish → P2 advanced**,
threading through the concrete iOS/Android fixes already located in doc 15.

---

## 2. New components to add

Deduplicated across domains; where several teardowns proposed the same primitive it is
listed once with the strongest citation. "Priority" = the tier it lands in per §6.

| Component | What it enables | Apps that ship it | Proposed JSON shape | Source repo + stars | Prio |
|---|---|---|---|---|---|
| **`optionGroup`** | Modifier/combo customizer: single/multi select, min/max, per-option price deltas → live total. The single highest-leverage QSR addition (pure contract, no native SDK). | Starbucks, Dodo, Domino's, McDonald's | `{ "type":"optionGroup","selection":"single","min":1,"max":1,"bind":"$state.mods.size","style":"cards","options":[{"value":"venti","label":"Venti","priceDelta":0.80,"image":"$data.p.venti.img"}] }` | [woltapp/wolt_modal_sheet 641★](https://github.com/woltapp/wolt_modal_sheet) (customizer sheet pattern) | **P0** |
| **`stepper`** | Quantity −N+ bound to state, min/max/step, spring bounce + haptic per tap. On card, in sheet, in cart. | Every QSR/grocery app | `{ "type":"stepper","bind":"$state.qty","min":1,"max":20,"step":1,"style":"pill","haptic":"light","onChange":{"action":"custom","name":"recalcTotal"} }` | native (SwiftUI `Stepper`/Compose) | **P0** |
| **`counter`** | Animated odometer number — currency-formatted balance/total that rolls digit-by-digit on change; sign-colored. The defining fintech micro-interaction. | Revolut, Cash App, Monzo, Robinhood | `{ "type":"counter","value":"$data.account.balance","format":{"style":"currency","currency":"GBP"},"roll":"digit","duration":0.6,"signColor":true }` | [UXDA Dopamine Banking](https://www.theuxda.com/blog/rise-dopamine-banking-how-fintechs-and-neobanks-are-redefining-customer-experience) · [60fps.design/Revolut](https://60fps.design/apps/revolut) | **P0** |
| **`sheet` / `bottomSheet`** | Detented, drag-resizable, optionally multi-page modal with a pinned live-priced footer. The product-detail surface everything else lives in. | Wolt, Music, Health, Maps, comment sheets | `{ "type":"bottomSheet","presentWhen":"$state.showProduct","detents":["medium","large"],"selectedDetent":"$state.d","grabber":true,"pages":[…],"pinnedFooter":{ "type":"button","title":"Add for $data.fmt.total","onTap":{"action":"custom","name":"addToCart"} } }` | [woltapp/wolt_modal_sheet 641★](https://github.com/woltapp/wolt_modal_sheet) · [exyte/PopupView ~1.8–4.1k★](https://github.com/exyte/PopupView) | **P0** |
| **`richtext`** | Span-styled inline text: @mentions / #hashtags / $cashtags / links as tappable colored runs, spoiler/blur ranges, "…more" truncation+expand. Required for any tweet/comment/caption. | X, YouTube, Instagram comments | `{ "type":"richtext","spans":[{"text":"@sdui","role":"mention","onTap":{…}},{"text":"#release","role":"hashtag"},{"text":"spoiler","role":"spoiler"}],"lineLimit":3,"expandable":true }` | DivKit text `ranges` · [microsoft/AdaptiveCards ~2.0k★](https://github.com/microsoft/AdaptiveCards) `RichTextBlock` | **P0** |
| **`video`** | Real player: autoplay-on-visible, mute-by-default, loop, poster, buffered scrubber, chapters, tap-pause, double-tap-seek, PiP, fullscreen/rotate. Unlocks YouTube/TikTok/Reels/X at once; upgrades `clips` pages to carry a real video child. | YouTube, TikTok, Reels, X, FB Watch | `{ "type":"video","source":"$item.url","poster":"$item.thumb","autoplay":"onVisible","visibilityThreshold":0.5,"muted":true,"loop":true,"aspectRatio":0.5625,"controls":"scrubber","gesture":{"tapToPause":true,"doubleTapSeek":10},"pictureInPicture":true,"bindProgress":"$state.playhead" }` | [androidx/media (Media3/ExoPlayer) ~2.9k★](https://github.com/androidx/media) · [react-native-video 7.7k★](https://github.com/TheWidlarzGroup/react-native-video) (prop surface) | **P1** |
| **`story` / `stories`** | Segmented tap-through player: per-segment progress fill, tap-right/left = next/prev, hold-to-pause, timed auto-advance, ring entry. Distinct from vertical `clips`. | Instagram, Tinkoff (first bank), Glovo, Wolt | `{ "type":"stories","authors":[{"avatar":"…","segments":[{"media":"…","kind":"image","durationMs":5000}]}],"tapZones":true,"holdToPause":true,"onComplete":{"action":"dismiss"} }` | [react-insta-stories](https://www.npmjs.com/package/react-insta-stories) · [D-32/SegmentedProgressBar](https://github.com/D-32/SegmentedProgressBar) · [The-Igor/d3-stories-instagram](https://github.com/The-Igor/d3-stories-instagram) | **P1** |
| **`storyRing`** | Tappable story-ring row that launches the full-screen story reader; seen/unseen state. | Instagram, Glovo, Wolt, Drinkit | `{ "type":"storyRing","items":"$data.home.stories","imageField":"cover","seenBind":"$state.seen","onOpen":{"action":"navigate","to":"story_viewer","transition":"fullScreenCover"} }` | reuses `clips`/`stories` reader | **P1** |
| **`avatar`** | The badge cluster as one node: story/live ring, verified/live/online badge, tap-to-profile. Ends hand-building from zstack+image+text. | Instagram, X, YouTube, all social | `{ "type":"avatar","source":"$item.pfp","size":44,"ring":"story","badge":"verified","onTap":{"action":"navigate","to":"profile"} }` | native (composition) | **P1** |
| **`lottie`** | After-Effects JSON vector animation rendered natively: like-bursts, loaders, success checks, empty states, per-step tracker icons, onboarding. One JSON → identical on both platforms. | Uber Eats (whisk/bag states), all | `{ "type":"lottie","source":"asset:success","loop":false,"progress":"$state.uploadPct","onFinish":{…},"reduceMotion":"staticFrame" }` | [airbnb/lottie-ios 26.8k★](https://github.com/airbnb/lottie-ios) · [lottie-android 35.7k★](https://github.com/airbnb/lottie-android) | **P1** |
| **`map`** | Live tracking + address pin: markers, animated courier movement, route polyline, draggable pin with reverse-geocode. The one post-purchase surface needing a native map SDK. | Uber Eats, DoorDash, Wolt, Dodo | `{ "type":"map","region":{"center":"$data.order.courier","fit":"route"},"markers":[{"id":"courier","coordinate":"$data.order.courier","animateMovement":true}],"route":{"coordinates":"$data.order.routePolyline"},"pin":{"mode":"draggable","bind":"$state.dropoff","reverseGeocodeTo":"$state.addr"} }` | [maplibre-native 2.1k★](https://github.com/maplibre/maplibre-native) · [mapbox-gl-native 4.5k★](https://github.com/mapbox/mapbox-gl-native) · MapKit (iOS) | **P1** |
| **`orderTracker`** | Horizontal stepped delivery tracker with a live current-step binding, per-step icon/Lottie, animated advance, ETA. | Uber Eats, DoorDash, Dodo | `{ "type":"orderTracker","orientation":"horizontal","currentStep":"$data.order.stepIndex","animateAdvance":true,"steps":[{"key":"preparing","lottie":"asset:whisk"},{"key":"enroute","icon":"bicycle"}],"eta":"$data.order.etaText" }` | [Uber Eats tracker redesign](https://www.marketingdive.com/news/uber-eats-boosts-delivery-tracker-transparency-with-colorful-animations/552543/) | **P1** |
| **`stickyNav`** | Two-way scroll-spy category rail: tap a chip → scroll snaps to section; scrolling highlights the active chip. | Glovo, Wolt, all menus | `{ "type":"stickyNav","bind":"$state.activeSection","sections":"$data.menu.categories","labelField":"name","anchorField":"id","scrollSpy":true }` | [Glovo UX teardown](https://medium.com/design-bootcamp/an-x-ray-of-the-glovo-app-to-understand-its-user-experience-61e4c44aed6c) | **P1** |
| **`tabs`** | Swipeable top tabs: segmented bar bound to a horizontally-swipeable pager, underline indicator tracks the drag. DivKit `div-tabs` is one of its most-used blocks. | X (For you/Following), YouTube, IG profile | `{ "type":"tabs","bind":"$state.tab","tabs":[{"label":"For you"},{"label":"Following"}],"indicator":"underline","pages":[…] }` | [divkit/divkit 2.7k★](https://github.com/divkit/divkit) `div-tabs` | **P1** |
| **`seekbar` + `marquee`** | Audio/video scrubber distinct from `slider` (buffered progress, chapters, elapsed/remaining); marquee auto-scrolls overflowing track titles. | Spotify, YouTube Music, Music | `{ "type":"seekbar","bind":"$state.playhead","buffered":"$state.buf","chapters":[0,0.3,0.72],"elapsedLabel":true }` · `{ "type":"marquee","value":"$data.track.title","speed":40 }` | native · [Spotify Now-Playing](https://codemyui.com/spotify-like-dynamic-gradient-background-based-on-image-colours/) | **P1** |
| **`reaction`** | Animated like: bind + count, double-tap heart burst, long-press reaction tray (6 emoji spring), odometer count roll. | Instagram, TikTok, Facebook, X | `{ "type":"reaction","bind":"$state.liked","count":"$item.likes","icon":"heart","burst":"heart","reactions":["like","love","haha"],"onChange":{…} }` | [ConfettiSwiftUI 2.4k★](https://github.com/simibac/ConfettiSwiftUI) · [Konfetti 3.4k★](https://github.com/DanielMartinus/Konfetti) | **P1** |
| **`scanner`** | Flagship device-capability node: `mode` = document/qr/barcode/photo; live edge-detection + auto-capture, multi-page tray, filter strip, viewfinder overlay, result binding. Unlocks the entire doc-scanner + super-app-scan surface. | iScanner, CamScanner, Adobe Scan, WeChat, Gojek | `{ "type":"scanner","mode":"document","autoCapture":true,"multiPage":true,"filters":["auto","magic","bw"],"overlay":{"shape":"quad","torchToggle":true},"resultBind":"$state.scan","onComplete":{"action":"navigate","to":"scan_review"} }` | [react-native-vision-camera 9.5k★](https://github.com/mrousavy/react-native-vision-camera) · [zxing/zxing 34k★](https://github.com/zxing/zxing) · VisionKit / ML Kit | **P1** |
| **`cropper` / `pdfview` / `signature`** | Complete the scanner pipeline: draggable-corner perspective crop; PDF page viewer w/ thumbnail strip; ink signature pad. | Adobe Scan, DocuSign, banking | `{ "type":"cropper","source":"$state.scan.pages.0","handles":"quad","resultBind":"$state.scan.pages.0" }` · `{ "type":"pdfview","source":"$data.doc.url","pageIndicator":true,"thumbnailStrip":true }` · `{ "type":"signature","guideline":true,"resultBind":"$state.sig" }` | [Yalantis/uCrop](https://github.com/Yalantis/uCrop) · PDFKit / [AndroidPdfViewer](https://github.com/barteksc/AndroidPdfViewer) | **P1** |
| **`wizard`** | Validated multi-step container: owns the stepper, gates `next` on per-step `validWhen`, aggregate form validity. Unlocks onboarding/checkout/account-setup across every app type. | Todoist, carrier setup, all onboarding | `{ "type":"wizard","indicator":"steps","current":"$state.step","steps":[{"title":"Account","content":{…},"validWhen":{"exists":"$state.email"}}],"next":{"title":"Continue"},"onFinish":{"action":"request","source":{…}} }` | [UX Patterns wizard](https://uxpatterns.dev/patterns/advanced/wizard) | **P1** |
| **`planselect`** | Paywall plan-selector cards: price/sub/badge/savings, highlighted best-value, trial toggle. The revenue screen. | every subscription app | `{ "type":"planselect","bind":"$state.plan","options":[{"id":"annual","title":"Yearly","price":"$39.99/yr","badge":"BEST VALUE","savings":"Save 58%","highlighted":true}],"trial":{"bind":"$state.trialOn","label":"7-day free trial"} }` | [RevenueCat paywall guide](https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps) | **P1** |
| **`donut`** | Spend-by-category ring with legend + center total + segment tap. | Revolut, Monzo analytics | `{ "type":"donut","segments":[{"label":"Groceries","value":320.5,"color":"$token.color.cat.food"}],"center":{"primary":"£1,204","secondary":"spent"},"legend":"right","format":{"style":"currency","currency":"GBP"} }` | [Mobbin Revolut analytics](https://mobbin.com/explore/screens/8abfbc04-b406-4c63-bc6b-161cf537d6e9) | **P1** |
| **`summary`** | Receipt / fee-breakdown key-value rows with muted line items, emphasized total, divider-before-total. | Wise, all checkout | `{ "type":"summary","rows":[{"label":"You send","value":"1,000.00 USD"},{"label":"Our fee","value":"4.28 USD","muted":true},{"label":"Total","value":"1,005.37 USD","emphasis":true,"dividerBefore":true}] }` | [Wise pricing](https://wise.com/us/pricing/) | **P1** |
| **`card`** | Bank card with 3D flip-to-reveal (PAN/CVV) behind a biometric gate; frozen frost overlay. | Monzo, Revolut, N26 | `{ "type":"card","front":{…},"back":{…},"flipped":"$state.revealed","flipAxis":"y","revealGate":{"action":"biometricAuth","reason":"Reveal card details"},"aspectRatio":1.586,"frozen":"$state.frozen" }` | [Eleken fintech guide](https://www.eleken.co/blog-posts/modern-fintech-design-guide) | **P1** |
| **`gauge`** | Telecom usage meter: radial or stacked-bar, segments, threshold color, arc-sweep + count-up on appear. | Verizon, T-Mobile, МТС | `{ "type":"gauge","style":"radial","value":"$data.usage.fraction","label":"34.2 GB of 50 GB","segments":[{"value":0.4,"label":"Video"}],"threshold":{"at":0.9,"color":"$token.color.danger"},"animateOnAppear":true }` | [Verizon usage dashboard](https://community.verizon.com/discussion/1824545/introducing-your-new-data-usage-dashboard) | **P1** |
| **`servicegrid`** | Super-app mini-app launcher: labeled icon tiles, badge, deep-link, editable favorites, "more" expander. | WeChat, Gojek, Grab | `{ "type":"servicegrid","columns":4,"editable":true,"items":"$data.services","template":{"icon":"$item.icon","label":"$item.label","onTap":{"action":"openDeepLink","url":"$item.deepLink"}},"more":{"label":"All services"} }` | [Gojek design](https://gojek.design/) · [Ramotion super-app](https://www.ramotion.com/blog/what-is-super-app/) | **P1** |
| **`pinpad` + `otp`** | Secure numeric keypad (filled dots, shuffle option, shake-on-error, biometric fallback) and segmented one-time-code field with SMS autofill + auto-submit. | all banking, all 2FA | `{ "type":"pinpad","bind":"$state.pin","length":6,"mask":true,"biometricFallback":true,"onComplete":{…} }` · `{ "type":"otp","bind":"$state.code","length":6,"textContentType":"oneTimeCode","autoSubmit":{…} }` | [procreator fintech UX](https://procreator.design/blog/best-fintech-ux-practices-for-mobile-apps/) | **P1** |
| **`rive`** | Interactive state-machine vector animation with typed inputs bound to `$state`/`$data` — server state drives the animation with no custom code. | Duolingo-class delight, interactive toggles | `{ "type":"rive","source":"…/toggle.riv","stateMachine":"SM1","inputs":{"isOn":"$state.enabled","level":"$data.progress"} }` | [rive-app/rive-android ~0.5k★](https://github.com/rive-app/rive-android) · [rive.app](https://rive.app/) | **P2** |
| **`state` container** | One node switches among named states (loading/empty/error/content) driven by a variable, with transitions. DivKit `div-state` — the backbone of reactivity. | all | `{ "type":"state","bind":"$state.phase","states":{"loading":{…},"error":{…},"content":{…}} }` | [DivKit div-state](https://divkit.tech/docs/en/concepts/divs/2/div-state) | **P2** |
| **`table` / `web`** | Adaptive-Cards-style typed-column table for enterprise dashboards; embedded webview for T&C/help/partner content. | RU-enterprise, all | `{ "type":"table","columns":[…],"rows":[…] }` · `{ "type":"web","source":"$data.tos.url" }` | [AdaptiveCards 1.5 Table](https://github.com/microsoft/AdaptiveCards) | **P2** |

**Extend, don't add — `chart` and `list`:**

- **`chart`** gains `style:"candlestick"|"ohlc"`, `interaction:{scrub,crosshair,onScrub,haptic}`,
  `baseline:{value,aboveColor,belowColor}` (directional green/red), and `ranges` (a
  segmented control wired to swap the series). Robinhood-exact.
  Source: [TradingView lightweight-charts 16.7k★](https://github.com/tradingview/lightweight-charts) ·
  [MPAndroidChart 38k★](https://github.com/PhilJay/MPAndroidChart) ·
  [danielgindi/Charts ~28k★](https://github.com/danielgindi/Charts) ·
  [vico 2.4k★](https://github.com/patrykandpatrick/vico) (Compose-native primary). **P1**
- **`list`** gains `sections:{groupBy,stickyHeaders,headerStyle}` (Monzo day-grouped feed,
  Weather pinned headers) — see 15 §F2 for the pipeline it plugs into. **P0**

---

## 3. New actions + runtime capabilities

### 3.1 Actions to implement / add

| Action | Enables | Notes / source | Prio |
|---|---|---|---|
| **`request`** (implement) | Every write path: form submit, server pagination, optimistic update, search-to-server. **Schema exists but it is a no-op on all platforms.** | 15 §F1 — resolve `source` → `host.loadOne` → inject `$data.<id>` → dispatch `onSuccess`/`onError` | **P0** |
| **`listAppend` / `listRemove` / `listUpsert`** | Client-side cart / collection mutation (add item w/ qty+mods, remove by predicate, upsert by match field). | food-delivery cart; generalizes to `arrayInsert/arrayRemove/arraySet` (15 §T1) | **P0** |
| **`requestPermission`** (implement) | Location for delivery, camera for scan, notifications. **In the enum but a silent no-op on Android** (15 §P3). Add a `resultBind` + `onGranted/onDenied`. | 15 §P3 — mirror the iOS priming→prompt→resultKey orchestration | **P0** |
| **`biometricAuth`** | Face ID / fingerprint unlock + step-up for high-risk actions (reveal card, confirm payment). | `LAContext` (iOS) / `BiometricPrompt` (Android); [Pragmatic Coders](https://www.pragmaticcoders.com/blog/biometric-authentication-in-android-fintech-apps) | **P1** |
| **`flyToCart`** | The parabola-into-badge add-to-cart — the most-copied QSR micro-interaction. Pairs with `matchedId` (§5). | `{ "action":"flyToCart","from":"$item.image","to":"cartTab","arc":"parabola","durationMs":550,"then":{"action":"haptic","style":"success"} }` · [FlyToCart iOS](https://github.com/pratik-123/FlyToCart) / [Android](https://github.com/matrixdevz/FlyToCartAnimation) | **P1** |
| **`confetti` / `celebrate` / `burst`** | Milestone celebration (reward unlocked, first order, first trade) and per-gesture like-burst. **Reserved-by-design** — the Robinhood-removed-confetti lesson: milestones only. Honors Reduce Motion. | `{ "action":"celebrate","style":"confetti","haptic":"success","duration":1.5 }` · [CNBC/Robinhood](https://www.cnbc.com/2021/03/31/robinhood-gets-rid-of-confetti-feature-amid-scrutiny-over-gamification.html) · [ConfettiSwiftUI 2.4k★](https://github.com/simibac/ConfettiSwiftUI) / [Konfetti 3.4k★](https://github.com/DanielMartinus/Konfetti) | **P1** |
| **`purchase` / `restorePurchases`** | Trigger the OS purchase sheet + restore. Contract only *triggers* the store sheet — never handles payment credentials. | StoreKit 2 / Play Billing via [RevenueCat SDKs](https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps) | **P1** |
| **`exportPDF` / `pickPhotos` / `pickFile` / `saveFile`** (implement) | Scanner→PDF export, multi-image picker, document picker, file save. **`saveFile` is unimplemented everywhere.** | 15 §F (matrix F) | **P1** |
| **`patch`** | Surgical partial update of one node (replace/append/prepend/remove/merge) without a full re-render — kills scroll-loss + flicker. DivKit `div-patch`. | `{ "action":"patch","target":"<id>","mode":"append","value":… }` · [13-div-patch-spec.md](13-div-patch-spec.md) · 15 §T0.3 | **P2** |
| **Action fills** (`copyToClipboard`, `setVariable`, pager control `setCurrentItem/next/prev`, `scrollBy`, form `submit`, `focusElement`/`clearFocus`, `setStoredValue`, `animatorStart/Stop`, `video` control) | Completeness — each is a few schema lines. We have `pager` but no action to drive it; no form `submit` to aggregate a subtree → one POST. | 15 §T1 | **P2** |

### 3.2 Runtime capabilities (data / binding / device)

- **Expression language + binding math (P0).** The quiet dependency of half this document.
  Today the only dynamic value is a `$state.<key>` literal. Add DivKit-style `@{…}`
  accepted anywhere `BindableString` is, with a **closed function catalog**:
  `$fmt.currency($sum($state.cart[*].lineTotal),'RUB')`, `$sum(...)`, `$count(...)`,
  `$fmt.percent`, `$fmt.compact`, arithmetic/comparison/ternary/string ops. Without it,
  every live total, badge-when-count>0, and price×qty round-trips to the server.
  Identical `ExpressionEvaluator` on both platforms.
  ([DivKit div-action](https://divkit.tech/docs/en/concepts/divs/2/div-action) ·
  [AdaptiveCards templating](https://github.com/microsoft/AdaptiveCards/issues/2448) · 15 §T0.1)
- **`format` primitive (P0).** A cross-cutting `format` object (style/currency/locale/
  fractionDigits/sign) wherever a numeric value is displayed, so `NumberFormatter` (iOS)
  and `NumberFormat` (Android) produce **identical** output. Dependency of
  `counter`/`donut`/`summary`/`gauge`. (banking C13)
- **Cursor pagination + prefetch + impressions (P0/P1).** Extend `DataSource` with
  `pagination:{cursorParam,nextCursorPath,itemsPath,prefetchNext,prefetchMedia}` and give
  `list` a network `onReachEnd:{action:"request"}` that **appends** (today's `list.limit`
  is a local counter only — 15 §F5), plus a `newItemsPill` binding. (media)
- **`onVisible` / `onImpression` gesture + `visibilityThreshold` (P1).** A component-level
  visibility hook (mirrors `onTap`) that fires an analytics event when an item crosses a
  threshold — and *also* drives `video.autoplay:"onVisible"`. (media)
- **New binding namespaces:** `$entitlement.<id>` (paywall gating via
  `visibleWhen:{exists:"$entitlement.pro"}`), `$permission.<kind>`, `$scan` (scanner
  result), `$gesture.*` / `$scroll.*` (read-only live gesture/scroll values, §4).
- **`debounceMs` on search/textfield (P2)** — `snapshotFlow{q}.debounce` / `Task.sleep`
  cancel (15 §F6). **State restoration (P2)** — back `$state` with `rememberSaveable` /
  `SavedStateHandle` (15 §F8). **`openDeepLink` un-aliased from `openURL` (P2)** — route
  through `host.navigate` not the browser (15 §F7).

---

## 4. Motion / animation model

Our entire animation surface today is `{ curve: linear|easeIn|easeOut|easeInOut|spring,
duration }` — and `spring` has no damping/stiffness/mass/velocity, so it is a magic word,
not a spec. DivKit already expresses entrance/exit, layout, press, keyframe timelines, and
Lottie **entirely in JSON**; that is our bar. The model, in build order:

**M1 — Real spring spec (P0, foundation for everything).** Replace the two-field stub with
a discriminated `type`:
```json
"animation": {
  "type": "spring",
  "spring": { "response": 0.4, "dampingFraction": 0.8, "initialVelocity": 0 },
  "delay": 0, "repeat": { "count": 1, "autoreverse": false }
}
```
`type:"easing"` keeps `{curve,duration}` and adds `cubicBezier` + `controlPoints`. Maps to
SwiftUI `.spring(response:dampingFraction:)` / Compose `spring(dampingRatio,stiffness)`.
Bake Apple's defaults as the no-param spring: nav/sheet `response 0.35–0.5, damping
0.8–0.86`; press-feedback scale `0.955`, `response 0.3, damping 0.7`.
([apple-signature §E]; reference physics: [facebookarchive/pop ~19k★](https://github.com/facebookarchive/pop))

**M2 — Global Reduce-Motion contract (P0).** A screen-level `motion:{reduceMotion:"auto",
maxDuration:0.6}` every primitive below must consult — parallax/stretch/spring-overshoot
fall back to cross-fade, Lottie freezes at a static frame. Non-negotiable for RU/enterprise
accessibility; today only partly honored (matrix 🟡 iOS / ⬜ Android).

**M3 — Declarative entrance/exit + stagger (P1).** Port DivKit's `transition_in/out`:
```json
"transition": {
  "in":  { "type":"set","of":[{"type":"fade","from":0},{"type":"slide","edge":"bottom","distance":24}],
           "animation":{"type":"spring","spring":{"response":0.5,"dampingFraction":0.85}} },
  "out": { "type":"fade","to":0 },
  "triggers": ["appear","visibility","dataChange"]
}
```
Plus `stagger:{each:0.04,from:"top",transition:{…}}` on any collection → cascading reveal.
Maps to SwiftUI `.transition` + `withAnimation` / Compose `AnimatedVisibility`.

**M4 — Shared-element / hero transition (P1, the single biggest gap).** ⬜ everywhere in
the matrix; named by media, Apple, food, banking, and motion teams. A stable `matchId`
pairs a node on screen A with one on screen B; `navigate` opts in:
```json
{ "type":"image","matchId":"product.$item.id.photo","source":"$item.photo" }
{ "action":"navigate","to":"detail","transition":"hero",
  "hero":{ "match":["product.$item.id.photo"], "style":"containerTransform" } }
```
`style`: `containerTransform | crossfade | sharedAxisX/Y/Z`. iOS `matchedGeometryEffect` /
`.navigationTransition(.zoom)` (iOS 18); Android **MaterialContainerTransform** / Compose
`SharedTransitionLayout` (1.7+). Powers App-Store card→detail, Photos thumb→full, Music
mini→full, menu-card→product-sheet, and Photos swipe-down-shrink-to-source.
([Material Motion M3](https://m3.material.io/blog/android-material-motion) ·
[Compose shared elements](https://developer.android.com/develop/ui/compose/animation/shared-elements) ·
[skydoves/orbital ~700★](https://github.com/skydoves/orbital) ·
[material-components-android ~15k★](https://github.com/material-components/material-components-android))

**M5 — Lottie & Rive components (P1 / P2).** See §2 — `lottie` (P1, straight port,
huge payoff) and `rive` (P2, interactive state machines with `$state`-bound inputs).

**M6 — Gesture- & scroll-linked motion (P2).** Expose the drag/scroll value as a readable
binding so any modifier tracks it live, plus interpolation helpers `@lerp/@clamp/@map`:
```json
{ "type":"bottomSheet","drag":{"value":"$gesture.sheetDrag"},
  "modifiers":{ "opacity":"$gesture.sheetDrag","scale":"@lerp($gesture.sheetDrag,1.0,0.92)" } }
```
And `scrollEffect:{parallax:0.5,bind:[{property:"blur","range":[0,200],"to":[0,20]}]}` —
generalizes collapsing-scroll into a reusable "scroll offset → any property" mapper.
Reanimated is the mental-model reference:
[react-native-reanimated ~9k★](https://github.com/software-mansion/react-native-reanimated).

**M7 — Number roll + shimmer modifier (P1 / P2).** `animateChange:{style:"roll",
durationMs:300}` on `text`/`counter` for rolling totals/balances; a `shimmer:{active:
"$state.loading"}` modifier so *any* node shimmers while its binding loads (generalizes the
existing skeleton). [compose-shimmer ~1k★](https://github.com/valentinilk/compose-shimmer) ·
[facebook/shimmer-android ~5.3k★](https://github.com/facebook/shimmer-android).

The **collapsing-hero / parallax `scrollBehavior` upgrade** (Weather stretchy hero + scrim
+ parallax + pinned section headers) is specified end-to-end in
[15 §P1 and §4](15-android-parity-and-features.md) with exact numbers (`range=156`,
smoothstep, four staged segments, snap); it is the motion track's largest parity item and
lands in P1 alongside M3/M4.

---

## 5. New modifiers, materials & shapes

| Addition | What it enables | Maps to | Prio |
|---|---|---|---|
| **`cornerStyle:"continuous"`** | Superellipse squircle (G2) vs circular arc (G1) on every card. iOS uses `.continuous` everywhere; Android's circular arc reads visibly tighter at r≥16. | SwiftUI `RoundedRectangle(style:.continuous)` / vendor `SmoothRoundedCornerShape`; [racra/smooth-corner-rect 74★](https://github.com/racra/smooth-corner-rect-android-compose) — see 15 §P4 D1 | **P0** |
| **Shared shadow helper** (`Modifier.sduiDropShadow`) | True colored offset soft shadow (x/y/blur/tint) — Android currently drops offset + caps blur to elevation. | `drawBehind` + `BlurMaskFilter` — 15 §P4 D2 | **P0** |
| **`matchId` / `matchedGeometry`** | The shared-element pairing modifier behind M4. | §4 M4 | **P1** |
| **`animation` spring object** | Per-modifier spring tuning (§4 M1) applied anywhere motion is specified. | §4 M1 | **P0** |
| **`visibleIf` / `enabledIf`** | Expression-driven conditional visibility/enablement on any node (badge when count>0, disable until valid) — pairs with the expression language. | 15 §T0.1 / §T3 | **P0** |
| **`mask`** (display-side) | Hide-and-reveal sensitive display (PAN/balance) — distinct from `secure` which only masks *input*. `{mask:{reveal:"$state.showPan","pattern":"•••• {last4}"}}`. | [Eleken](https://www.eleken.co/blog-posts/modern-fintech-design-guide) | **P2** |
| **Liquid Glass material tier** | `material:"glass"` routes to iOS 26 Liquid Glass (interactive lensing/specular), falling back to `.regularMaterial` below; Android/Aurora real blur via `RenderEffect` / [chrisbanes/haze ~2.3k★](https://github.com/chrisbanes/haze). | [WWDC25 Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · 15 §P4 D3 | **P2** |
| **`shimmer`** modifier | Generalized shimmer (§4 M7). | §4 M7 | **P2** |

**New top-level artifacts (iOS-specific, P2):** `liveActivity` (Lock Screen + Dynamic
Island four-region layout, tied to APNs updates) and `widget` (timeline-driven, family +
deep-link) — sibling artifacts of `Screen`, mapping 1:1 to ActivityKit / WidgetKit.
([ActivityKit guide](https://dev.to/canopassoftware/integrating-live-activity-and-dynamic-island-in-ios-a-complete-guide-4i78);
apple-signature C10/C11.)

---

## 6. Phased roadmap

Sequenced so a backend team crosses a usable threshold as early as possible. Each phase
references the concrete iOS/Android fix locations already in
[doc 15](15-android-parity-and-features.md).

### P0 — Unblock real apps (contract + runtime foundation + zero-native-SDK revenue path)

Without these you can describe a screen but cannot build an app. Almost all are pure
contract + layout + local state — they land at parity fastest.

1. **`request` action** (15 §F1) + **Android list pipeline** (15 §F2) + **Android
   pull-to-refresh** (15 §F3) + **cursor pagination/append** (15 §F5). *Turns "demo" into
   "usable by a large app."*
2. **Expression language + binding math** (`@{…}`, `$fmt`/`$sum`/`$count`) + **`format`
   primitive** + **`visibleIf`/`enabledIf`** (15 §T0.1). *The dependency of every live
   total, balance, and badge.*
3. **`optionGroup` + `stepper` + `counter`** + **cart mutation actions**
   (`listAppend/Remove/Upsert`). *The entire QSR customizer→cart and fintech-balance
   revenue path, no native SDK.*
4. **`sheet`/`bottomSheet` detents + pinned footer** and **`list` sections (grouped/sticky
   headers)** + **`richtext`**. *Product-detail surface, grouped feeds, any comment/tweet.*
5. **Motion foundation:** real spring spec (§4 M1) + global Reduce-Motion contract (§4 M2).
6. **`requestPermission` (implement) + `requireVersion`** (15 §P3) — both silent no-ops on
   Android today.
7. **Card-design parity helpers:** `cornerStyle:"continuous"` + shared drop-shadow
   (15 §P4 D1/D2) + **`Screen.nav` contract** with centered title + trailing actions
   (15 §P2). *Makes chrome authorable at all.*

### P1 — Signature polish (makes it read premium / first-party)

The layer that separates "a feed-ish app" from "the app these companies ship."

8. **`video`** (autoplay-on-visible + `seekbar` + PiP/fullscreen) + `onVisible`/impression
   hook — unlocks YouTube/TikTok/Reels/X and upgrades `clips` to carry real video.
9. **Shared-element / hero transition** (§4 M4) + **declarative entrance/exit + stagger**
   (§4 M3) + **`lottie` component** (§4 M5) — the three highest delight-per-effort motion
   ports.
10. **Collapsing hero / Weather scroll** end-to-end on Android + iOS polish
    (15 §P1 + §4) — the largest visible parity break.
11. **Social layer:** `story`/`stories` + `storyRing` + `avatar` + `reaction`/`burst` +
    `flyToCart` + `confetti`/`celebrate` + `stickyNav` + `tabs`.
12. **Fintech layer:** extended `chart` (scrub + candlestick + ranges + baseline + haptic)
    + `donut` + `summary` + `card` flip + `pinpad` + `otp` + `biometricAuth`.
13. **Delivery layer:** `map` + `orderTracker` + `requestPermission(location)`.
14. **Device-capability layer:** `scanner` (+ `cropper` + `pdfview` + `signature`) +
    `exportPDF`/`saveFile`/`pickPhotos` + `wizard` + form validation + `planselect` +
    `purchase`/`restorePurchases` + `gauge` + `servicegrid`.

### P2 — Advanced (contract ceiling + platform reach)

15. **Architectural contract:** `patch`/partial-update (15 §T0.3, [doc 13](13-div-patch-spec.md))
    + templates + `$data` iteration (15 §T0.4) + typed variables/triggers (15 §T0.2) +
    `state` container + action fills (15 §T1).
16. **Interactive motion tier:** `rive` component + gesture/scroll-linked `$gesture.*`/
    `$scroll.*` bindings + parallax `scrollEffect` + `shimmer` modifier + number-roll.
17. **Platform-native artifacts:** `liveActivity` / Dynamic Island + `widget` (iOS);
    Liquid Glass material tier; `mask` modifier.
18. **Completeness:** `table` + `web` + `marquee`; deep-link routing (15 §F7); state
    restoration (15 §F8); debounced search (15 §F6); offline-cache DB
    ([doc 11](11-offline-cache-spec.md)) + resilience `fallback`/`requires` (15 §T3).

---

## Cross-cutting sourcing notes

- **DivKit** ([2.7k★](https://github.com/divkit/divkit)) is the closest cross-platform SDUI
  peer and the reference for the expression language, typed variables/triggers, `div-patch`,
  templates, `div-tabs`, `div-state`, and the entire declarative motion model. Study it
  first for any architectural item.
- **Airbnb Lottie** ([ios 26.8k★](https://github.com/airbnb/lottie-ios) /
  [android 35.7k★](https://github.com/airbnb/lottie-android)) is the one animation asset
  format that gives identical output on both platforms from a single JSON — adopt it as the
  `lottie` backend and the confetti/tracker/onboarding motion source.
- **Whole-app composition + tokens + dark mode** references:
  [nowinandroid 21.4k★](https://github.com/android/nowinandroid) +
  [compose-samples/Jetsnack 23.3k★](https://github.com/android/compose-samples) (Android),
  [IceCubesApp ~7k★](https://github.com/Dimillian/IceCubesApp) (iOS theming engine).
- Every capability maps to a native mechanism — AVPlayer/Media3, VisionKit/ML Kit,
  MapKit/MapLibre, StoreKit/Play Billing, LAContext/BiometricPrompt, matchedGeometry/
  SharedTransitionLayout — so the "one JSON, identical native screens" promise holds at
  every tier.
