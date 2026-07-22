# Figma → SDUI (design-token bridge)

The goal: a designer changes a variable in Figma, and **every screen on every
platform** updates — no engineer in the loop. Because SDUI resolves everything
through `$token.<group>.<name>`, and that token file is platform-neutral, a
single Figma export drives iOS and Android at once.

## Today: tokens from Figma

Export your Figma **Variables** (via the native "Export variables" or a plugin
like *Tokens Studio* / *Design Tokens* — both emit the W3C Design Tokens format),
then convert:

```bash
node spec/tools/figma-tokens.mjs figma-export.json ios/…/Content/tokens.json
```

The converter ([`spec/tools/figma-tokens.mjs`](../spec/tools/figma-tokens.mjs)):

- flattens the token groups, so `color/primary` becomes `$token.color.primary`;
- resolves aliases (`{color.primary}`);
- normalises colours to hex, dimensions (`16px`) to points, and typography to
  `{ size, weight }`;
- works with W3C Design Tokens and Tokens Studio exports.

The result is a `tokens.json` the SDUI runtime already understands — the same
file the Android renderer will load. **One export, both platforms, every screen.**

## Live (optional)

With the Figma MCP connected, variables can be pulled straight from a file
(`get_variable_defs`) and piped through the same conversion — no manual export.
Point it at a file/frame and the tokens land in the contract.

## The vision: Figma → JSON → two platforms

The token bridge is step one. The end state:

1. **Tokens** — Figma Variables → `tokens.json` (done, above).
2. **Components** — map Figma components to SDUI `custom.*` / primitives via a
   naming convention, so a Figma frame can be read into a screen payload.
3. **Screens** — export a frame's layer tree → a validated SDUI JSON screen,
   which renders natively on iOS **and** Android from the one contract.

That last step is the killer feature: **design once in Figma, ship native on both
platforms, change anything from the backend.** The contract-first design (schema
validates before render) is exactly what makes automated generation safe.

## Dark mode / themes

Figma modes (Light/Dark, or brand themes) map to the token file's `color` vs
`colorDark` groups (and, later, per-theme files). `$env.theme` selects at render
time — see [`spec/docs/authoring.md`](../spec/docs/authoring.md).
