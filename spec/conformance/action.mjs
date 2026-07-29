// JS reference for the action interpreter — a faithful port of the observable behavior of
// ios/Sources/SDUIRuntime/ActionInterpreter.swift (and its Android/Aurora twins). Instead
// of driving a real host, it records an ORDERED list of effects and mutates a state map,
// so the conformance harness can assert every renderer interprets an action identically.
//
// Modeled (deterministic, host-independent): analytics-first ordering, sequence/parallel
// (both in-order), condition (then/else), navigate, dismiss, dismissRoot, openURL/
// openDeepLink, setState, increment (with $state. prefix strip + numeric default), refresh,
// showToast, scrollTo, haptic, share, log, custom. `delay` produces no observable effect
// (matches iOS: it only sleeps). Host-outcome verbs (request/saveFile/preview/
// requireVersion/requestPermission) are out of scope for Level-A effects and recorded as
// { type, unmodeled:true } so a fixture never silently asserts wrong behavior.

import { resolve, resolveString, evalCondition } from './binding.mjs';

const resolvedValue = (v, ctx) => (typeof v === 'string' ? resolve(v, ctx) : v);
const numberOf = (v) => (typeof v === 'number' ? v : (typeof v === 'string' && v.trim() !== '' && !isNaN(Number(v)) ? Number(v) : 0));

// Interpret `action` against `ctx` (whose `state` is mutated in place), appending to `effects`.
export function interpret(action, ctx, effects) {
  if (!action || typeof action !== 'object') return effects;
  if (action.analytics?.event !== undefined) effects.push({ type: 'analytics', event: action.analytics.event });

  const k = action.action;
  switch (k) {
    case 'sequence':
    case 'parallel':
      for (const child of action.actions || []) interpret(child, ctx, effects);
      break;

    case 'condition':
      if (evalCondition(action.if, ctx)) { if (action.then) interpret(action.then, ctx, effects); }
      else if (action.else) interpret(action.else, ctx, effects);
      break;

    case 'navigate': {
      const e = { type: 'navigate', to: resolveString(action.to, ctx), transition: action.transition || 'push' };
      if (action.params) { e.params = {}; for (const [pk, pv] of Object.entries(action.params)) e.params[pk] = resolve(pv, ctx); }
      effects.push(e);
      break;
    }
    case 'dismiss': effects.push({ type: 'dismiss' }); break;
    case 'dismissRoot': effects.push({ type: 'dismissRoot' }); break;
    case 'openURL': case 'openDeepLink': effects.push({ type: 'openURL', url: resolveString(action.url, ctx) }); break;

    case 'setState': {
      if (action.key === undefined) break;
      const value = resolvedValue(action.value, ctx);
      ctx.state[action.key] = value;
      effects.push({ type: 'setState', key: action.key, value });
      break;
    }
    case 'increment': {
      if (action.key === undefined) break;
      const by = action.by !== undefined ? Number(action.by) : 1;
      const bare = action.key.startsWith('$state.') ? action.key.slice('$state.'.length) : action.key;
      const next = numberOf(ctx.state[bare]) + (isNaN(by) ? 1 : by);
      ctx.state[bare] = next;
      effects.push({ type: 'setState', key: bare, value: next });
      break;
    }
    case 'refresh': effects.push({ type: 'refresh', sources: (action.sources || []).slice() }); break;
    case 'showToast': {
      const e = { type: 'showToast', message: resolveString(action.message, ctx) };
      if (action.style !== undefined) e.style = action.style;
      effects.push(e);
      break;
    }
    case 'delay': break; // no observable effect (iOS only sleeps)
    case 'scrollTo': effects.push({ type: 'scrollTo', target: resolveString(action.target, ctx) }); break;
    case 'haptic': { const e = { type: 'haptic' }; if (action.style !== undefined) e.style = action.style; effects.push(e); break; }
    case 'share': {
      const e = { type: 'share' };
      if (action.text !== undefined) e.text = resolveString(action.text, ctx);
      if (action.url !== undefined) e.url = resolveString(action.url, ctx);
      effects.push(e);
      break;
    }
    case 'log': effects.push({ type: 'log', message: resolveString(action.message, ctx) }); break;
    case 'analytics': break; // already emitted via action.analytics
    case 'custom': {
      if (action.name === undefined) break;
      const e = { type: 'custom', name: action.name };
      if (action.payload !== undefined) e.payload = resolvedValue(action.payload, ctx);
      effects.push(e);
      break;
    }
    default: effects.push({ type: k, unmodeled: true });
  }
  return effects;
}

// Convenience: run an action against a fresh-ish ctx, return { effects, state }.
export function runAction(action, ctx) {
  const effects = [];
  interpret(action, ctx, effects);
  return { effects, state: ctx.state };
}
