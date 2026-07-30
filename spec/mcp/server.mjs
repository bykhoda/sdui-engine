#!/usr/bin/env node
// SDUI MCP server — a zero-dependency Model Context Protocol server over stdio.
//
// It hands any Claude client (Claude Code, Claude Desktop, the API) the SDUI toolchain
// as native tools: introspect the contract, pull examples, scaffold a screen, and —
// above all — VALIDATE a payload before it ships. So anyone, whatever their craft,
// can just talk to Claude and build a real native screen from the one shared contract.
//
// Transport: newline-delimited JSON-RPC 2.0 on stdin/stdout (the MCP stdio transport).
// Logs go to stderr ONLY — stdout is the protocol stream and must stay clean.
//
// Register in Claude Code (.mcp.json) or Claude Desktop (claude_desktop_config.json):
//   { "mcpServers": { "sdui": { "command": "node", "args": ["spec/mcp/server.mjs"] } } }
// The contract dir resolves relative to this file, so it runs from any cwd. Set
// SDUI_SPEC_DIR to point one installed server at another checkout's spec/ instead.

import * as T from './tools.mjs';

const SERVER_INFO = { name: 'sdui', version: '0.1.0' };
const DEFAULT_PROTOCOL = '2025-06-18';   // only used if a client omits protocolVersion; we echo theirs otherwise
const log = (...a) => console.error('[sdui-mcp]', ...a);   // stderr, never stdout

// --- Tool registry: name → { description, inputSchema, run(args) → result-or-string }
const TOOLS = {
  validate_screen: {
    description: 'Validate an SDUI screen payload against the contract: unknown component/action types, missing required fields, dangling $data refs, and (by default) $token typos. Call this before serving any screen you build.',
    inputSchema: {
      type: 'object',
      properties: {
        payload: { type: 'object', description: 'The full screen document: { version, screen }.' },
        checkTokens: { type: 'boolean', description: 'Also verify every $token.* ref exists (default true).' },
      },
      required: ['payload'],
    },
    run: (a) => T.validateScreen(a.payload, { checkTokens: a.checkTokens !== false }),
  },
  lint_screen: {
    description: 'Design-lint an SDUI screen (the guardrail ABOVE validation): off-token color/spacing/radius literals, WCAG AA text contrast, sub-44pt tap targets, dead buttons, layout-jumpy images, and palette cohesion. Returns findings [{rule, severity, path, message, fix?}] plus a severity summary. Run it after validate_screen and reflect on the findings — many carry a machine-applicable `fix` patch. Same engine the visual composer badges with, so the verdict never drifts.',
    inputSchema: {
      type: 'object',
      properties: {
        payload: { type: 'object', description: 'The full screen document: { version, screen }.' },
        minSeverity: { type: 'string', enum: ['error', 'warn', 'info'], description: "Lowest severity to report (default 'info' = everything). Use 'error' to gate a ship." },
        rules: { type: 'array', items: { type: 'string' }, description: 'Optional allow-list of rule ids to run (e.g. ["a11y/contrast"]). Omit to run all.' },
      },
      required: ['payload'],
    },
    run: (a) => T.lintScreen(a.payload, { minSeverity: a.minSeverity ?? 'info', rules: a.rules ?? null }),
  },
  list_lint_rules: {
    description: 'List every design-lint rule lint_screen enforces, with its id, default severity, and rationale. Use this to see what "good" means before authoring, or to pick a `rules` filter.',
    inputSchema: { type: 'object', properties: {} },
    run: () => T.listLintRules(),
  },
  list_components: {
    description: 'List every component type the engine renders, with its required fields and purpose. Use this instead of guessing component names.',
    inputSchema: { type: 'object', properties: {} },
    run: () => T.listComponents(),
  },
  list_actions: {
    description: 'List every action kind (navigate, setState, request, requestPermission, …) with its required fields.',
    inputSchema: { type: 'object', properties: {} },
    run: () => T.listActions(),
  },
  list_tokens: {
    description: 'List the design tokens available to $token.* references, grouped, plus the flat set of every valid token path.',
    inputSchema: { type: 'object', properties: {} },
    run: () => T.listTokens(),
  },
  list_examples: {
    description: 'List the ready-made example screens (id + title) you can fetch with get_example.',
    inputSchema: { type: 'object', properties: {} },
    run: () => T.listExamples(),
  },
  get_example: {
    description: 'Fetch one full example screen payload by id (e.g. "feed", "signup_submit", "product_detail", "async_product").',
    inputSchema: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    run: (a) => T.getExample(a.id),
  },
  scaffold_screen: {
    description: 'Return a minimal, already-valid starter screen for an intent, ready to flesh out.',
    inputSchema: {
      type: 'object',
      properties: {
        kind: { type: 'string', enum: ['blank', 'list', 'form', 'detail'], description: 'Screen shape to scaffold.' },
        id: { type: 'string' }, title: { type: 'string' },
      },
      required: ['kind'],
    },
    run: (a) => T.scaffoldScreen(a.kind, { id: a.id ?? a.kind, title: a.title ?? 'Untitled' }),
  },
};

// --- Resources: read-only context a client can attach ------------------------------
function resourceList() {
  const base = [
    { uri: 'sdui://schema', name: 'SDUI JSON Schema', description: 'The full contract (JSON Schema 2020-12).', mimeType: 'application/json' },
    { uri: 'sdui://tokens', name: 'Design tokens', description: 'Example token set referenced by $token.*.', mimeType: 'application/json' },
    { uri: 'sdui://guide', name: 'Authoring guide', description: 'How to write payloads: bindings, components, actions.', mimeType: 'text/markdown' },
  ];
  for (const e of T.listExamples()) {
    base.push({ uri: `sdui://examples/${e.id}`, name: `Example: ${e.id}`, description: e.title || e.id, mimeType: 'application/json' });
  }
  return base;
}
function resourceRead(uri) {
  if (uri === 'sdui://schema') return { mimeType: 'application/json', text: JSON.stringify(T.getSchema(), null, 2) };
  if (uri === 'sdui://tokens') return { mimeType: 'application/json', text: JSON.stringify(T.listTokens(), null, 2) };
  if (uri === 'sdui://guide') return { mimeType: 'text/markdown', text: T.getGuide() };
  const m = uri.match(/^sdui:\/\/examples\/([A-Za-z0-9_.]+)$/);
  if (m) return { mimeType: 'application/json', text: JSON.stringify(T.getExample(m[1]), null, 2) };
  throw new Error(`unknown resource: ${uri}`);
}

// --- JSON-RPC plumbing -------------------------------------------------------------
function reply(id, result) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n'); }
function replyError(id, code, message) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }) + '\n'); }

function handle(msg) {
  const { id, method, params } = msg;
  const isRequest = id !== undefined && id !== null;   // notifications carry no id

  switch (method) {
    case 'initialize':
      return reply(id, {
        // Echo the client's protocol version when it sends one; otherwise a broadly-supported default.
        protocolVersion: params?.protocolVersion ?? DEFAULT_PROTOCOL,
        capabilities: { tools: {}, resources: {} },
        serverInfo: SERVER_INFO,
      });
    case 'notifications/initialized':
    case 'notifications/cancelled':
      return;   // notifications — no response
    case 'ping':
      return isRequest && reply(id, {});
    case 'tools/list':
      return reply(id, { tools: Object.entries(TOOLS).map(([name, t]) => ({ name, description: t.description, inputSchema: t.inputSchema })) });
    case 'tools/call': {
      const tool = TOOLS[params?.name];
      if (!tool) return replyError(id, -32602, `unknown tool: ${params?.name}`);
      try {
        const out = tool.run(params.arguments ?? {});
        const text = typeof out === 'string' ? out : JSON.stringify(out, null, 2);
        return reply(id, { content: [{ type: 'text', text }], isError: false });
      } catch (e) {
        // Tool-level failure is reported in-band (isError) so the model can react.
        return reply(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
      }
    }
    case 'resources/list':
      return reply(id, { resources: resourceList() });
    case 'resources/read': {
      try {
        const r = resourceRead(params?.uri);
        return reply(id, { contents: [{ uri: params.uri, mimeType: r.mimeType, text: r.text }] });
      } catch (e) { return replyError(id, -32602, e.message); }
    }
    default:
      if (isRequest) return replyError(id, -32601, `method not found: ${method}`);
  }
}

// --- stdin reader: newline-delimited JSON -----------------------------------------
let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); }
    catch { log('dropped non-JSON line'); continue; }
    try { handle(msg); }
    catch (e) { log('handler error:', e.message); if (msg?.id != null) replyError(msg.id, -32603, e.message); }
  }
});
process.stdin.on('end', () => process.exit(0));
log(`ready — ${Object.keys(TOOLS).length} tools, ${resourceList().length} resources`);
