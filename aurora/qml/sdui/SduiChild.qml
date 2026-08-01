// Recursion shim for the QML renderer.
//
// Qt 5's QML engine refuses to let a component instantiate itself by type name — a
// `SduiRenderer { }` inside SduiRenderer.qml raises "SduiRenderer is instantiated
// recursively", the type becomes *unavailable*, and the whole screen renders blank (the
// error cascades up through ScreenPage). The world-standard fix for a recursive QML tree is
// to break the compile-time cycle with a Loader whose `source` is a URL resolved at RUNTIME:
// SduiRenderer.qml → SduiChild (this) → Loader.source "SduiRenderer.qml", so nothing depends
// on its own type at compile time. Every child in SduiRenderer's containers goes through here.
//
// It forwards `node`/`ctx` to the loaded renderer and ADOPTS the renderer's real size. A bare
// Loader sizes only to its item's IMPLICIT size, which silently drops fixed sizes from the
// contract (`modifiers.size` — e.g. Live cards 172×212, icon-rail items width 84) and
// collapses whole horizontal rails to zero height. Mirror SduiRenderer's own size logic
// (fixed → fill → implicit) so fixed-size children keep their size. A delegate that sets
// `width`/anchors explicitly still overrides these defaults.
import QtQuick 2.6

Loader {
    id: shim
    property var node
    property var ctx

    source: Qt.resolvedUrl("SduiRenderer.qml")

    onLoaded: {
        item.node = Qt.binding(function () { return shim.node })
        item.ctx = Qt.binding(function () { return shim.ctx })
    }

    width:  item ? (item._fixedW >= 0 ? item._fixedW
                   : (item._fillW && shim.parent ? shim.parent.width : item.implicitWidth)) : 0
    height: item ? (item._fixedH >= 0 ? item._fixedH : item.implicitHeight) : 0
}
