// The recursive SDUI renderer for Aurora — the QML/Silica counterpart of iOS
// Builtins.swift and Android Builtins.kt. Maps a contract node to Silica QML via
// a Loader (Qt 5.6 has no DelegateChooser), recursing through Repeater.
//
// This node wrapper applies the shared modifier surface (size / background /
// cornerRadius / shadow / padding / onTap / pulse) around whatever the type
// renders, so cards, rails and the premium home all render like iOS/Android.
// Unsupported types degrade to a visible marker, never a crash. Qt 5.6 / ES5.
import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import "Tokens.js" as T

Item {
    id: root

    property var node          // parsed contract node
    property var ctx           // { tokens, state, data, env, item, dispatch }

    // ---------- modifier access ----------
    function _m() { return (root.node && root.node.modifiers) ? root.node.modifiers : null }
    function _sizeSpec(axis) { var m = _m(); var s = m ? m.size : null; return s ? s[axis] : null }
    function _fixed(axis) { var s = _sizeSpec(axis); return (s && s.mode === "fixed" && s.value !== undefined) ? s.value : -1 }
    function _isFill(axis) { var s = _sizeSpec(axis); return !!(s && s.mode === "fill") }
    function _padEdge(edge) {
        var m = _m(); if (!m || m.padding === undefined) return 0;
        var p = m.padding;
        if (p !== null && typeof p === "object") {
            var v = p[edge];
            if (v === undefined && edge === "left")  v = (p.leading !== undefined ? p.leading : p.horizontal);
            if (v === undefined && edge === "right") v = (p.trailing !== undefined ? p.trailing : p.horizontal);
            if (v === undefined && (edge === "top" || edge === "bottom")) v = p.vertical;
            return T.num(v, root.ctx, 0);
        }
        return T.num(p, root.ctx, 0);
    }
    function _tapAction() {
        if (root.node && root.node.onTap) return root.node.onTap;
        var m = _m(); if (m && m.onTap) return m.onTap;
        return null;
    }
    function _dispatch(a) { if (a && root.ctx && root.ctx.dispatch) root.ctx.dispatch(a); }

    property real _padL: _padEdge("left")
    property real _padR: _padEdge("right")
    property real _padT: _padEdge("top")
    property real _padB: _padEdge("bottom")
    property real _fixedW: _fixed("width")
    property real _fixedH: _fixed("height")
    property bool _fillW: _isFill("width")

    implicitWidth: (loader.item ? loader.item.implicitWidth : 0) + _padL + _padR
    implicitHeight: (loader.item ? loader.item.implicitHeight : 0) + _padT + _padB
    width: _fixedW >= 0 ? _fixedW : (_fillW && parent ? parent.width : implicitWidth)
    height: _fixedH >= 0 ? _fixedH : implicitHeight

    // gentle "breathe" (Instagram live-ring) when a pulse modifier is present
    SequentialAnimation on scale {
        running: root._m() !== null && root._m().pulse !== undefined
        loops: Animation.Infinite
        NumberAnimation { to: 1.06; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
    }

    // ---------- background + soft shadow ----------
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: T.num(root._m() ? root._m().cornerRadius : undefined, root.ctx, 0)
        property string bgc: T.color(root._m() ? root._m().background : undefined, root.ctx, "")
        color: bgc.length ? bgc : "transparent"
        visible: bgc.length > 0
    }
    DropShadow {
        anchors.fill: bg
        source: bg
        visible: bg.visible && root._m() !== null && root._m().shadow !== undefined
        radius: 18; samples: 25
        horizontalOffset: 0; verticalOffset: 6
        color: "#26000000"; transparentBorder: true
    }

    // ---------- content (inset by padding) ----------
    Loader {
        id: loader
        anchors.fill: parent
        anchors.leftMargin: root._padL; anchors.rightMargin: root._padR
        anchors.topMargin: root._padT; anchors.bottomMargin: root._padB
        sourceComponent: root.pick(root.node ? root.node.type : "")
        onLoaded: { if (item) { item.node = root.node; item.ctx = root.ctx } }
    }

    // ---------- whole-node tap ----------
    MouseArea {
        anchors.fill: parent
        enabled: root._tapAction() !== null
        onClicked: root._dispatch(root._tapAction())
    }

    function pick(type) {
        switch (type) {
        case "vstack":    return cColumn
        case "hstack":    return cRow
        case "zstack":    return cStack
        case "scroll":    return cScroll
        case "grid":      return cGrid
        case "text":      return cText
        case "button":    return cButton
        case "image":     return cImage
        case "icon":      return cIcon
        case "gradient":  return cGradient
        case "divider":   return cDivider
        case "spacer":    return cSpacer
        case "toggle":    return cToggle
        case "textfield": return cField
        case "list":       return cList
        case "chart":      return cChart
        case "progress":   return cProgress
        case "spinner":    return cSpinner
        case "slider":     return cSlider
        case "rings":      return cRings
        case "ticker":     return cTicker
        case "disclosure": return cDisclosure
        default:          return cUnknown
        }
    }

    // ===================== containers =====================
    Component {
        id: cColumn
        Column {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            spacing: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            property string align: node && node.alignment ? node.alignment : "leading"
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiRenderer {
                    node: modelData; ctx: parent.ctx
                    width: parent.align === "center" || parent.align === "trailing" ? implicitWidth : parent.width
                    anchors.horizontalCenter: parent.align === "center" ? parent.horizontalCenter : undefined
                    anchors.right: parent.align === "trailing" ? parent.right : undefined
                }
            }
        }
    }
    Component {
        id: cRow
        Row {
            property var node
            property var ctx
            spacing: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiRenderer { node: modelData; ctx: parent.ctx }
            }
        }
    }
    Component {
        id: cStack
        Item {
            property var node
            property var ctx
            property string align: node && node.alignment ? node.alignment : "center"
            width: parent ? parent.width : implicitWidth
            implicitHeight: childrenRect.height
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiRenderer {
                    node: modelData; ctx: parent.ctx
                    // Overlay each child at the stack's alignment corner.
                    anchors.left:   parent.align.indexOf("Leading") >= 0 || parent.align === "leading" || parent.align === "top" || parent.align === "bottom" || parent.align === "center" ? parent.left : undefined
                    anchors.right:  parent.align.indexOf("Trailing") >= 0 || parent.align === "trailing" ? parent.right : undefined
                    anchors.top:    parent.align.indexOf("top") === 0 || parent.align === "topLeading" || parent.align === "topTrailing" ? parent.top : undefined
                    anchors.bottom: parent.align.indexOf("bottom") === 0 || parent.align === "bottomLeading" || parent.align === "bottomTrailing" ? parent.bottom : undefined
                    anchors.horizontalCenter: parent.align === "center" || parent.align === "top" || parent.align === "bottom" ? parent.horizontalCenter : undefined
                    anchors.verticalCenter: parent.align === "center" || parent.align === "leading" || parent.align === "trailing" ? parent.verticalCenter : undefined
                }
            }
        }
    }
    Component {
        id: cScroll
        Loader {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            sourceComponent: (node && node.axis === "horizontal") ? cHScroll : cVPass
        }
    }
    // Horizontal rail: a Flickable wrapping the child hstack.
    Component {
        id: cHScroll
        Flickable {
            property var node: parent.node
            property var ctx: parent.ctx
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            height: inner.height
            contentWidth: inner.width
            contentHeight: inner.height
            SduiRenderer { id: inner; node: parent.node ? parent.node.child : null; ctx: parent.ctx }
        }
    }
    // Vertical scroll is a pass-through (the page already provides the scroll surface).
    Component {
        id: cVPass
        Column {
            property var node: parent.node
            property var ctx: parent.ctx
            width: parent ? parent.width : implicitWidth
            SduiRenderer { width: parent.width; node: parent.node ? parent.node.child : null; ctx: parent.ctx }
        }
    }
    Component {
        id: cGrid
        Column {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            property int cols: node && node.columns ? node.columns : 2
            property real gap: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            property var kids: node && node.children ? node.children : []
            spacing: gap
            Repeater {
                model: Math.ceil(kids.length / cols)
                delegate: Row {
                    property int rowIx: index
                    width: parent.width
                    spacing: parent.gap
                    Repeater {
                        model: parent.parent.cols
                        delegate: Item {
                            property int cellIx: parent.parent.rowIx * parent.parent.parent.cols + index
                            width: (parent.parent.width - parent.parent.parent.gap * (parent.parent.parent.cols - 1)) / parent.parent.parent.cols
                            height: childrenRect.height
                            SduiRenderer {
                                width: parent.width
                                node: cellIx < kids.length ? kids[cellIx] : null
                                ctx: root2ctx
                                property var root2ctx: parent.parent.parent.parent.ctx
                                visible: cellIx < kids.length
                            }
                        }
                    }
                }
            }
        }
    }

    // ===================== leaves =====================
    Component {
        id: cText
        Label {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            wrapMode: Text.Wrap
            horizontalAlignment: node && node.alignment === "center" ? Text.AlignHCenter
                : node && node.alignment === "trailing" ? Text.AlignRight : Text.AlignLeft
            text: node ? T.str(node.value, ctx) : ""
            font.pixelSize: node ? T.fontSize(node.style) : Theme.fontSizeMedium
            color: node ? T.color(node.color, ctx, Theme.primaryColor) : Theme.primaryColor
        }
    }
    Component {
        id: cButton
        Button {
            property var node
            property var ctx
            text: node ? T.str(node.title, ctx) : ""
            onClicked: { if (node && node.onTap && ctx && ctx.dispatch) ctx.dispatch(node.onTap) }
        }
    }
    Component {
        id: cImage
        Image {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            fillMode: Image.PreserveAspectCrop
            clip: true
            source: node ? T.str(node.source, ctx) : ""
        }
    }
    Component {
        id: cIcon
        Label {
            property var node
            property var ctx
            text: node ? T.str(node.name, ctx) : ""
            color: node ? T.color(node.color, ctx, Theme.highlightColor) : Theme.highlightColor
        }
    }
    // Gradient fill (diagonal/horizontal/vertical), rounded via an opacity mask.
    Component {
        id: cGradient
        Item {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            height: parent ? parent.height : implicitHeight
            property var cols: node && node.colors ? node.colors : ["#888888", "#444444"]
            property string dir: node && node.direction ? node.direction : "vertical"
            property real rad: T.num(node && node.modifiers ? node.modifiers.cornerRadius : undefined, ctx, 0)
            LinearGradient {
                id: grad
                anchors.fill: parent
                visible: false
                start: Qt.point(0, 0)
                end: parent.dir === "horizontal" ? Qt.point(width, 0)
                    : parent.dir === "diagonal" ? Qt.point(width, height) : Qt.point(0, height)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: cols[0] ? cols[0] : "#888888" }
                    GradientStop { position: cols.length >= 3 ? 0.5 : 1.0; color: cols[1] ? cols[1] : "#444444" }
                    GradientStop { position: 1.0; color: cols[2] ? cols[2] : (cols[1] ? cols[1] : "#444444") }
                }
            }
            Rectangle { id: gmask; anchors.fill: parent; radius: parent.rad; visible: false }
            OpacityMask { anchors.fill: parent; source: grad; maskSource: gmask }
        }
    }
    Component {
        id: cDivider
        Separator {
            property var node
            property var ctx
            width: parent ? parent.width : 0
            horizontalAlignment: Qt.AlignHCenter
            color: node ? T.color(node.color, ctx, Theme.secondaryColor) : Theme.secondaryColor
        }
    }
    Component {
        id: cSpacer
        Item {
            property var node
            property var ctx
            width: 1
            height: T.num(node && node.minLength, ctx, Theme.paddingLarge)
        }
    }
    Component {
        id: cToggle
        TextSwitch {
            property var node
            property var ctx
            text: node ? T.str(node.title, ctx) : ""
        }
    }
    Component {
        id: cField
        TextField {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            label: node ? T.str(node.label, ctx) : ""
            placeholderText: node ? T.str(node.placeholder, ctx) : ""
        }
    }
    // ===================== data + feedback =====================

    // list — rows from a `template` repeated over an `items` array (each element
    // exposed as `$item`), or from inline `children`; an `empty` slot shows when
    // there are no rows. Faithful to iOS ListView's core (Builtins.swift:873).
    // The page already owns the scroll surface (ScreenPage's SilicaFlickable), so
    // rows flow in a Column+Repeater rather than a nested SilicaListView — nesting
    // two vertical scrollers is the Silica anti-pattern the pass-through avoids.
    Component {
        id: cList
        Column {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            spacing: T.num(node && node.spacing, ctx, Theme.paddingSmall)

            // Resolve `items` (inline array or a "$…" binding to one) to an array.
            function _items() {
                if (!node || node.items === undefined || node.items === null) return null;
                var r = (typeof node.items === "string") ? T.resolve(node.items, ctx) : node.items;
                return (Object.prototype.toString.call(r) === "[object Array]") ? r : [];
            }
            // A per-row render context: a shallow clone of ctx with `item` set, so
            // "$item.title" resolves inside the template (matches ctx.with(item:)).
            function _rowCtx(el) {
                var c = {};
                for (var k in ctx) c[k] = ctx[k];
                c.item = el;
                return c;
            }
            property var _rows: _items()
            property bool _templated: node && node.items !== undefined && node.template !== undefined

            // Templated rows.
            Repeater {
                model: parent._templated && parent._rows ? parent._rows : []
                delegate: SduiRenderer {
                    width: parent.width
                    node: parent.node.template
                    ctx: parent._rowCtx(modelData)
                }
            }
            // Empty slot — shown when a templated list resolves to zero rows.
            // (An invisible child is excluded from Column layout, so this adds no
            // gap when there ARE rows.)
            SduiRenderer {
                width: parent.width
                visible: parent._templated && parent._rows !== null && parent._rows.length === 0
                         && parent.node && parent.node.empty !== undefined
                node: (parent.node && parent.node.empty !== undefined) ? parent.node.empty : null
                ctx: parent.ctx
            }
            // Inline children (non-templated list).
            Repeater {
                model: !parent._templated && parent.node && parent.node.children ? parent.node.children : []
                delegate: SduiRenderer { width: parent.width; node: modelData; ctx: parent.ctx }
            }
        }
    }

    // chart — line / area / bar drawn on a Canvas from `values` (x = index) or
    // `points` [{x,y}], with premium Apple-Stocks-style scrubbing: press and drag
    // to reveal a crosshair, a target dot and a floating value pill. Faithful to
    // iOS SDUIChartView (ChartView.swift). ES5 only; the 2D context is `g` so it
    // never shadows the SDUI render `ctx`.
    Component {
        id: cChart
        Item {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: 180
            height: parent ? parent.height : implicitHeight

            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            property string style: (node && node.style) ? node.style : "line"
            property bool showAxes: !!(node && node.axes)
            property bool interactive: (node && node.interactive !== undefined) ? !!node.interactive : true
            property string unit: (node && node.unit) ? String(node.unit) : ""
            property int sel: -1

            // Resolve the data into a flat [{x,y}] list (points OR values-by-index).
            function _points() {
                var raw, arr, out = [], i;
                if (node && node.points !== undefined) {
                    raw = (typeof node.points === "string") ? T.resolve(node.points, ctx) : node.points;
                    arr = (Object.prototype.toString.call(raw) === "[object Array]") ? raw : [];
                    for (i = 0; i < arr.length; i++) {
                        var it = arr[i] || {};
                        out.push({ x: (it.x !== undefined ? Number(it.x) : i), y: Number(it.y) || 0 });
                    }
                    return out;
                }
                if (node && node.values !== undefined) {
                    raw = (typeof node.values === "string") ? T.resolve(node.values, ctx) : node.values;
                    arr = (Object.prototype.toString.call(raw) === "[object Array]") ? raw : [];
                    for (i = 0; i < arr.length; i++) out.push({ x: i, y: Number(arr[i]) || 0 });
                }
                return out;
            }
            property var pts: _points()
            onPtsChanged: canvas.requestPaint()
            onTintChanged: canvas.requestPaint()
            onSelChanged: canvas.requestPaint()

            function _fmt(v) {
                if (v === Math.round(v) && Math.abs(v) < 100000) return String(Math.round(v));
                return v.toFixed(2);
            }

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var g = getContext("2d");
                    g.clearRect(0, 0, width, height);
                    var p = parent.pts;
                    if (!p || p.length === 0) return;

                    var padL = parent.showAxes ? 30 : 6;
                    var padR = 8, padT = 12;
                    var padB = parent.showAxes ? 20 : 8;
                    var plotW = Math.max(1, width - padL - padR);
                    var plotH = Math.max(1, height - padT - padB);
                    var isBar = parent.style === "bar";

                    var i, xs = [], ys = [];
                    for (i = 0; i < p.length; i++) { xs.push(p[i].x); ys.push(p[i].y); }
                    var xMin = Math.min.apply(null, xs), xMax = Math.max.apply(null, xs);
                    var xPad = isBar ? 0.6 : 0;
                    xMin -= xPad; xMax += xPad;
                    var yLo = Math.min.apply(null, ys), yHi = Math.max.apply(null, ys);
                    if (isBar) { yLo = 0; yHi = yHi * 1.28 + 0.0001; }
                    else { var yp = (yHi - yLo) * 0.16 + 0.0001; yLo -= yp; yHi += yp; }

                    function xPix(x) { return xMax === xMin ? padL + plotW / 2 : padL + (x - xMin) / (xMax - xMin) * plotW; }
                    function yPix(y) { return yHi === yLo ? padT + plotH / 2 : padT + (1 - (y - yLo) / (yHi - yLo)) * plotH; }

                    // Optional light axes (baseline + left rule).
                    if (parent.showAxes) {
                        g.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.25);
                        g.lineWidth = 1;
                        g.beginPath();
                        g.moveTo(padL, padT); g.lineTo(padL, padT + plotH);
                        g.lineTo(padL + plotW, padT + plotH);
                        g.stroke();
                    }

                    if (isBar) {
                        var bw = Math.min(20, plotW / p.length * 0.6);
                        var baseY = yPix(0);
                        for (i = 0; i < p.length; i++) {
                            var bx = xPix(p[i].x) - bw / 2;
                            var by = yPix(p[i].y);
                            var bh = baseY - by;
                            var r = Math.min(6, bw / 2);
                            g.globalAlpha = (parent.sel === i) ? 1.0 : 0.9;
                            g.fillStyle = parent.tint;
                            // Rounded-top bar path.
                            g.beginPath();
                            g.moveTo(bx, baseY);
                            g.lineTo(bx, by + r);
                            g.quadraticCurveTo(bx, by, bx + r, by);
                            g.lineTo(bx + bw - r, by);
                            g.quadraticCurveTo(bx + bw, by, bx + bw, by + r);
                            g.lineTo(bx + bw, baseY);
                            g.closePath();
                            g.fill();
                        }
                        g.globalAlpha = 1.0;
                    } else {
                        // Smooth curve through the points (midpoint quadratics).
                        function tracePath() {
                            g.beginPath();
                            g.moveTo(xPix(p[0].x), yPix(p[0].y));
                            for (var k = 1; k < p.length; k++) {
                                var xc = (xPix(p[k - 1].x) + xPix(p[k].x)) / 2;
                                var yc = (yPix(p[k - 1].y) + yPix(p[k].y)) / 2;
                                g.quadraticCurveTo(xPix(p[k - 1].x), yPix(p[k - 1].y), xc, yc);
                            }
                            g.lineTo(xPix(p[p.length - 1].x), yPix(p[p.length - 1].y));
                        }
                        if (parent.style === "area") {
                            tracePath();
                            g.lineTo(xPix(p[p.length - 1].x), padT + plotH);
                            g.lineTo(xPix(p[0].x), padT + plotH);
                            g.closePath();
                            g.globalAlpha = 0.18; g.fillStyle = parent.tint; g.fill();
                            g.globalAlpha = 1.0;
                        }
                        tracePath();
                        g.strokeStyle = parent.tint; g.lineWidth = 2.5;
                        g.lineJoin = "round"; g.lineCap = "round";
                        g.stroke();
                    }

                    // Scrub crosshair + read-out pill for the selected point.
                    if (parent.sel >= 0 && parent.sel < p.length) {
                        var sx = xPix(p[parent.sel].x), sy = yPix(p[parent.sel].y);
                        // Dashed vertical rule.
                        g.globalAlpha = 0.35; g.strokeStyle = parent.tint; g.lineWidth = 1;
                        if (g.setLineDash) g.setLineDash([3, 3]);
                        g.beginPath(); g.moveTo(sx, padT); g.lineTo(sx, padT + plotH); g.stroke();
                        if (g.setLineDash) g.setLineDash([]);
                        g.globalAlpha = 1.0;
                        // Target dot: glow + solid ring + white centre.
                        g.globalAlpha = 0.18; g.fillStyle = parent.tint;
                        g.beginPath(); g.arc(sx, sy, 11, 0, Math.PI * 2); g.fill();
                        g.globalAlpha = 1.0; g.fillStyle = parent.tint;
                        g.beginPath(); g.arc(sx, sy, 6, 0, Math.PI * 2); g.fill();
                        g.fillStyle = "#ffffff";
                        g.beginPath(); g.arc(sx, sy, 3, 0, Math.PI * 2); g.fill();
                        // Floating value pill (flips below when the point sits high).
                        var txt = parent.unit + parent._fmt(p[parent.sel].y);
                        g.font = "600 13px sans-serif";
                        var tw = g.measureText(txt).width;
                        var pw = tw + 16, ph = 22;
                        var px = Math.max(padL, Math.min(sx - pw / 2, padL + plotW - pw));
                        var high = (sy - padT) < plotH * 0.28;
                        var py = high ? sy + 14 : sy - ph - 14;
                        g.fillStyle = Qt.rgba(0.5, 0.5, 0.5, 0.22);
                        g.fillRect(px, py, pw, ph);
                        g.globalAlpha = 0.4; g.strokeStyle = parent.tint; g.lineWidth = 1;
                        g.strokeRect(px, py, pw, ph); g.globalAlpha = 1.0;
                        g.fillStyle = Theme.primaryColor;
                        g.textBaseline = "middle"; g.textAlign = "left";
                        g.fillText(txt, px + 8, py + ph / 2);
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: parent.interactive
                preventStealing: true
                function _selectAt(mx) {
                    var p = parent.pts;
                    if (!p || p.length === 0) return;
                    var padL = parent.showAxes ? 30 : 6, padR = 8;
                    var plotW = Math.max(1, width - padL - padR);
                    var xs = [], i;
                    for (i = 0; i < p.length; i++) xs.push(p[i].x);
                    var xMin = Math.min.apply(null, xs), xMax = Math.max.apply(null, xs);
                    if (parent.style === "bar") { xMin -= 0.6; xMax += 0.6; }
                    var best = -1, bestD = 1e9;
                    for (i = 0; i < p.length; i++) {
                        var px = xMax === xMin ? padL + plotW / 2 : padL + (p[i].x - xMin) / (xMax - xMin) * plotW;
                        var d = Math.abs(px - mx);
                        if (d < bestD) { bestD = d; best = i; }
                    }
                    parent.sel = best;
                }
                onPressed: _selectAt(mouse.x)
                onPositionChanged: _selectAt(mouse.x)
                onReleased: parent.sel = -1
                onCanceled: parent.sel = -1
            }
        }
    }

    // progress — determinate capsule (gradient fill, spring-eased width) or, when
    // `value` is absent/unresolvable, an indeterminate sweeping shimmer. Faithful
    // to iOS ProgressBarView (Builtins.swift:1900).
    Component {
        id: cProgress
        Item {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            property real h: T.num(node && node.height, ctx, 6)
            implicitHeight: h
            height: h
            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            // -1 sentinel = indeterminate (no value / non-numeric binding).
            function _val() {
                if (!node || node.value === undefined || node.value === null) return -1;
                var v = T.num(node.value, ctx, NaN);
                if (isNaN(v)) return -1;
                return Math.max(0, Math.min(1, v));
            }
            property real val: _val()
            property bool indeterminate: val < 0

            Rectangle {  // track
                id: ptrack
                anchors.fill: parent
                radius: height / 2
                color: parent.tint
                opacity: 0.16
            }
            Item {  // clip region for the fill
                anchors.fill: parent
                clip: true
                Rectangle {
                    id: pfill
                    height: parent.height
                    radius: height / 2
                    visible: !parent.parent.indeterminate
                    width: parent.parent.indeterminate ? 0 : parent.parent.val * parent.width
                    color: parent.parent.tint
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                }
                Rectangle {  // indeterminate sweep
                    id: psweep
                    visible: parent.parent.indeterminate
                    height: parent.height
                    radius: height / 2
                    width: parent.width * 0.4
                    color: parent.parent.tint
                    x: parent.parent.indeterminate ? 0 : 0
                    SequentialAnimation on x {
                        running: parent.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: -psweep.width; to: psweep.parent.width; duration: 1100; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }

    // spinner — Silica's native, ambience-aware BusyIndicator. `scale` grows or
    // shrinks it. Faithful to iOS SpinnerView (Async.swift:8). NOTE: Silica's
    // BusyIndicator tints from the active ambience highlight, so the `color` prop
    // is honoured approximately (a ColorOverlay is layered when a custom colour is
    // supplied to keep parity with the iOS `tint`).
    Component {
        id: cSpinner
        Item {
            property var node
            property var ctx
            property real sc: T.num(node && node.scale, ctx, 1)
            property string tint: node && node.color ? T.color(node.color, ctx, "") : ""
            implicitWidth: busy.width * sc
            implicitHeight: busy.height * sc
            BusyIndicator {
                id: busy
                anchors.centerIn: parent
                running: true
                size: BusyIndicatorSize.Medium
                scale: parent.sc
            }
            ColorOverlay {
                anchors.fill: busy
                source: busy
                scale: parent.sc
                visible: parent.tint.length > 0
                color: parent.tint.length > 0 ? parent.tint : "transparent"
            }
        }
    }

    // slider — a native drag capsule that reads AND writes a 0…1 `$state` value
    // through the host hooks (ctx.setState), so it stays in sync with a `ticker`
    // or any label bound to the same key. Honours `color`, `height`, `thumb`.
    // Faithful to iOS SliderView (Builtins.swift:1647). A Silica Slider can't
    // carry an arbitrary track colour/height/thumb toggle, so the same native
    // MouseArea-drag mechanism iOS uses is used here to honour the full contract.
    Component {
        id: cSlider
        Item {
            id: sroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            property real trackH: T.num(node && node.height, ctx, 6)
            property bool thumb: (node && node.thumb !== undefined) ? !!node.thumb : true
            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            property string bindKey: (node && node.bind) ? node.bind : ""
            property real thumbD: trackH + 12
            property real val: node ? Math.max(0, Math.min(1, T.num(node.bind, ctx, 0))) : 0
            implicitHeight: Math.max(trackH, thumbD)
            height: implicitHeight

            function _write(px) {
                var w = sroot.width - (sroot.thumb ? sroot.thumbD : 0);
                var base = sroot.thumb ? sroot.thumbD / 2 : 0;
                var v = w > 0 ? (px - base) / w : 0;
                v = Math.max(0, Math.min(1, v));
                if (sroot.bindKey && sroot.ctx && sroot.ctx.setState) sroot.ctx.setState(sroot.bindKey, v);
            }

            Rectangle {  // track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: parent.trackH
                radius: height / 2
                color: parent.tint; opacity: 0.22
            }
            Rectangle {  // fill
                anchors.verticalCenter: parent.verticalCenter
                height: parent.trackH; radius: height / 2
                width: Math.max(0, parent.val * parent.width)
                color: parent.tint
            }
            Rectangle {  // thumb
                visible: parent.thumb
                width: parent.thumbD; height: parent.thumbD; radius: width / 2
                color: "white"
                border.color: Qt.rgba(0, 0, 0, 0.12); border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(Math.max(parent.val * (parent.width - parent.thumbD), 0), parent.width - parent.thumbD)
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                onPressed: sroot._write(mouse.x)
                onPositionChanged: sroot._write(mouse.x)
            }
        }
    }

    // rings — Apple-Fitness activity rings drawn on a Canvas: concentric trimmed
    // arcs (outermost first), each a faint full track under a bright progress arc
    // with round caps, starting at 12 o'clock. Faithful to iOS RingsView
    // (Builtins.swift:77). ES5; 2D context is `g`.
    Component {
        id: cRings
        Item {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: 220
            height: parent ? parent.height : implicitHeight
            property real lineW: T.num(node && node.lineWidth, ctx, 16)
            property real gap: T.num(node && node.gap, ctx, 6)
            function _vals() {
                var raw = (node && node.values !== undefined)
                    ? ((typeof node.values === "string") ? T.resolve(node.values, ctx) : node.values) : [];
                return (Object.prototype.toString.call(raw) === "[object Array]") ? raw : [];
            }
            property var vals: _vals()
            property var cols: (node && node.colors && Object.prototype.toString.call(node.colors) === "[object Array]") ? node.colors : []
            onValsChanged: rcanvas.requestPaint()

            Canvas {
                id: rcanvas
                anchors.fill: parent
                antialiasing: true
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var g = getContext("2d");
                    g.clearRect(0, 0, width, height);
                    var v = parent.vals;
                    if (!v || v.length === 0) return;
                    var lw = parent.lineW, gp = parent.gap;
                    var side = Math.min(width, height) - lw;
                    var cx = width / 2, cy = height / 2;
                    var i;
                    for (i = 0; i < v.length; i++) {
                        var col = (i < parent.cols.length) ? T.color(parent.cols[i], parent.ctx, Theme.highlightColor) : Theme.highlightColor;
                        var inset = i * (lw + gp);
                        var radius = (side - inset * 2) / 2;
                        if (radius <= 0) continue;
                        var prog = Math.max(0, Math.min(1, Number(v[i]) || 0));
                        // Faint full-circle track.
                        g.globalAlpha = 0.18; g.strokeStyle = col; g.lineWidth = lw; g.lineCap = "round";
                        g.beginPath(); g.arc(cx, cy, radius, 0, Math.PI * 2); g.stroke();
                        // Bright progress arc, from 12 o'clock (-90deg) clockwise.
                        g.globalAlpha = 1.0;
                        if (prog > 0) {
                            g.beginPath();
                            g.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + prog * Math.PI * 2, false);
                            g.stroke();
                        }
                    }
                    g.globalAlpha = 1.0;
                }
            }
        }
    }

    // ticker — an invisible heartbeat that advances a numeric `$state` value by
    // `step` every `interval` seconds (capped at `max`, `loop`ing to 0), but only
    // while the `while` bool-state key is true. Writes through the same host hook
    // the slider reads, so they stay in sync. Faithful to iOS TickerView
    // (Ticker.swift). ES5.
    Component {
        id: cTicker
        Item {
            id: troot
            property var node
            property var ctx
            width: 0; height: 0
            property string bindKey: (node && node.bind) ? node.bind : ""
            property real interval: Math.max(0.05, T.num(node && node.interval, ctx, 1))
            property real step: T.num(node && node.step, ctx, 0.01)
            property real maxV: T.num(node && node.max, ctx, 1)
            property bool loop: !!(node && node.loop)
            function _running() {
                if (!node || node["while"] === undefined || node["while"] === null) return true;
                var w = T.resolve(node["while"], ctx);
                return w === true || w === "true" || w === 1 || w === "1";
            }
            Timer {
                interval: troot.interval * 1000
                repeat: true
                running: troot.bindKey.length > 0 && troot._running()
                onTriggered: {
                    if (!troot.ctx || !troot.ctx.getState || !troot.ctx.setState) return;
                    var cur = Number(troot.ctx.getState(troot.bindKey));
                    if (isNaN(cur)) cur = 0;
                    var next = cur + troot.step;
                    if (next >= troot.maxV) next = troot.loop ? 0 : troot.maxV;
                    troot.ctx.setState(troot.bindKey, next);
                }
            }
        }
    }

    // disclosure — a self-contained collapsible section: a tappable header (icon
    // chip, title, subtitle, rotating chevron) that reveals its `children` with a
    // spring. Faithful to iOS DisclosureView (Disclosure.swift). The open/closed
    // state lives here (seeded from `expanded`), so no $state wiring is needed.
    // NOTE: Aurora has no SF-Symbol set, so `icon` renders as its glyph/text (as
    // the icon primitive does) inside the accent chip.
    Component {
        id: cDisclosure
        Rectangle {
            id: droot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: col.implicitHeight
            height: implicitHeight
            radius: 16
            color: Qt.rgba(0.5, 0.5, 0.5, 0.10)
            clip: true
            // Accordion reveal: the card's height animates and the clip unveils
            // the body top-down (matches the iOS DisclosureView note).
            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            property bool expanded: !!(node && node.expanded)
            property string accent: T.color(node && node.accent, ctx, Theme.highlightColor)
            property string title: node ? T.str(node.title, ctx) : ""
            property string subtitle: node ? T.str(node.subtitle, ctx) : ""
            property string icon: node && node.icon ? T.str(node.icon, ctx) : ""

            Column {
                id: col
                width: parent.width

                // Header row.
                MouseArea {
                    width: parent.width
                    height: hrow.implicitHeight + Theme.paddingLarge
                    onClicked: droot.expanded = !droot.expanded
                    Row {
                        id: hrow
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.paddingLarge
                        width: parent.width - Theme.paddingLarge * 2
                        spacing: Theme.paddingMedium

                        Rectangle {
                            visible: droot.icon.length > 0
                            width: 34; height: 34; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            color: droot.accent; opacity: 0.14
                            Label {
                                anchors.centerIn: parent
                                text: droot.icon
                                color: droot.accent
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (droot.icon.length > 0 ? 34 + Theme.paddingMedium : 0) - chev.width - Theme.paddingMedium
                            spacing: 2
                            Label {
                                width: parent.width
                                text: droot.title
                                font.pixelSize: Theme.fontSizeMedium
                                font.bold: true
                                color: Theme.primaryColor
                                wrapMode: Text.Wrap
                            }
                            Label {
                                width: parent.width
                                visible: droot.subtitle.length > 0
                                text: droot.subtitle
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryColor
                                wrapMode: Text.Wrap
                            }
                        }
                        Label {
                            id: chev
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▼"  // ▼ chevron
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            rotation: droot.expanded ? 0 : -90
                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        }
                    }
                }

                // Body — divider + children, revealed while expanded.
                Column {
                    id: body
                    width: parent.width
                    visible: droot.expanded
                    opacity: droot.expanded ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Separator {
                        width: parent.width - Theme.paddingLarge * 2
                        x: Theme.paddingLarge
                        color: Theme.secondaryColor
                        horizontalAlignment: Qt.AlignHCenter
                    }
                    Item { width: 1; height: Theme.paddingMedium }
                    Repeater {
                        model: (droot.node && droot.node.children) ? droot.node.children : []
                        delegate: SduiRenderer {
                            width: body.width - Theme.paddingLarge * 2
                            x: Theme.paddingLarge
                            node: modelData
                            ctx: droot.ctx
                        }
                    }
                    Item { width: 1; height: Theme.paddingMedium }
                }
            }
        }
    }

    Component {
        id: cUnknown
        Label {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: "#C0392B"
            text: node ? ("[unsupported: " + node.type + "]") : ""
        }
    }
}
