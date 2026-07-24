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
