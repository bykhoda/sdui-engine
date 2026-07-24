// Root application window — the Aurora sibling of iOS DemoApp / Android MainActivity.
import QtQuick 2.6
import Sailfish.Silica 1.0

ApplicationWindow {
    initialPage: Qt.resolvedUrl("pages/CatalogPage.qml")
    cover: Qt.resolvedUrl("cover/DefaultCover.qml")
    allowedOrientations: defaultAllowedOrientations
}
