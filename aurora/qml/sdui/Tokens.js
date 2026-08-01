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
    // ctx arrives a tick after a node instantiates (Loader chain in SduiRenderer/SduiChild);
    // resolve to undefined until then rather than throwing, and the binding re-evaluates once
    // ctx lands. Keeps token resolution null-safe.
    if (!ctx) return undefined;
    var parts = token.split('.');
    var ns = parts.shift();
    if (ns === '$token') {
        // Dark scheme: colour tokens resolve against the `colorDark` override block
        // (per-key fallback to the light `color` block for anything it omits) — the
        // same semantic-token resolution iOS/Android apply for the active appearance.
        if (parts[0] === 'color' && ctx.env && ctx.env.theme === 'dark'
                && ctx.tokens && ctx.tokens.colorDark) {
            var dparts = parts.slice();
            dparts[0] = 'colorDark';
            var dv = _get(ctx.tokens, dparts);
            if (dv !== undefined) return dv;
        }
        return _get(ctx.tokens, parts);
    }
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

// The contract expresses colours as #RRGGBB or #RRGGBBAA (the iOS/Android order).
// Qt parses hex strings as #AARRGGBB, so an 8-digit value handed to Qt untouched has
// its alpha byte read as red (e.g. #FFFFFF33 → opaque yellow). Re-order the alpha to
// the front so one contract renders identical colours on all three platforms.
function normHex(v) {
    if (typeof v === 'string' && v.charAt(0) === '#' && v.length === 9) {
        return '#' + v.substr(7, 2) + v.substr(1, 6);
    }
    return v;
}

function color(value, ctx, fallback) {
    if (value === undefined || value === null) return fallback;
    var v = resolve(value, ctx);
    if (typeof v === 'string' && v.length > 0) return normHex(v);
    return fallback;
}

function num(value, ctx, fallback) {
    if (value === undefined || value === null) return fallback;
    var v = resolve(value, ctx);
    if (typeof v === 'number') return v;
    if (typeof v === 'string' && v.length > 0 && !isNaN(Number(v))) return Number(v);
    return fallback;
}

// Evaluate a Condition (spec/schema Condition) against the render context — the
// QML/ES5 counterpart of iOS `Condition.evaluate(in:)` / Android
// `Condition.evaluate(ctx)`. Exactly one operator key is expected; unknown or
// empty conditions are false. `equals`/`notEquals` compare the two sides'
// resolved string forms; `exists` treats missing / null / empty-string /
// empty-array as false (numbers, bools and objects count as present — matching
// iOS, where a number's stringValue is non-empty).
function evalCondition(cond, ctx) {
    if (!cond || typeof cond !== 'object') return false;
    if (cond.equals !== undefined && cond.equals !== null) {
        return str(cond.equals[0], ctx) === str(cond.equals[1], ctx);
    }
    if (cond.notEquals !== undefined && cond.notEquals !== null) {
        return str(cond.notEquals[0], ctx) !== str(cond.notEquals[1], ctx);
    }
    if (cond.exists !== undefined && cond.exists !== null) {
        var v = resolve(cond.exists, ctx);
        if (v === undefined || v === null) return false;
        if (typeof v === 'string') return v.length > 0;
        if (Object.prototype.toString.call(v) === '[object Array]') return v.length > 0;
        return true;
    }
    if (cond.not !== undefined && cond.not !== null) return !evalCondition(cond.not, ctx);
    if (cond.and !== undefined && cond.and !== null) {
        for (var i = 0; i < cond.and.length; i++) {
            if (!evalCondition(cond.and[i], ctx)) return false;
        }
        return true;
    }
    if (cond.or !== undefined && cond.or !== null) {
        for (var j = 0; j < cond.or.length; j++) {
            if (evalCondition(cond.or[j], ctx)) return true;
        }
        return false;
    }
    return false;
}

// Map a typography ref ("$token.typography.title2") to a pixel size — a v0
// heuristic on the leaf name. TODO: resolve from the tokens file's typography
// table once its shape is wired through.
// SF-Symbol name → a Unicode/emoji glyph. Aurora ships no SF-Symbol font, so the `icon`
// component would otherwise paint the raw name ("figure.run", "cart.fill"). Covers the names
// used across the shared screens; unmapped names fall back to a neutral dot (never the raw
// string). ES5 only (Qt5 V4 engine).
var _GLYPHS = {
    // navigation / arrows
    "chevron.right": "›", "chevron.left": "‹", "chevron.up": "⌃", "chevron.down": "⌄",
    "arrow.right": "→", "arrow.left": "←", "arrow.up": "↑", "arrow.down": "↓",
    "arrow.up.right": "↗", "arrow.up.left": "↖", "arrow.down.right": "�’",
    "arrow.triangle.2.circlepath": "↻", "arrow.clockwise": "↻", "arrow.counterclockwise": "↺",
    "arrow.2.squarepath": "⇄", "arrow.up.arrow.down": "⇅", "arrow.left.arrow.right": "⇄",
    "arrow.triangle.branch": "⑂", "arrowshape.turn.up.left": "↩",
    "arrow.up.left.and.arrow.down.right": "⤢", "arrow.down.right.and.arrow.up.left": "⤡",
    "arrow.up.circle": "⊕", "arrow.down.circle": "⊖", "arrow.up.doc": "⤒",
    "chevron.right.circle": "›",
    // symbols / status
    "plus": "+", "plus.circle": "⊕", "minus": "−", "minus.circle": "⊖",
    "xmark": "✕", "xmark.circle": "⊗", "xmark.octagon": "⊗",
    "checkmark": "✓", "checkmark.circle": "✓", "checkmark.seal": "✔",
    "circle": "○", "capsule": "▭", "info.circle": "ⓘ", "questionmark.circle": "?",
    "exclamationmark.triangle": "⚠", "exclamationmark.bubble": "❕", "dollarsign.circle": "＄",
    "ellipsis": "…", "ellipsis.circle": "…", "line.3.horizontal": "≡", "list.bullet": "☰",
    "slider.horizontal.3": "▤", "switch.2": "⇄", "textformat": "A", "textformat.size": "A",
    "bold": "B", "character.cursor.ibeam": "⌶", "cursorarrow.rays": "✳",
    // people / social
    "person": "☻", "person.2": "☺", "person.fill": "☻", "person.crop.circle": "☻",
    "heart": "♥", "star": "★", "star.leadinghalf.filled": "★", "star.circle": "★",
    "bell": "🔔", "bell.badge": "🔔", "bell.slash": "🔕", "flag": "⚑", "bookmark": "🔖",
    "hand.thumbsup": "👍", "hand.thumbsdown": "👎", "hand.tap": "☝", "hand.draw": "✍",
    "hand.point.up.left": "☝", "hand.raised.slash": "✋", "crown": "♔", "gift": "🎁",
    "quote.bubble": "❝",
    // comms
    "bubble.left": "💬", "bubble.left.and.bubble.right": "💬", "message": "💬",
    "envelope": "✉", "envelope.open": "✉", "paperplane": "➤", "phone": "☎",
    "tray": "📥", "tray.full": "📥", "archivebox": "🗄",
    // media
    "play": "▶", "play.circle": "▶", "play.rectangle": "▶", "pause": "⏸",
    "backward": "⏮", "forward": "⏭", "shuffle": "🔀", "repeat": "🔁",
    "music.note": "♪", "music.note.list": "♫",
    "speaker.fill": "🔊", "speaker.wave.2": "🔊", "speaker.wave.3": "🔊", "headphones": "🎧",
    "film": "🎞", "video": "🎥", "photo": "🖼", "photo.on.rectangle.angled": "🖼",
    "camera": "📷", "qrcode": "▣",
    // docs / files
    "doc": "📄", "doc.text": "📄", "doc.richtext": "📄", "doc.on.doc": "🗐", "folder": "📁",
    "square.and.arrow.up": "⤴", "square.and.arrow.down": "⤵", "square.and.pencil": "✎", "pencil": "✎",
    "pencil.and.ruler": "📐", "checklist": "☑", "tablecells": "▦",
    // shapes / grids
    "square.grid.2x2": "▦", "square.grid.3x3": "▦", "square.stack": "▤", "square.stack.3d.up": "▤",
    "square.on.square": "❒", "rectangle.stack": "▤", "rectangle.portrait.and.arrow.right": "⎋",
    "rectangle.portrait.bottomhalf.inset.filled": "▭",
    // system / connectivity
    "house": "⌂", "gearshape": "⚙", "gear": "⚙", "lock": "🔒", "lock.open": "🔓",
    "wifi": "📶", "wifi.slash": "⊘", "battery.100": "🔋", "icloud": "☁",
    "externaldrive.badge.icloud": "☁", "dot.radiowaves.left.and.right": "📡",
    "airplayaudio": "📡", "cable.connector": "🔌", "shield.lefthalf.filled": "🛡",
    "bolt.shield": "🛡", "door.left.hand.closed": "🚪",
    // commerce
    "cart": "🛒", "bag": "🛍", "creditcard": "💳", "tag": "🏷", "shippingbox": "📦",
    // search / location / time
    "magnifyingglass": "🔍", "map": "🗺", "location": "📍", "location.circle": "📍",
    "pin": "📌", "calendar": "📅", "clock": "🕒",
    // nature / weather
    "flame": "🔥", "bolt": "⚡", "bolt.horizontal": "⚡", "bolt.badge.checkmark": "⚡",
    "bolt.horizontal.circle": "⚡", "drop": "💧", "leaf": "🍃",
    "sun.max": "☀", "sunrise": "🌅", "sunset": "🌇", "moon.stars": "☾", "moon": "☾",
    "cloud": "☁", "cloud.sun": "⛅", "cloud.moon": "☁", "cloud.rain": "🌧",
    // activity / fitness
    "figure.run": "🏃", "figure.walk": "🚶", "figure.walk.motion": "🚶", "figure.stairs": "🧗",
    "dumbbell": "🏋", "bicycle": "🚲",
    // charts / creative / tools
    "chart.bar": "📊", "chart.line.uptrend.xyaxis": "📈", "chart.pie": "◔",
    "paintpalette": "🎨", "sparkles": "✨", "wand.and.stars": "🪄", "wand.and.rays": "🪄",
    "cube": "⬢", "hammer": "🔨", "wrench": "🔧", "link": "🔗",
    // numbered badges
    "1.circle": "①", "2.circle": "②", "3.circle": "③",
    // brands (no glyph font → initial letter)
    "apple.logo": "", "safari": "❖"
};

// Resolve an SF-Symbol name to a glyph. Try the exact name, then progressively drop trailing
// dot-segments ("cloud.sun.fill" → "cloud.sun" → "cloud") so the many "*.fill"/"*.circle.fill"
// variants all fall back to their base without needing a row each. Unmapped → a neutral dot,
// never the raw SF string.
function glyph(name) {
    if (!name) return "";
    if (_GLYPHS[name] !== undefined) return _GLYPHS[name];
    var parts = String(name).split(".");
    while (parts.length > 1) {
        parts.pop();
        var key = parts.join(".");
        if (_GLYPHS[key] !== undefined) return _GLYPHS[key];
    }
    return "•";
}

// Typography resolves from the SHARED tokens (ctx.tokens.typography) — the same source iOS/Android
// read — so the three renderers use identical sizes/weights. The hardcoded table is only a fallback
// for a bare run where tokens haven't loaded. `style` is e.g. "$token.typography.largeTitle".
var _TYPE_FALLBACK = {
    hero: {size: 76, weight: "bold"}, display: {size: 44, weight: "bold"},
    largeTitle: {size: 32, weight: "bold"}, title: {size: 28, weight: "bold"},
    title2: {size: 22, weight: "bold"}, title3: {size: 20, weight: "semibold"},
    headline: {size: 17, weight: "semibold"}, body: {size: 17, weight: "regular"},
    callout: {size: 16, weight: "regular"}, subheadline: {size: 15, weight: "regular"},
    footnote: {size: 13, weight: "regular"}, caption: {size: 12, weight: "medium"},
    caption2: {size: 11, weight: "regular"}
};

function _typeSpec(style, ctx) {
    var leaf = (typeof style === "string") ? style.split(".").pop() : "body";
    var t = (ctx && ctx.tokens && ctx.tokens.typography) ? ctx.tokens.typography[leaf] : null;
    return t ? t : (_TYPE_FALLBACK[leaf] || _TYPE_FALLBACK.body);
}

function fontSize(style, ctx) {
    var s = _typeSpec(style, ctx).size;
    return (typeof s === "number") ? s : 17;
}

// Map a token weight name to a Qt Font.Weight enum value (so semibold ≠ bold, matching iOS/Android).
// Font.Normal=50, Medium=57, DemiBold=63, Bold=75, Black=87.
function fontWeight(style, ctx) {
    var w = String(_typeSpec(style, ctx).weight || "regular");
    if (w === "bold") return 75;
    if (w === "semibold") return 63;
    if (w === "medium") return 57;
    if (w === "heavy" || w === "black") return 87;
    return 50; // regular / light
}

// Kept for callers that still want a boolean.
function fontBold(style, ctx) {
    return fontWeight(style, ctx) >= 63;
}
