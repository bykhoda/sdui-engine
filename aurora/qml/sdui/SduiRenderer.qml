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
    property bool _fillW: _isFill("width") || _hasSpacerChild("hstack")
    property bool _fillH: _isFill("height") || _hasSpacerChild("vstack")

    function _hasSpacerChild(axisType) {
        var n = root.node;
        if (!n || n.type !== axisType || !n.children) return false;
        for (var i = 0; i < n.children.length; i++)
            if (n.children[i] && n.children[i].type === "spacer") return true;
        return false;
    }

    // A `visibleWhen` condition gates the whole node (iOS/Android ComponentRegistry skip a node
    // whose condition is false). When hidden we render nothing AND take no layout space, so
    // positioners exclude it — this is what de-duplicates the selected/unselected chip pairs
    // (each gated by equals/notEquals on $state) that otherwise both drew ("All All").
    property bool _visible: !root.node || root.node.visibleWhen === undefined || root.node.visibleWhen === null
                            || T.evalCondition(root.node.visibleWhen, root.ctx)
    visible: _visible

    // Intrinsic size must reflect the RESOLVED size — a fixed size (modifiers.size) is the
    // node's intrinsic size, exactly like a SwiftUI .frame(width:height:) / Compose
    // Modifier.size. Folding it in here (not only into `width`/`height`) is what lets a parent
    // that measures children by their IMPLICIT size — a zstack (cStack), a rail's content
    // hstack — see fixed-size circles/cards instead of collapsing to zero.
    implicitWidth: _fixedW >= 0 ? _fixedW : ((loader.item ? loader.item.implicitWidth : 0) + _padL + _padR)
    implicitHeight: _fixedH >= 0 ? _fixedH : ((loader.item ? loader.item.implicitHeight : 0) + _padT + _padB)
    width: _fixedW >= 0 ? _fixedW : (_fillW && parent ? parent.width : implicitWidth)
    height: _fixedH >= 0 ? _fixedH : (_fillH && parent ? parent.height : implicitHeight)

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
        // Honor modifiers.opacity, and CLIP the content to the node's cornerRadius so
        // edge-to-edge children (images, inner gradients) round with the card instead of
        // bleeding square corners past it — the iOS `.clipShape`/Android `.clip(shape)` twin.
        opacity: T.num(root._m() ? root._m().opacity : undefined, root.ctx, 1)
        layer.enabled: bg.radius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: loader.width; height: loader.height; radius: bg.radius }
        }
        sourceComponent: root._visible ? root.pick(root.node ? root.node.type : "") : null
        // Bind (not assign) so node/ctx keep tracking `root` — the recursion shim
        // (SduiChild) sets root.node/ctx a tick after this Loader instantiates, and static
        // assignment would freeze the children at the initial `undefined`.
        onLoaded: {
            if (item) {
                item.node = Qt.binding(function () { return root.node })
                item.ctx = Qt.binding(function () { return root.ctx })
            }
        }
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
        case "hstack":    return _hasSpacerChild("hstack") ? cRowSplit : cRowPlain
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
        case "async":      return cAsync
        case "calendar":   return cCalendar
        case "clips":      return cClips
        case "datepicker": return cDatePicker
        case "filecell":   return cFileCell
        case "pager":      return cPager
        case "picker":     return cPicker
        case "roadmap":    return cRoadmap
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
                delegate: SduiChild {
                    node: modelData; ctx: parent.ctx
                    width: parent.align === "center" || parent.align === "trailing" ? implicitWidth : parent.width
                    anchors.horizontalCenter: parent.align === "center" ? parent.horizontalCenter : undefined
                    anchors.right: parent.align === "trailing" ? parent.right : undefined
                }
            }
        }
    }
    // hstack without a spacer — a plain hugging Row (also the safe path for a fill/weight child,
    // which Qt sizes against the loader-provided width). pick() routes here unless a spacer is present.
    Component {
        id: cRowPlain
        Row {
            property var node
            property var ctx
            spacing: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiChild { node: modelData; ctx: parent.ctx }
            }
        }
    }

    // hstack WITH a spacer — split at the first spacer into a leading group (anchored left) and a
    // trailing group (anchored right) in a full-width Item, so the spacer separates them to opposite
    // edges (SwiftUI Spacer / Compose weight) — deterministic anchors, no leftover maths. The
    // SduiRenderer reports fill-width when a spacer is present (so this Item is handed the full width),
    // so `rr` binds NO width/height — that would double-write against the loader. Only reached for
    // spacer rows, which don't mix a spacer with a fill child (that would be a contradictory layout),
    // so a fill child never lands in one of these hugging anchored rows.
    Component {
        id: cRowSplit
        Item {
            id: rr
            property var node
            property var ctx
            property real gap: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            property string valign: (node && node.alignment) ? node.alignment : "center"
            function _spacerIdx() {
                var ks = (node && node.children) ? node.children : [];
                for (var i = 0; i < ks.length; i++) if (ks[i] && ks[i].type === "spacer") return i;
                return -1;
            }
            property int _sp: _spacerIdx()
            property bool _flex: _sp >= 0
            property var _leftKids: (node && node.children) ? (_flex ? node.children.slice(0, _sp) : node.children) : []
            property var _rightKids: (node && node.children && _flex) ? node.children.slice(_sp + 1) : []

            implicitWidth: leftRow.implicitWidth + (_flex ? rightRow.implicitWidth + gap : 0)
            implicitHeight: Math.max(leftRow.implicitHeight, rightRow.implicitHeight)

            Row {
                id: leftRow
                anchors.left: parent.left
                anchors.top: rr.valign === "top" ? parent.top : undefined
                anchors.bottom: rr.valign === "bottom" ? parent.bottom : undefined
                anchors.verticalCenter: (rr.valign !== "top" && rr.valign !== "bottom") ? parent.verticalCenter : undefined
                spacing: rr.gap
                Repeater { model: rr._leftKids; delegate: SduiChild { node: modelData; ctx: rr.ctx } }
            }
            Row {
                id: rightRow
                anchors.right: parent.right
                anchors.top: rr.valign === "top" ? parent.top : undefined
                anchors.bottom: rr.valign === "bottom" ? parent.bottom : undefined
                anchors.verticalCenter: (rr.valign !== "top" && rr.valign !== "bottom") ? parent.verticalCenter : undefined
                spacing: rr.gap
                visible: rr._flex
                Repeater { model: rr._rightKids; delegate: SduiChild { node: modelData; ctx: rr.ctx } }
            }
        }
    }
    Component {
        id: cStack
        Item {
            id: st
            property var node
            property var ctx
            property string align: node && node.alignment ? node.alignment : "center"
            width: parent ? parent.width : implicitWidth
            // A ZStack (iOS ZStack / Android Box) sizes to its LARGEST child. Deriving that
            // from childrenRect is CIRCULAR here — children are centre-anchored, so
            // childrenRect ← child positions ← parent height ← implicitHeight — which Qt5
            // detects as a binding loop and resolves to 0, collapsing the stack. Measure each
            // child's own RESOLVED size instead: intrinsic, no cycle. A child's resolved size
            // lives in its actual `width`/`height` (SduiChild folds in fixed sizes there) — a
            // bare Loader does NOT forward a child's implicitWidth/Height once it carries its
            // own width/height bindings, so `implicitWidth`/`implicitHeight` read 0 for
            // fixed-size children. Take the max of both to be safe.
            property real _maxH: 0
            property real _maxW: 0
            implicitHeight: _maxH
            implicitWidth: _maxW
            function _remeasure() {
                var mh = 0, mw = 0;
                for (var i = 0; i < st.children.length; i++) {
                    var c = st.children[i];
                    if (!c) continue;
                    var ch = Math.max(c.implicitHeight || 0, c.height || 0);
                    var cw = Math.max(c.implicitWidth || 0, c.width || 0);
                    if (ch > mh) mh = ch;
                    if (cw > mw) mw = cw;
                }
                st._maxH = mh; st._maxW = mw;
            }
            Repeater {
                model: (node && node.children) ? node.children : []
                onItemAdded: st._remeasure()
                onItemRemoved: st._remeasure()
                delegate: SduiChild {
                    node: modelData; ctx: st.ctx
                    // A ZStack proposes its own size to each child (SwiftUI ZStack / Compose Box):
                    // a fixed-size child keeps its size, every other child is offered the stack's
                    // width. Without this a non-fixed overlay (e.g. the featured card's caption
                    // vstack) hits a circular width↔implicitWidth and collapses to 0, so its text
                    // wraps to nothing and piles up. Height stays intrinsic so bottom/top anchoring
                    // still hugs content.
                    width: (item && item._fixedW >= 0) ? item._fixedW : st.width
                    onImplicitHeightChanged: st._remeasure()
                    onImplicitWidthChanged: st._remeasure()
                    onHeightChanged: st._remeasure()
                    onWidthChanged: st._remeasure()
                    // Overlay each child at the stack's alignment corner. "center" must NOT set
                    // anchors.left — QML then drops the horizontalCenter and the concentric
                    // ring/overlay children pin left instead of nesting centered.
                    anchors.left:   st.align.indexOf("Leading") >= 0 || st.align === "leading" || st.align === "top" || st.align === "bottom" ? st.left : undefined
                    anchors.right:  st.align.indexOf("Trailing") >= 0 || st.align === "trailing" ? st.right : undefined
                    anchors.top:    st.align.indexOf("top") === 0 || st.align === "topLeading" || st.align === "topTrailing" ? st.top : undefined
                    anchors.bottom: st.align.indexOf("bottom") === 0 || st.align === "bottomLeading" || st.align === "bottomTrailing" ? st.bottom : undefined
                    anchors.horizontalCenter: st.align === "center" || st.align === "top" || st.align === "bottom" ? st.horizontalCenter : undefined
                    anchors.verticalCenter: st.align === "center" || st.align === "leading" || st.align === "trailing" ? st.verticalCenter : undefined
                }
            }
        }
    }
    Component {
        id: cScroll
        Item {
            id: sc
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            // Hug the loaded scroll surface. Reading scl.item.implicit* DIRECTLY (not the Loader's
            // own forwarded implicit size — Qt5 drops that once the Loader carries a width binding)
            // is what carries a horizontal rail's height up to the enclosing SduiRenderer; a bare
            // Loader here reported 0 and collapsed every rail.
            implicitWidth: scl.item ? scl.item.implicitWidth : 0
            implicitHeight: scl.item ? scl.item.implicitHeight : 0
            height: implicitHeight
            Loader {
                id: scl
                anchors.left: parent.left
                anchors.right: parent.right
                height: item ? item.implicitHeight : 0
                property var node: sc.node
                property var ctx: sc.ctx
                sourceComponent: (sc.node && sc.node.axis === "horizontal") ? cHScroll : cVPass
            }
        }
    }
    // Horizontal rail: a Flickable wrapping the child hstack.
    Component {
        id: cHScroll
        Flickable {
            id: hf
            property var node: parent ? parent.node : null
            property var ctx: parent ? parent.ctx : null
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            // A Flickable has no intrinsic implicit size; without this the enclosing cScroll
            // Loader (which sizes to its item's IMPLICIT height) reports 0 and the whole rail
            // collapses. Expose the content height/width so it propagates up the Loader chain.
            implicitHeight: inner.height
            implicitWidth: inner.width
            height: inner.height
            contentWidth: inner.width
            contentHeight: inner.height
            // Reference the Flickable by id (hf), NOT `parent`: a child declared inside a Flickable
            // is reparented to its `contentItem`, so `parent.node`/`parent.ctx` would resolve
            // against contentItem (no such properties) and the rail's content would never load.
            SduiChild { id: inner; node: hf.node ? hf.node.child : null; ctx: hf.ctx }
        }
    }
    // Vertical scroll is a pass-through (the page already provides the scroll surface).
    Component {
        id: cVPass
        Column {
            property var node: parent ? parent.node : null
            property var ctx: parent ? parent.ctx : null
            width: parent ? parent.width : implicitWidth
            SduiChild { width: parent.width; node: parent.node ? parent.node.child : null; ctx: parent.ctx }
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
                            SduiChild {
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
            font.pixelSize: node ? T.fontSize(node.style, ctx) : Theme.fontSizeMedium
            font.weight: node ? T.fontWeight(node.style, ctx) : Font.Normal
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
    // image — a remote picture sized by its `loader.aspectRatio` (height = width / ratio, iOS
    // .aspectRatio / Compose .aspectRatio) or, when no ratio is given, by the frame its parent
    // imposes (modifiers.size / a fixed-height container — the MEDIA-card case). While loading or
    // on failure it fills that frame with a skeleton/placeholder (never collapses to zero), the
    // same grey box iOS/Android show — so an offline snapshot matches them. contentMode fill→crop,
    // fit→letterbox; `placeholder: "none"` draws nothing under a not-yet-loaded image.
    Component {
        id: cImage
        Item {
            property var node
            property var ctx
            property var ldr: (node && node.loader) ? node.loader : null
            property real ar: ldr ? T.num(ldr.aspectRatio, ctx, 0) : 0
            property string ph: (ldr && ldr.placeholder) ? T.str(ldr.placeholder, ctx) : "skeleton"
            property bool crop: !(ldr && ldr.contentMode === "fit")
            width: parent ? parent.width : implicitWidth
            implicitWidth: parent ? parent.width : 200
            implicitHeight: ar > 0 ? (width / ar) : (parent ? parent.height : 0)
            height: implicitHeight
            clip: true

            Rectangle {   // skeleton / loading + failure surface
                anchors.fill: parent
                visible: img.status !== Image.Ready && parent.ph !== "none"
                color: Qt.rgba(0.5, 0.5, 0.5, 0.12)
            }
            Label {       // failure / empty glyph, centred on the placeholder
                anchors.centerIn: parent
                visible: (img.status === Image.Error || img.status === Image.Null) && parent.ph !== "none"
                text: T.glyph("photo"); opacity: 0.45; font.pixelSize: 28
                color: Theme.secondaryColor
            }
            Image {
                id: img
                anchors.fill: parent
                fillMode: parent.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                clip: true
                asynchronous: true
                cache: true
                source: node ? T.str(node.source, ctx) : ""
            }
        }
    }
    Component {
        id: cIcon
        Label {
            property var node
            property var ctx
            // Aurora has no SF-Symbol font → map the name to a Unicode/emoji glyph, and honor
            // the contract's icon size + colour (was rendering the raw name at default size).
            text: node ? T.glyph(T.str(node.name, ctx)) : ""
            font.pixelSize: node ? T.num(node.size, ctx, Theme.iconSizeMedium) : Theme.iconSizeMedium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
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
                delegate: SduiChild {
                    width: parent.width
                    node: parent.node.template
                    ctx: parent._rowCtx(modelData)
                }
            }
            // Empty slot — shown when a templated list resolves to zero rows.
            // (An invisible child is excluded from Column layout, so this adds no
            // gap when there ARE rows.)
            SduiChild {
                width: parent.width
                visible: parent._templated && parent._rows !== null && parent._rows.length === 0
                         && parent.node && parent.node.empty !== undefined
                node: (parent.node && parent.node.empty !== undefined) ? parent.node.empty : null
                ctx: parent.ctx
            }
            // Inline children (non-templated list).
            Repeater {
                model: !parent._templated && parent.node && parent.node.children ? parent.node.children : []
                delegate: SduiChild { width: parent.width; node: modelData; ctx: parent.ctx }
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
                        delegate: SduiChild {
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

    // async — fetch-then-render container: a phase machine (loading → loaded →
    // content, or failed → error). Declares one `source` (DataSource); shows the
    // `loading` slot while in flight, then renders `content` with the response
    // bound as `$data.<source.id>`; on failure shows the `error` slot. Faithful to
    // iOS AsyncView (Async.swift:28). Aurora has no network layer in the reference
    // host, so when `ctx.loadSource` is absent the load is SIMULATED: a short
    // in-flight delay then success with an empty `$data.<id>` object (the real
    // host injects the payload). Default loading = an indeterminate sweep bar;
    // default error = a plain recoverable message — matching the iOS defaults.
    Component {
        id: cAsync
        Item {
            id: aroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: aloader.item ? aloader.item.implicitHeight : 120
            height: implicitHeight

            // 0 = loading, 1 = loaded, 2 = failed.
            property int phase: 0
            property var loadedValue: null
            property var source: (node && node.source) ? node.source : null
            property string sourceId: (aroot.source && aroot.source.id) ? aroot.source.id : "data"

            // A per-child render ctx with the response injected under $data.<id>.
            function _contentCtx() {
                var c = {};
                for (var k in ctx) c[k] = ctx[k];
                var d = {};
                if (ctx && ctx.data) { for (var j in ctx.data) d[j] = ctx.data[j]; }
                d[aroot.sourceId] = aroot.loadedValue;
                c.data = d;
                return c;
            }

            function _begin() {
                aroot.phase = 0;
                if (!aroot.source) { aroot.phase = 2; return; }
                // Real host hook, if the environment provides one (async → callback).
                if (ctx && typeof ctx.loadSource === "function") {
                    ctx.loadSource(aroot.source, function (value) {
                        if (value === undefined || value === null) { aroot.phase = 2; }
                        else { aroot.loadedValue = value; aroot.phase = 1; }
                    });
                    return;
                }
                // No loader in this host → simulate a successful fetch.
                asim.restart();
            }
            Component.onCompleted: _begin()

            Timer {
                id: asim
                interval: 800
                repeat: false
                onTriggered: { aroot.loadedValue = {}; aroot.phase = 1; }
            }

            Loader {
                id: aloader
                width: parent.width
                sourceComponent: aroot.phase === 1 ? aContent
                    : aroot.phase === 2 ? aError : aLoading
            }

            // loaded → the content slot, rendered with $data injected.
            Component {
                id: aContent
                SduiChild {
                    width: parent ? parent.width : implicitWidth
                    node: (aroot.node && aroot.node.content !== undefined) ? aroot.node.content : null
                    ctx: aroot._contentCtx()
                }
            }
            // loading → the loading slot, or a default indeterminate sweep bar.
            Component {
                id: aLoading
                Loader {
                    width: parent ? parent.width : implicitWidth
                    sourceComponent: (aroot.node && aroot.node.loading !== undefined) ? aLoadingSlot : aLoadingDefault
                }
            }
            Component {
                id: aLoadingSlot
                SduiChild {
                    width: parent ? parent.width : implicitWidth
                    node: aroot.node.loading; ctx: aroot.ctx
                }
            }
            Component {
                id: aLoadingDefault
                Item {
                    width: parent ? parent.width : implicitWidth
                    implicitHeight: 86
                    Rectangle {
                        id: adtrack
                        anchors.centerIn: parent
                        width: Math.min(parent.width - Theme.paddingLarge * 2, 260)
                        height: 6; radius: 3
                        color: Theme.highlightColor; opacity: 0.16
                        clip: true
                        Rectangle {
                            id: adsweep
                            height: parent.height; radius: 3
                            width: parent.width * 0.4
                            color: Theme.highlightColor
                            SequentialAnimation on x {
                                loops: Animation.Infinite
                                NumberAnimation { from: -adsweep.width; to: adtrack.width; duration: 1100; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }
            // failed → the error slot, or a default recoverable message.
            Component {
                id: aError
                Loader {
                    width: parent ? parent.width : implicitWidth
                    sourceComponent: (aroot.node && aroot.node.error !== undefined) ? aErrorSlot : aErrorDefault
                }
            }
            Component {
                id: aErrorSlot
                SduiChild {
                    width: parent ? parent.width : implicitWidth
                    node: aroot.node.error; ctx: aroot.ctx
                }
            }
            Component {
                id: aErrorDefault
                Row {
                    width: parent ? parent.width : implicitWidth
                    height: 120
                    Label {
                        anchors.centerIn: parent
                        text: "⚠  Couldn't load content"
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }

    // calendar — a custom month-grid calendar driven entirely from the contract.
    // The same node does single-day, contiguous `range`, or `multi`-day selection
    // via the bindable `mode`; all dates are ISO yyyy-MM-dd strings written to
    // $state (range → startBind/endBind, multi → one comma-separated key). Faithful
    // to iOS CalendarGridView (SDUICalendar.swift:19). Pure layout + date maths, so
    // it matches the iOS/Compose grid one-to-one. Two-way via ctx.getState/setState.
    Component {
        id: cCalendar
        Column {
            id: calroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            spacing: 18

            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            property string mode: node ? T.str(node.mode, ctx) : "single"
            property bool weekMon: (node ? T.str(node.weekStart, ctx) : "sunday") === "monday"

            property string singleKey: (node && node.bind) ? node.bind : ""
            property string startKey: (node && node.startBind) ? node.startBind : ""
            property string endKey: (node && node.endBind) ? node.endBind : ""
            property string multiKey: (node && node.multiBind) ? node.multiBind : calroot.singleKey

            // Live state reads. Referencing `ctx` makes these re-evaluate whenever
            // the host reassigns it (setState rebuilds ctx wholesale), so the grid
            // repaints on every selection.
            function _read(key) {
                if (!key || !ctx || !ctx.getState) return "";
                var v = ctx.getState(key);
                return (v === undefined || v === null) ? "" : String(v);
            }
            property string vSingle: (ctx, _read(singleKey))
            property string vStart: (ctx, _read(startKey))
            property string vEnd: (ctx, _read(endKey))
            property string vMulti: (ctx, _read(multiKey))

            // Visible month (year/month ints), seeded from any current selection.
            property int visY: (new Date()).getFullYear()
            property int visM: (new Date()).getMonth()
            Component.onCompleted: {
                var anchor = _parse(vStart) || _parse(vSingle);
                if (!anchor) { var md = _multiDates(); if (md.length > 0) anchor = md[0]; }
                if (anchor) { calroot.visY = anchor.getFullYear(); calroot.visM = anchor.getMonth(); }
            }

            // ---- ES5 date helpers (local midnight; ISO yyyy-MM-dd) ----
            function _pad(n) { return n < 10 ? "0" + n : String(n); }
            function _iso(d) { return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()); }
            function _parse(s) {
                if (!s || s.length < 10) return null;
                var p = s.split("-");
                if (p.length !== 3) return null;
                var y = Number(p[0]), m = Number(p[1]), da = Number(p[2]);
                if (isNaN(y) || isNaN(m) || isNaN(da)) return null;
                return new Date(y, m - 1, da);
            }
            function _same(a, b) { return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
            function _multiDates() {
                var out = [], parts = calroot.vMulti ? calroot.vMulti.split(",") : [];
                for (var i = 0; i < parts.length; i++) { var d = _parse(parts[i]); if (d) out.push(d); }
                return out;
            }
            function _write(key, value) { if (key && ctx && ctx.setState) ctx.setState(key, value); }

            // Build the 42-cell grid (leading blanks + this month's days).
            function _cells() {
                var first = new Date(calroot.visY, calroot.visM, 1);
                var startDow = first.getDay();                       // 0=Sun..6=Sat
                var offset = calroot.weekMon ? ((startDow + 6) % 7) : startDow;
                var daysInMonth = new Date(calroot.visY, calroot.visM + 1, 0).getDate();
                var out = [], i;
                for (i = 0; i < offset; i++) out.push(null);
                for (i = 1; i <= daysInMonth; i++) out.push(new Date(calroot.visY, calroot.visM, i));
                while (out.length % 7 !== 0) out.push(null);
                return out;
            }
            property var cells: (visY, visM, weekMon, _cells())

            // Selection classification for one day → "none"|"single"|"start"|"end"|"mid".
            function _kind(day) {
                if (!day) return "none";
                if (calroot.mode === "range") {
                    var s = _parse(calroot.vStart), e = _parse(calroot.vEnd);
                    if (s && e) {
                        if (_same(s, e)) return _same(day, s) ? "single" : "none";
                        if (_same(day, s)) return "start";
                        if (_same(day, e)) return "end";
                        if (day > s && day < e) return "mid";
                        return "none";
                    }
                    if (s && _same(day, s)) return "single";
                    return "none";
                }
                if (calroot.mode === "multi") {
                    var md = _multiDates();
                    for (var i = 0; i < md.length; i++) if (_same(md[i], day)) return "single";
                    return "none";
                }
                var d = _parse(calroot.vSingle);
                if (d && _same(day, d)) return "single";
                return "none";
            }

            function _select(day) {
                if (!day) return;
                var iso = _iso(day);
                if (calroot.mode === "range") {
                    var s = calroot.vStart, e = calroot.vEnd;
                    if (s === "" || e !== "") { _write(calroot.startKey, iso); _write(calroot.endKey, ""); }
                    else {
                        var sd = _parse(s);
                        if (sd && day < sd) _write(calroot.startKey, iso);
                        else _write(calroot.endKey, iso);
                    }
                } else if (calroot.mode === "multi") {
                    var md = _multiDates(), found = -1, i;
                    for (i = 0; i < md.length; i++) if (_same(md[i], day)) { found = i; break; }
                    if (found >= 0) md.splice(found, 1); else md.push(day);
                    md.sort(function (a, b) { return a - b; });
                    var isos = [];
                    for (i = 0; i < md.length; i++) isos.push(_iso(md[i]));
                    _write(calroot.multiKey, isos.join(","));
                } else {
                    _write(calroot.singleKey, iso);
                }
            }

            function _step(delta) {
                var m = calroot.visM + delta, y = calroot.visY;
                while (m < 0) { m += 12; y -= 1; }
                while (m > 11) { m -= 12; y += 1; }
                calroot.visM = m; calroot.visY = y;
            }

            // ---- summary ----
            function _pretty(s) {
                var d = _parse(s); if (!d) return s;
                var mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                return mon[d.getMonth()] + " " + d.getDate();
            }
            function _prettyFull(s) {
                var d = _parse(s); if (!d) return s;
                var wd = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                return wd[d.getDay()] + ", " + _pretty(s);
            }
            function _nights(a, b) {
                var da = _parse(a), db = _parse(b); if (!da || !db) return "";
                var n = Math.round((db - da) / 86400000);
                return n + (n === 1 ? " night" : " nights");
            }
            function _sumCaption() {
                if (calroot.mode === "range") return "SELECTED RANGE";
                if (calroot.mode === "multi") return "SELECTED DAYS";
                return "SELECTED DATE";
            }
            function _sumLabel() {
                if (calroot.mode === "range") {
                    if (calroot.vStart === "") return "Select dates";
                    if (calroot.vEnd === "") return _pretty(calroot.vStart) + " — select end";
                    return _pretty(calroot.vStart) + " – " + _pretty(calroot.vEnd);
                }
                if (calroot.mode === "multi") {
                    var n = _multiDates().length;
                    return n === 0 ? "Pick any days" : (n + " selected");
                }
                return calroot.vSingle === "" ? "Select a date" : _prettyFull(calroot.vSingle);
            }
            function _sumTrailing() {
                if (calroot.mode === "range" && calroot.vStart !== "" && calroot.vEnd !== "")
                    return _nights(calroot.vStart, calroot.vEnd);
                return "";
            }

            // Summary header.
            Column {
                width: parent.width
                spacing: 3
                Label {
                    text: calroot._sumCaption()
                    font.pixelSize: Theme.fontSizeExtraSmall
                    font.bold: true
                    color: Theme.secondaryColor
                }
                Row {
                    width: parent.width
                    Label {
                        width: parent.width - trail.width
                        text: calroot._sumLabel()
                        font.pixelSize: Theme.fontSizeLarge
                        font.bold: true
                        color: calroot.tint
                    }
                    Label {
                        id: trail
                        anchors.bottom: parent.bottom
                        text: calroot._sumTrailing()
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }
                }
            }

            // Month title + navigation.
            Row {
                width: parent.width
                Label {
                    width: parent.width - navL.width - navR.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var mon = ["January", "February", "March", "April", "May", "June",
                                   "July", "August", "September", "October", "November", "December"];
                        return mon[calroot.visM] + " " + calroot.visY;
                    }
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: Theme.primaryColor
                }
                Rectangle {
                    id: navL
                    width: 40; height: 40; radius: 20
                    color: calroot.tint; opacity: 0.10
                    Label { anchors.centerIn: parent; text: "‹"; font.pixelSize: Theme.fontSizeLarge; color: calroot.tint; opacity: 1 }
                    MouseArea { anchors.fill: parent; onClicked: calroot._step(-1) }
                }
                Rectangle {
                    id: navR
                    width: 40; height: 40; radius: 20
                    color: calroot.tint; opacity: 0.10
                    Label { anchors.centerIn: parent; text: "›"; font.pixelSize: Theme.fontSizeLarge; color: calroot.tint }
                    MouseArea { anchors.fill: parent; onClicked: calroot._step(1) }
                }
            }

            // Weekday header row.
            Row {
                width: parent.width
                property var syms: calroot.weekMon ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]
                Repeater {
                    model: 7
                    delegate: Label {
                        width: parent.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: parent.syms[index]
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.bold: true
                        color: Theme.secondaryColor
                    }
                }
            }

            // Day grid — 7 columns, zero spacing so range bands join into one pill.
            Grid {
                width: parent.width
                columns: 7
                rowSpacing: 4
                columnSpacing: 0
                property real cw: width / 7
                Repeater {
                    model: calroot.cells
                    delegate: Item {
                        width: parent.cw
                        height: 44
                        property var day: modelData
                        property string kind: calroot._kind(day)
                        property bool onFill: kind === "single" || kind === "start" || kind === "end"
                        property bool isToday: day ? calroot._same(day, new Date()) : false

                        // Range band halves (join across cells at zero column spacing).
                        Row {
                            anchors.fill: parent
                            visible: parent.kind === "start" || parent.kind === "end" || parent.kind === "mid"
                            Rectangle {
                                width: parent.width / 2; height: 40
                                anchors.verticalCenter: parent.verticalCenter
                                color: (parent.parent.kind === "end" || parent.parent.kind === "mid") ? calroot.tint : "transparent"
                                opacity: 0.15
                            }
                            Rectangle {
                                width: parent.width / 2; height: 40
                                anchors.verticalCenter: parent.verticalCenter
                                color: (parent.parent.kind === "start" || parent.parent.kind === "mid") ? calroot.tint : "transparent"
                                opacity: 0.15
                            }
                        }
                        Rectangle {  // filled endpoint / single
                            visible: parent.onFill
                            anchors.centerIn: parent
                            width: 38; height: 38; radius: 19
                            color: calroot.tint
                        }
                        Rectangle {  // today ring (unselected)
                            visible: !parent.onFill && parent.isToday && parent.kind === "none"
                            anchors.centerIn: parent
                            width: 38; height: 38; radius: 19
                            color: "transparent"
                            border.color: calroot.tint; border.width: 1.5
                            opacity: 0.6
                        }
                        Label {
                            anchors.centerIn: parent
                            visible: parent.day !== null
                            text: parent.day ? String(parent.day.getDate()) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: parent.kind !== "none"
                            color: parent.onFill ? "white" : (parent.isToday && parent.kind === "none" ? calroot.tint : Theme.primaryColor)
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.day !== null
                            onClicked: calroot._select(parent.day)
                        }
                    }
                }
            }
        }
    }

    // clips — a full-screen vertical snap feed (Instagram Reels / TikTok). Each
    // `pages[i]` carries its own gradient media, caption block and action-rail
    // counts; swipe up/down to page, double-tap to like (with a heart burst), and
    // a brief shimmering skeleton simulates media buffering. Faithful to iOS
    // ClipsView (ClipsView.swift:13). ES5.
    Component {
        id: cClips
        Item {
            id: clroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            // A snap feed wants full height; Silica's Screen scales per device.
            property real feedH: (typeof Screen !== "undefined" && Screen.height) ? Screen.height * 0.82 : 640
            implicitHeight: feedH
            height: feedH
            clip: true

            property var pages: (node && node.pages && Object.prototype.toString.call(node.pages) === "[object Array]") ? node.pages : []
            property int index: 0
            property real drag: 0
            property var liked: ({})
            property int burst: -1
            property real discAngle: 0

            NumberAnimation on discAngle { from: 0; to: 360; duration: 6000; loops: Animation.Infinite; running: true }

            function _isLiked(i) { return clroot.liked[i] === true; }
            function _toggle(i) {
                var m = {}; for (var k in clroot.liked) m[k] = clroot.liked[k];
                m[i] = !(m[i] === true); clroot.liked = m;
            }
            function _burst(i) {
                if (!(clroot.liked[i] === true)) _toggle(i);
                clroot.burst = i; burstTimer.restart();
            }
            Timer { id: burstTimer; interval: 650; onTriggered: clroot.burst = -1 }

            function _settle(dy, h) {
                var threshold = h * 0.18, next = clroot.index;
                if (dy < -threshold && clroot.index < clroot.pages.length - 1) next += 1;
                else if (dy > threshold && clroot.index > 0) next -= 1;
                clroot.index = next; clroot.drag = 0;
            }

            Rectangle { anchors.fill: parent; color: "black" }

            // The stacked pages, offset by the current index + live drag.
            Column {
                id: stack
                width: parent.width
                y: -clroot.index * clroot.feedH + clroot.drag
                Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                Repeater {
                    model: clroot.pages
                    delegate: Item {
                        width: clroot.width
                        height: clroot.feedH
                        property var pg: modelData
                        property int pgIndex: index

                        // Gradient media backdrop.
                        LinearGradient {
                            anchors.fill: parent
                            start: Qt.point(0, 0)
                            end: Qt.point(width, height)
                            property var cols: (pg && pg.colors && pg.colors.length >= 2) ? pg.colors : ["#7A3CF0", "#101018"]
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: parent.cols[0] }
                                GradientStop { position: 1.0; color: parent.cols[parent.cols.length - 1] }
                            }
                        }
                        // Legibility scrim.
                        LinearGradient {
                            anchors.fill: parent
                            start: Qt.point(0, 0); end: Qt.point(0, height)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#26000000" }
                                GradientStop { position: 0.55; color: "#00000000" }
                                GradientStop { position: 1.0; color: "#8C000000" }
                            }
                        }

                        // Heart burst on double-tap.
                        Label {
                            anchors.centerIn: parent
                            visible: clroot.burst === pgIndex
                            text: "♥"
                            color: "white"
                            font.pixelSize: 140
                            scale: clroot.burst === pgIndex ? 1 : 0.4
                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                        }

                        // Caption block (bottom-left) + action rail (bottom-right).
                        Item {
                            anchors.fill: parent
                            anchors.margins: 18
                            Column {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 40
                                width: parent.width * 0.72
                                spacing: 8
                                Row {
                                    spacing: 9
                                    Rectangle {
                                        width: 38; height: 38; radius: 19
                                        color: "#CC1D1D1F"
                                        border.color: "#FF6B57"; border.width: 2
                                        Label {
                                            anchors.centerIn: parent
                                            text: {
                                                var a = pg && pg.author ? String(pg.author) : "@";
                                                var s = a.charAt(0) === "@" ? a.substring(1) : a;
                                                return s.length > 0 ? s.charAt(0).toUpperCase() : "-";
                                            }
                                            color: "white"; font.bold: true; font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: pg && pg.author ? String(pg.author) : "@creator"
                                        color: "white"; font.bold: true; font.pixelSize: Theme.fontSizeMedium
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: followLbl.width + 24; height: followLbl.height + 10
                                        radius: 8; color: "transparent"
                                        border.color: "white"; border.width: 1
                                        Label { id: followLbl; anchors.centerIn: parent; text: "Follow"; color: "white"; font.pixelSize: Theme.fontSizeExtraSmall; font.bold: true }
                                    }
                                }
                                Label {
                                    width: parent.width
                                    visible: !!(pg && pg.caption)
                                    text: pg && pg.caption ? String(pg.caption) : ""
                                    color: "white"; font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                                Row {
                                    spacing: 7
                                    Label { text: "♪"; color: "white"; font.pixelSize: Theme.fontSizeSmall }
                                    Label {
                                        text: pg && pg.audio ? String(pg.audio) : "Original audio"
                                        color: "white"; font.pixelSize: Theme.fontSizeExtraSmall
                                    }
                                }
                            }
                            Column {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 40
                                spacing: 22
                                // Like.
                                Column {
                                    spacing: 4
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: clroot._isLiked(pgIndex) ? "♥" : "♡"
                                        color: clroot._isLiked(pgIndex) ? "#FF3D5E" : "white"
                                        font.pixelSize: 34
                                        scale: clroot._isLiked(pgIndex) ? 1.12 : 1
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                        MouseArea { anchors.fill: parent; onClicked: clroot._toggle(pgIndex) }
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: pg && pg.likes ? String(pg.likes) : "0"
                                        color: "white"; font.pixelSize: Theme.fontSizeExtraSmall; font.bold: true
                                    }
                                }
                                // Comments.
                                Column {
                                    spacing: 4
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "💬"; font.pixelSize: 30 }
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: pg && pg.comments ? String(pg.comments) : "0"; color: "white"; font.pixelSize: Theme.fontSizeExtraSmall; font.bold: true }
                                }
                                // Shares.
                                Column {
                                    spacing: 4
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "↪"; color: "white"; font.pixelSize: 32 }
                                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: pg && pg.shares ? String(pg.shares) : "Share"; color: "white"; font.pixelSize: Theme.fontSizeExtraSmall; font.bold: true }
                                }
                                // Spinning audio disc.
                                Rectangle {
                                    width: 42; height: 42; radius: 21
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#E6FFFFFF" }
                                        GradientStop { position: 1.0; color: "#888888" }
                                    }
                                    rotation: clroot.discAngle
                                    Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: "black" }
                                }
                            }
                        }

                        // Buffering skeleton (first ~0.75s per page).
                        Rectangle {
                            anchors.fill: parent
                            color: "#59000000"
                            visible: opacity > 0.01
                            opacity: pgIndex === clroot.index ? 1 : 0
                            Timer { running: pgIndex === clroot.index; interval: 750; onTriggered: parent.opacity = 0 }
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                    }
                }
            }

            // Top tab bar overlay.
            Row {
                anchors.top: parent.top
                anchors.topMargin: 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 22
                Label { text: "Following"; color: "#B3FFFFFF"; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Label { text: "For You"; color: "white"; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }

            // Paging drag surface (children handle their own taps first).
            MouseArea {
                anchors.fill: parent
                propagateComposedEvents: true
                property real _startY: 0
                onPressed: _startY = mouse.y
                onPositionChanged: {
                    var dy = mouse.y - _startY;
                    if ((clroot.index === 0 && dy > 0) || (clroot.index === clroot.pages.length - 1 && dy < 0)) dy *= 0.3;
                    clroot.drag = dy;
                }
                onReleased: clroot._settle(mouse.y - _startY, clroot.feedH)
                onCanceled: { clroot.drag = 0; }
                onDoubleClicked: clroot._burst(clroot.index)
            }
        }
    }

    // datepicker — a native single-date picker two-way bound to an ISO yyyy-MM-dd
    // $state key. `style:"graphical"` shows Silica's inline month DatePicker;
    // `style:"compact"` shows a tappable value field that expands the same picker.
    // Faithful to iOS DatePickerView (Calendar.swift:12). Two-way via getState/setState.
    Component {
        id: cDatePicker
        Column {
            id: dproot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            spacing: Theme.paddingSmall

            property string bindKey: (node && node.bind) ? node.bind : ""
            property string style: (node && node.style) ? node.style : "graphical"
            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            property bool expanded: style === "graphical"

            function _pad(n) { return n < 10 ? "0" + n : String(n); }
            function _iso(d) { return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()); }
            function _cur() {
                if (!ctx || !ctx.getState) return "";
                var v = ctx.getState(bindKey);
                return (v === undefined || v === null) ? "" : String(v);
            }
            function _curDate() {
                var s = (ctx, _cur());
                if (s && s.length >= 10) {
                    var p = s.split("-");
                    if (p.length === 3) { var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2])); if (!isNaN(d.getTime())) return d; }
                }
                return new Date();
            }
            property string curIso: (ctx, _cur())

            // Compact field (value + chevron) — toggles the inline picker.
            Rectangle {
                width: parent.width
                visible: dproot.style === "compact"
                height: 56; radius: 12
                color: Qt.rgba(0.5, 0.5, 0.5, 0.10)
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.paddingLarge
                    anchors.rightMargin: Theme.paddingLarge
                    spacing: Theme.paddingMedium
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - chev2.width - Theme.paddingMedium
                        text: dproot.curIso.length > 0 ? dproot.curIso : "Select a date"
                        color: dproot.curIso.length > 0 ? Theme.primaryColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    Label {
                        id: chev2
                        anchors.verticalCenter: parent.verticalCenter
                        text: dproot.expanded ? "▲" : "▼"
                        color: dproot.tint
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: dproot.expanded = !dproot.expanded }
            }

            // The inline month picker (Silica native).
            DatePicker {
                id: dpick
                visible: dproot.expanded
                width: parent.width
                date: dproot._curDate()
                onDateChanged: {
                    if (dproot.bindKey && dproot.ctx && dproot.ctx.setState)
                        dproot.ctx.setState(dproot.bindKey, dproot._iso(date));
                }
            }
        }
    }

    // filecell — a document / upload cell with the full state set: empty →
    // loading → success / warning (too large) / error. A fixed `state` pins one
    // showcase state (with `title`/`size`); otherwise tapping an empty cell
    // simulates a pick (Aurora's file dialog needs pageStack + Sailfish.Pickers,
    // so the interactive path fakes the pick → brief loading → success, matching
    // the iOS timing). Faithful to iOS FileCellView (FileCell.swift:16).
    Component {
        id: cFileCell
        Item {
            id: fcroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: fcloader.item ? fcloader.item.implicitHeight : 80
            height: implicitHeight

            property string tint: T.color(node && node.color, ctx, Theme.highlightColor)
            property string fixedState: (node && node.state) ? String(node.state) : ""
            property real maxKB: T.num(node && node.maxSizeKB, ctx, -1)
            property string titleText: node ? T.str(node.title, ctx) : ""
            property string sizeText: node ? T.str(node.size, ctx) : ""
            property string viewLabel: (node && node.viewLabel) ? T.str(node.viewLabel, ctx) : "View"

            // interactive phase: "empty" | "loading" | "success"
            property string phase: "empty"
            function _fixedPhase() {
                var s = fcroot.fixedState;
                if (s === "loading") return "loading";
                if (s === "success") return "success";
                if (s === "warning" || s === "tooLarge") return "warning";
                if (s === "error" || s === "failed") return "error";
                if (s === "empty") return "empty";
                return "";
            }
            property string current: (fcroot._fixedPhase() !== "") ? fcroot._fixedPhase() : fcroot.phase
            property bool showcase: fcroot._fixedPhase() !== ""

            function _fileName() { return fcroot.titleText.length > 0 ? fcroot.titleText : "Document.pdf"; }
            function _ext() {
                var n = fcroot._fileName(), dot = n.lastIndexOf(".");
                return dot >= 0 ? n.substring(dot + 1).toUpperCase() : "";
            }
            function _glyph() {
                var e = fcroot._ext().toLowerCase();
                if (e === "pdf") return "🖹";
                if (e === "png" || e === "jpg" || e === "jpeg" || e === "heic" || e === "gif") return "🖼";
                if (e === "mp4" || e === "mov" || e === "m4v") return "🎞";
                if (e === "zip" || e === "rar" || e === "7z") return "🗜";
                return "🗎";
            }
            function _warnText() {
                if (node && node.limitText) return T.str(node.limitText, ctx);
                if (fcroot.maxKB > 0) return "Attach a file no larger than " + Math.round(fcroot.maxKB / 1024) + " MB";
                return "File is too large";
            }
            function _errText() { return (node && node.errorText) ? T.str(node.errorText, ctx) : "Upload failed"; }

            function _pick() {
                if (fcroot.showcase) return;
                fcroot.phase = "loading";
                fcpickTimer.restart();
            }
            Timer { id: fcpickTimer; interval: 1100; onTriggered: fcroot.phase = "success" }
            function _remove() { if (!fcroot.showcase) fcroot.phase = "empty"; }

            Loader {
                id: fcloader
                width: parent.width
                sourceComponent: fcroot.current === "empty" ? fcEmpty
                    : fcroot.current === "loading" ? fcLoading : fcCard
            }

            // Empty — dashed drop target.
            Component {
                id: fcEmpty
                Rectangle {
                    width: parent ? parent.width : implicitWidth
                    implicitHeight: 76; height: 76
                    radius: 16; color: "transparent"
                    border.color: Qt.rgba(0.5, 0.5, 0.5, 0.35); border.width: 1.5
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16; anchors.rightMargin: 16
                        spacing: 14
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "⭱"; font.pixelSize: 26; color: fcroot.tint }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - 16 - chevF.width - 28
                            spacing: 2
                            Label { text: fcroot.titleText.length > 0 ? fcroot.titleText : "Choose a file"; font.pixelSize: Theme.fontSizeMedium; font.bold: true; color: Theme.primaryColor }
                            Label {
                                text: fcroot.maxKB > 0 ? ("Max " + Math.round(fcroot.maxKB / 1024) + " MB") : "From Files or cloud storage"
                                font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor
                            }
                        }
                        Label { id: chevF; anchors.verticalCenter: parent.verticalCenter; text: "›"; font.pixelSize: Theme.fontSizeLarge; color: Theme.secondaryColor }
                    }
                    MouseArea { anchors.fill: parent; onClicked: fcroot._pick() }
                }
            }
            // Loading — spinner + skeleton bars.
            Component {
                id: fcLoading
                Rectangle {
                    width: parent ? parent.width : implicitWidth
                    implicitHeight: 76; height: 76
                    radius: 16; color: Qt.rgba(0.5, 0.5, 0.5, 0.06)
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16; spacing: 14
                        BusyIndicator { anchors.verticalCenter: parent.verticalCenter; running: true; size: BusyIndicatorSize.Small }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9
                            Rectangle { width: 190; height: 12; radius: 6; color: Qt.rgba(0.5, 0.5, 0.5, 0.18) }
                            Rectangle { width: 120; height: 12; radius: 6; color: Qt.rgba(0.5, 0.5, 0.5, 0.18) }
                        }
                    }
                }
            }
            // success / warning / error — the card row.
            Component {
                id: fcCard
                Rectangle {
                    width: parent ? parent.width : implicitWidth
                    implicitHeight: 84; height: 84
                    radius: 16; color: Qt.rgba(0.5, 0.5, 0.5, 0.06)
                    property string tone: fcroot.current === "warning" ? "#E8871E"
                        : fcroot.current === "error" ? "#C0392B" : Theme.secondaryColor
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16; anchors.rightMargin: 8
                        spacing: 14
                        Label {
                            anchors.top: parent.top; anchors.topMargin: 16
                            text: fcroot.current === "warning" ? "⚠" : fcroot.current === "error" ? "⊗" : fcroot._glyph()
                            font.pixelSize: 24
                            color: fcroot.current === "success" ? Theme.secondaryColor : parent.tone
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - 14 - trashF.width - 24
                            spacing: 2
                            Label { text: fcroot._fileName(); font.pixelSize: Theme.fontSizeMedium; font.bold: true; color: Theme.primaryColor; truncationMode: TruncationMode.Fade; width: parent.width }
                            Label { visible: fcroot.sizeText.length > 0; text: fcroot.sizeText; font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor }
                            Label {
                                text: fcroot.current === "success" ? fcroot.viewLabel
                                    : fcroot.current === "warning" ? fcroot._warnText() : fcroot._errText()
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: fcroot.current === "success"
                                color: fcroot.current === "success" ? fcroot.tint : parent.parent.tone
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: fcroot.current === "success"
                                    onClicked: {}
                                }
                            }
                        }
                        Label {
                            id: trashF
                            anchors.verticalCenter: parent.verticalCenter
                            text: "🗑"; font.pixelSize: 22; color: Theme.secondaryColor
                            MouseArea { anchors.fill: parent; onClicked: fcroot._remove() }
                        }
                    }
                }
            }
        }
    }

    // pager — a paging carousel (one child page at a time) with a page-dot
    // indicator and optional auto-advance. Powers rotating hero banners. Manual
    // swipe always works; auto-advance runs only when `autoAdvanceMs > 0`.
    // Faithful to iOS PagerView (Pager.swift:10). Uses Silica's SlideshowView.
    Component {
        id: cPager
        Column {
            id: pgroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            spacing: 10

            property var pages: (node && node.children && Object.prototype.toString.call(node.children) === "[object Array]") ? node.children : []
            property real pageH: T.num(node && node.height, ctx, 200)
            property real autoMs: T.num(node && node.autoAdvanceMs, ctx, 0)
            property bool showDots: ((node && node.indicator) ? node.indicator : "dots") !== "none"
            property string accent: T.color("$token.color.primary", ctx, Theme.highlightColor)

            SlideshowView {
                id: slides
                width: parent.width
                height: pgroot.pageH
                itemWidth: width
                clip: true
                model: pgroot.pages
                delegate: Item {
                    width: slides.itemWidth
                    height: slides.height
                    SduiChild {
                        anchors.fill: parent
                        anchors.leftMargin: 20; anchors.rightMargin: 20
                        node: modelData
                        ctx: pgroot.ctx
                    }
                }
                Timer {
                    interval: pgroot.autoMs > 0 ? pgroot.autoMs : 3600000
                    repeat: true
                    running: pgroot.autoMs > 0 && pgroot.pages.length > 1
                    onTriggered: slides.currentIndex = (slides.currentIndex + 1) % pgroot.pages.length
                }
            }

            // Page dots (a widening capsule marks the current page).
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: pgroot.showDots && pgroot.pages.length > 1
                spacing: 6
                Repeater {
                    model: pgroot.pages.length
                    delegate: Rectangle {
                        height: 6; radius: 3
                        width: index === slides.currentIndex ? 18 : 6
                        color: index === slides.currentIndex ? pgroot.accent : Qt.rgba(0.5, 0.5, 0.5, 0.28)
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    }
                }
            }
        }
    }

    // picker — a single-choice control two-way bound to a $state key. `options`
    // are {label,value}; `style` selects the presentation: menu/inline/wheel use
    // Silica's ComboBox (a tappable value that lists the options), while segmented
    // renders an inline button row. Faithful to iOS PickerView (Builtins.swift:1867).
    // Two-way via getState/setState.
    Component {
        id: cPicker
        Item {
            id: pkroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            implicitHeight: pkloader.item ? pkloader.item.implicitHeight : Theme.itemSizeMedium
            height: implicitHeight

            property string bindKey: (node && node.bind) ? node.bind : ""
            property string style: (node && node.style) ? node.style : "menu"
            property string titleText: node ? T.str(node.title, ctx) : ""
            property var options: (node && node.options && Object.prototype.toString.call(node.options) === "[object Array]") ? node.options : []
            property string accent: T.color(node && node.color, ctx, Theme.highlightColor)

            function _cur() {
                if (!ctx || !ctx.getState) return "";
                var v = ctx.getState(bindKey);
                return (v === undefined || v === null) ? "" : String(v);
            }
            property string curVal: (ctx, _cur())
            function _curIndex() {
                for (var i = 0; i < pkroot.options.length; i++)
                    if (String(pkroot.options[i].value) === pkroot.curVal) return i;
                return 0;
            }
            function _label(i) { return (i >= 0 && i < pkroot.options.length) ? T.str(pkroot.options[i].label, ctx) : ""; }
            function _write(val) { if (pkroot.bindKey && pkroot.ctx && pkroot.ctx.setState) pkroot.ctx.setState(pkroot.bindKey, val); }

            Loader {
                id: pkloader
                width: parent.width
                sourceComponent: pkroot.style === "segmented" ? pkSegmented : pkCombo
            }

            // menu / inline / wheel → Silica ComboBox.
            Component {
                id: pkCombo
                ComboBox {
                    width: parent ? parent.width : implicitWidth
                    label: pkroot.titleText
                    currentIndex: pkroot._curIndex()
                    menu: ContextMenu {
                        Repeater {
                            model: pkroot.options
                            delegate: MenuItem {
                                text: pkroot._label(index)
                                onClicked: pkroot._write(String(pkroot.options[index].value))
                            }
                        }
                    }
                }
            }

            // segmented → an inline row of pill buttons.
            Component {
                id: pkSegmented
                Row {
                    width: parent ? parent.width : implicitWidth
                    spacing: 6
                    Repeater {
                        model: pkroot.options
                        delegate: Rectangle {
                            property bool sel: String(pkroot.options[index].value) === pkroot.curVal
                            width: (parent.width - 6 * (pkroot.options.length - 1)) / Math.max(1, pkroot.options.length)
                            height: Theme.itemSizeSmall
                            radius: 10
                            color: sel ? pkroot.accent : Qt.rgba(0.5, 0.5, 0.5, 0.12)
                            Label {
                                anchors.centerIn: parent
                                text: pkroot._label(index)
                                color: parent.sel ? "white" : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: parent.sel
                            }
                            MouseArea { anchors.fill: parent; onClicked: pkroot._write(String(pkroot.options[index].value)) }
                        }
                    }
                }
            }
        }
    }

    // roadmap — a numbered vertical timeline. Each step is a node on a connecting
    // rail (done → a filled check node); steps with a `detail` disclose it on tap
    // with a spring. Self-contained interaction — no $state. Faithful to iOS
    // RoadmapView (Roadmap.swift:9).
    Component {
        id: cRoadmap
        Column {
            id: rmroot
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth

            property string accent: T.color(node && node.accent, ctx, Theme.highlightColor)
            property var steps: (node && node.steps && Object.prototype.toString.call(node.steps) === "[object Array]") ? node.steps : []

            Repeater {
                model: rmroot.steps
                delegate: Item {
                    width: rmroot.width
                    implicitHeight: Math.max(rnode.height + (isLast ? 0 : 20), rtext.implicitHeight + 5 + (isLast ? 0 : 20))
                    height: implicitHeight
                    property var step: modelData
                    property bool isLast: index === rmroot.steps.length - 1
                    property bool done: !!(step && step.done)
                    property bool expanded: false
                    property string detail: step && step.detail ? T.str(step.detail, ctx) : ""
                    property bool hasDetail: detail.length > 0

                    // Node + rail column.
                    Item {
                        id: railCol
                        width: 30
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        Rectangle {  // connecting rail
                            visible: !isLast
                            width: 2; radius: 1
                            anchors.horizontalCenter: rnode.horizontalCenter
                            anchors.top: rnode.bottom
                            anchors.bottom: parent.bottom
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.20)
                        }
                        Rectangle {  // node
                            id: rnode
                            width: 30; height: 30; radius: 15
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: done ? rmroot.accent : Qt.rgba(0.5, 0.5, 0.5, 0.14)
                            Label {
                                anchors.centerIn: parent
                                text: done ? "✓" : String(index + 1)
                                color: done ? "white" : rmroot.accent
                                font.pixelSize: Theme.fontSizeExtraSmall
                                font.bold: true
                            }
                        }
                    }

                    // Title + disclosed detail.
                    Column {
                        id: rtext
                        anchors.left: railCol.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        spacing: 3
                        Label {
                            width: parent.width
                            text: step && step.title ? T.str(step.title, ctx) : ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            color: Theme.primaryColor
                            wrapMode: Text.Wrap
                        }
                        Label {
                            width: parent.width
                            visible: hasDetail && expanded
                            text: detail
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            wrapMode: Text.Wrap
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: hasDetail
                        onClicked: expanded = !expanded
                    }
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
