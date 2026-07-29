// JS reference for the binding + condition engine — a faithful port of
// ios/Sources/SDUICore/BindingEngine.swift (and its Android/Aurora twins). Kept here so
// the conformance harness can assert that all three renderers resolve identically.
//
// Rules (mirrored exactly):
//  • Whole-string binding ("$data.product.title") → the resolved node's real value/type.
//  • Interpolation ("Hello, $state.name") → each $token replaced by its string value.
//  • Prefixes: $token.<path> · $data.<sourceId>.<path> · $state/$env/$params.<key>.<path>
//    · $item.<path>. For data/state/env/params, the first segment is the key and the rest
//    is the path INTO that key's value (a lone key returns the whole value).
//  • Indirection: a value that is itself a whole-binding string resolves again (depth-guarded).

const TOKEN = /\$[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*/g;
const WHOLE = /^\$[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*$/;

function valueAt(obj, path) {
  let cur = obj;
  for (const k of path) { if (cur == null) return undefined; cur = cur[k]; }
  return cur;
}

// iOS JSONValue.stringValue: string→itself, number/bool→its description, else nil.
function stringValue(v) {
  if (typeof v === 'string') return v;
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  return null; // array / object / null / undefined have no stringValue
}
const arrayValue = (v) => (Array.isArray(v) ? v : null);

function resolveToken(token, ctx, depth) {
  if (depth > 10) return undefined;
  const parts = token.split('.');
  const prefix = parts[0], rest = parts.slice(1);
  let resolved;
  switch (prefix) {
    case '$token': resolved = valueAt(ctx.tokens, rest); break;
    case '$data': {
      const src = rest[0];
      resolved = rest.length <= 1 ? ctx.data?.[src] : valueAt(ctx.data?.[src], rest.slice(1));
      break;
    }
    case '$env': case '$state': case '$params': {
      const bag = prefix === '$env' ? ctx.env : prefix === '$state' ? ctx.state : ctx.params;
      const key = rest[0];
      resolved = rest.length <= 1 ? bag?.[key] : valueAt(bag?.[key], rest.slice(1));
      break;
    }
    case '$item': resolved = rest.length === 0 ? ctx.item : valueAt(ctx.item, rest); break;
    default: resolved = undefined;
  }
  // Indirection: resolved value is itself a whole-binding → resolve again.
  if (typeof resolved === 'string' && WHOLE.test(resolved)) return resolveToken(resolved, ctx, depth + 1);
  return resolved;
}

// Full resolve → real value (whole-binding) or interpolated string.
export function resolve(input, ctx) {
  if (typeof input !== 'string') return input;
  if (WHOLE.test(input)) { const v = resolveToken(input, ctx, 0); return v === undefined ? null : v; }
  return input.replace(TOKEN, (m) => { const sv = stringValue(resolveToken(m, ctx, 0)); return sv == null ? '' : sv; });
}

// Display string (empty when null) — what most text/label bindings render.
export function resolveString(input, ctx) {
  const v = resolve(input, ctx);
  const sv = stringValue(v);
  return sv == null ? '' : sv;
}

export function evalCondition(cond, ctx) {
  if (!cond || typeof cond !== 'object') return false;
  if (cond.equals) return resolveString(cond.equals[0], ctx) === resolveString(cond.equals[1], ctx);
  if (cond.notEquals) return resolveString(cond.notEquals[0], ctx) !== resolveString(cond.notEquals[1], ctx);
  if (cond.exists !== undefined) {
    const v = resolve(cond.exists, ctx);
    if (v === null || v === undefined) return false;
    const sv = stringValue(v), av = arrayValue(v);
    return (sv != null && sv !== '') || (av != null && av.length > 0);
  }
  if (cond.not) return !evalCondition(cond.not, ctx);
  if (cond.and) return cond.and.every((c) => evalCondition(c, ctx));
  if (cond.or) return cond.or.some((c) => evalCondition(c, ctx));
  return false;
}
