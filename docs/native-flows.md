# Redirecting into existing native flows

Yes — an SDUI screen can jump into your app's **existing native flows**, not just
other SDUI screens. This is what makes SDUI adoptable incrementally: server-driven
screens and hand-written native screens live side by side.

## How it works

Navigation actions are declarative; the host decides what they mean. The runtime
hands `navigate` / `dismiss` / `openDeepLink` / `custom` to your `ActionHost`
(iOS) or the equivalent on Android. Your router inspects the target and routes it
either to an SDUI screen or straight into a native flow:

```swift
final class AppRouter: SDUIHostDelegate {
    func navigate(to screen: String, params: [String: JSONValue], transition: String) {
        switch screen {
        case "checkout":            // an existing native flow
            appCoordinator.startCheckout(productId: params["productId"]?.stringValue)
        case let sduiId where isServerDriven(sduiId):
            container.push(SDUIRoute(screen: sduiId, params: params))
        default:                    // fall back to a deep link
            deepLinkRouter.open(screen, params)
        }
    }

    func custom(name: String, payload: JSONValue?) {
        // App-specific bridges: open a native scanner, wallet, share sheet, etc.
        if name == "openScanner" { appCoordinator.openScanner() }
    }
}
```

So from a JSON screen:

```json
{ "action": "navigate", "to": "checkout", "params": { "productId": "$data.product.id" } }
```

…lands the user in your **native** checkout — the SDUI screen never needs to know
it isn't another SDUI screen.

## Patterns

- **`navigate` to a known route** → the host maps it to a native flow or an SDUI
  screen (its choice, per id).
- **`openDeepLink` / `openURL`** → hand off to your deep-link router (universal
  links, `myapp://…`).
- **`custom { name, payload }`** → an app-defined bridge for anything native the
  contract doesn't model (biometrics, camera, wallet, native paywall).

## Why this is the point

You migrate screen-by-screen: turn one flow server-driven, keep the rest native,
and let `navigate`/`custom` stitch them together. No big-bang rewrite.
