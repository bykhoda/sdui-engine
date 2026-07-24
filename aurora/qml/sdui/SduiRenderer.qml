// The recursive SDUI renderer for Aurora — the QML/Silica counterpart of iOS
// Builtins.swift and Android Builtins.kt. It maps a contract node ({ type, ...props,
// children }) to a Silica component via a Loader (Qt 5.6 has no DelegateChooser),
// recursing through Repeater for children.
//
// Status: v0 core primitives (stacks, text, button, image, icon, divider, spacer,
// toggle, textfield). The long tail (list templates, chart, calendar, clips, async,
// swipe, actions/runtime) is TODO — unsupported types degrade to a visible marker,
// never a crash, matching the safe-degradation contract of the other renderers.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "Tokens.js" as T

Item {
    id: root

    property var node          // parsed contract node
    property var ctx           // { tokens, state, data, env, item }

    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    function pick(type) {
        switch (type) {
        case "vstack":    return cColumn
        case "hstack":    return cRow
        case "zstack":    return cStack
        case "scroll":    return cScroll
        case "text":      return cText
        case "button":    return cButton
        case "image":     return cImage
        case "icon":      return cIcon
        case "divider":   return cDivider
        case "spacer":    return cSpacer
        case "toggle":    return cToggle
        case "textfield": return cField
        default:          return cUnknown
        }
    }

    Loader {
        id: loader
        width: root.width
        sourceComponent: root.pick(root.node ? root.node.type : "")
        onLoaded: {
            if (item) {
                item.node = root.node
                item.ctx = root.ctx
            }
        }
    }

    // ---- containers ----
    Component {
        id: cColumn
        Column {
            property var node
            property var ctx
            width: parent ? parent.width : 0
            spacing: T.num(node && node.spacing, ctx, Theme.paddingSmall)
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiRenderer { width: parent.width; node: modelData; ctx: parent.ctx }
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
            width: parent ? parent.width : 0
            implicitHeight: childrenRect.height
            Repeater {
                model: (node && node.children) ? node.children : []
                delegate: SduiRenderer { anchors.fill: parent; node: modelData; ctx: parent.ctx }
            }
        }
    }
    Component {
        id: cScroll
        // The screen page already provides the scroll surface, so `scroll` is a
        // pass-through here — avoids a nested Flickable inside a Flickable.
        Column {
            property var node
            property var ctx
            width: parent ? parent.width : 0
            SduiRenderer { width: parent.width; node: (node ? node.child : null); ctx: parent.ctx }
        }
    }

    // ---- leaves ----
    Component {
        id: cText
        Label {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            wrapMode: Text.Wrap
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
            // TODO: dispatch node.onTap once the Aurora action runtime is ported.
        }
    }
    Component {
        id: cImage
        Image {
            property var node
            property var ctx
            width: parent ? parent.width : implicitWidth
            fillMode: Image.PreserveAspectFit
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
