// Binding + token resolution for the Aurora SDUI renderer — the QML/ES5
// counterpart of iOS BindingEngine / Android BindingEngine. Pure functions, no
// QML types, so it can be a shared `.pragma library`. ECMAScript 5 only (Qt 5.6
// V4 engine): no let/const/arrow functions.
.pragma library

function _get(obj, parts) {
    var cur = obj;
    for (var i = 0; i < parts.length; i++) {
        if (cur === undefined || cur === null) return undefined;
        cur = cur[parts[i]];
    }
    return cur;
}

function _lookup(token, ctx) {
    var parts = token.split('.');
    var ns = parts.shift();
    if (ns === '$token') return _get(ctx.tokens, parts);
    if (ns === '$state') return _get(ctx.state, parts);
    if (ns === '$data')  return _get(ctx.data, parts);
    if (ns === '$env')   return _get(ctx.env, parts);
    if (ns === '$item')  return _get(ctx.item, parts);
    return undefined;
}

function isBinding(s) {
    return typeof s === 'string' && s.length > 0 && s.charAt(0) === '$';
}

// Resolve a bindable value. A whole-string binding ("$token.color.primary")
// returns its real typed value; a literal with embedded $tokens is interpolated;
// anything else passes through untouched. A missing binding resolves to '' —
// never an error (same contract as iOS/Android).
function resolve(value, ctx) {
    if (typeof value !== 'string') return value;
    if (isBinding(value) && value.indexOf(' ') === -1 && value.indexOf('$', 1) === -1) {
        var v = _lookup(value, ctx);
        return v === undefined ? '' : v;
    }
    return value.replace(/\$[A-Za-z_][A-Za-z0-9_.]*/g, function (m) {
        var v = _lookup(m, ctx);
        return (v === undefined || v === null) ? '' : String(v);
    });
}

function str(value, ctx) {
    var v = resolve(value, ctx);
    return (v === undefined || v === null) ? '' : String(v);
}

function color(value, ctx, fallback) {
    if (value === undefined || value === null) return fallback;
    var v = resolve(value, ctx);
    if (typeof v === 'string' && v.length > 0) return v;
    return fallback;
}

function num(value, ctx, fallback) {
    if (value === undefined || value === null) return fallback;
    var v = resolve(value, ctx);
    if (typeof v === 'number') return v;
    if (typeof v === 'string' && v.length > 0 && !isNaN(Number(v))) return Number(v);
    return fallback;
}

// Map a typography ref ("$token.typography.title2") to a pixel size — a v0
// heuristic on the leaf name. TODO: resolve from the tokens file's typography
// table once its shape is wired through.
function fontSize(style) {
    if (typeof style !== 'string') return 20;
    var leaf = style.split('.').pop();
    var table = {
        largeTitle: 40, title: 32, title1: 30, title2: 26, title3: 22,
        headline: 20, body: 18, callout: 17, subheadline: 16,
        footnote: 14, caption: 13, caption2: 11
    };
    return table[leaf] !== undefined ? table[leaf] : 18;
}
