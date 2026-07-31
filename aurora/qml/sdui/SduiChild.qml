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
// It forwards `node`/`ctx` to the loaded renderer; a Loader already mirrors its item's
// implicit size (implicitWidth/implicitHeight are read-only and track the item), so parent
// Column/Row/Grid lay the child out. width/anchors set by the delegate apply to the Loader
// (an Item), which resizes the loaded renderer to fill.
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
}
