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

// Typography weight: the bold/semibold leaves of the type scale.
function fontBold(style) {
    return /^(largeTitle|title|title1|title2|title3|headline)$/.test(String(style || ""));
}

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
