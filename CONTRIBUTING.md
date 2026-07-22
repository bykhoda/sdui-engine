# Contributing

Thanks for your interest in improving this SDUI engine. This project favours a
small, sharp core with a strictly versioned contract, so contributions are held
to a clear bar.

## Ground rules

- **The contract is the source of truth.** Any change to component types,
  actions, or bindings starts in [`spec/schema/sdui.schema.json`](spec/schema/sdui.schema.json).
  Platform renderers follow the schema, never the other way around.
- **Both platforms stay in sync.** A new capability must be expressible in the
  neutral contract and land on iOS and Android together (or ship behind a
  version bump with a documented gap).
- **No crashes on bad input.** Unknown components and missing bindings degrade
  safely. Add a test that proves it.

## Development

### iOS

```bash
cd ios
swift build
swift test
```

`SDUICore` is pure and fully unit-tested — new model, decoding, and binding
logic belongs there with tests. UI code lives in `SDUIRender`.

### Contract & examples

Validate any payload against the contract before committing:

```bash
node spec/tools/validate.mjs spec/examples/*.json
```

Every new capability should come with an example screen that exercises it.

## Pull requests

- Keep PRs focused; one concern each.
- Follow [Conventional Commits](https://www.conventionalcommits.org/) for commit
  and PR titles (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Update [`CHANGELOG.md`](CHANGELOG.md) under **Unreleased**.
- CI must be green: the package builds and tests pass, and all example payloads
  validate.

## Code style

- Match the surrounding code. Readability first: clear names, small types, and a
  short doc comment on every public symbol explaining *why*, not just *what*.
- 4-space indentation for Swift; 2 spaces for JSON/JS/YAML/Markdown (see
  [`.editorconfig`](.editorconfig)).

By contributing, you agree that your contributions are licensed under the
project's [Apache-2.0 License](LICENSE).
