# Conformance corpus

The shared fixture corpus that makes **"identical on iOS/Android/Aurora"** provable.
Full design: [docs/blueprint/09-conformance-fixtures.md](../../docs/blueprint/09-conformance-fixtures.md).

```
node spec/conformance/check.mjs          # run all fixtures (Level-A reference)
node spec/conformance/check.mjs <id>     # run named fixtures
```

Each `fixtures/<id>/` holds:
- `screen.json` — a minimal SDUI screen exercising one thing
- `tokens.json` — optional; defaults to `spec/schema/tokens.example.json`
- `expect.json` — platform-neutral assertions

`expect.json` keys:
- `validation`: `{ "valid": true }` or `{ "valid": false, "errorContains": "…" }` — reuses the production `Validator`.
- `bindings`: `{ "<input>": "<expected resolveString>" }` — resolved by `binding.mjs`, a
  faithful port of `BindingEngine` (whole-string + interpolation + all prefixes + indirection).
- `conditions`: `[ { "expr": <Condition>, "value": true|false } ]` — evaluated by the same port.
- Context for bindings/conditions comes from an optional `state.json`:
  `{ "state": {…}, "data": {…}, "env": {…}, "params": {…}, "item": {…} }` (+ tokens from `tokens.json`/default).
- `effects` / `render`: declared but reported as **pending** until their reference runners
  land (staged in doc 09). The harness never claims coverage it doesn't have.

**Contract:** each native platform will run these same fixtures in its own language, so a
fixture failing anywhere (or in the JS reference) is a red build. Adding a component /
modifier / action should come with a fixture.
