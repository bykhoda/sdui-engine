// The catalog browser — the Aurora sibling of iOS CatalogNavigation / Android
// CatalogList. Loads the SAME bundled catalog + screens + tokens (from the QRC
// aliased at build time onto the shared iOS Content), and pushes a ScreenPage
// rendering the selected screen through SduiRenderer.
import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property var tokens: ({})
    property var screensById: ({})
    property var categories: []

    Component.onCompleted: loadAll()

    // Reads a bundled JSON resource and hands the parsed object to `cb` (or null
    // on malformed input — never throws into the UI).
    function readJson(url, cb) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var parsed = null;
                try { parsed = JSON.parse(xhr.responseText); } catch (e) { parsed = null; }
                cb(parsed);
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function loadAll() {
        readJson("qrc:/content/tokens.json", function (t) { page.tokens = t ? t : {}; });
        readJson("qrc:/content/catalog.json", function (c) {
            page.categories = (c && c.categories) ? c.categories : [];
        });
        readJson("qrc:/content/manifest.json", function (m) {
            var list = (m && m.screens) ? m.screens : [];
            var acc = {};
            var remaining = list.length;
            if (remaining === 0) { page.screensById = acc; return; }
            for (var i = 0; i < list.length; i++) {
                readJson("qrc:/" + list[i], function (doc) {
                    if (doc && doc.screen && doc.screen.id) acc[doc.screen.id] = doc;
                    remaining = remaining - 1;
                    if (remaining === 0) page.screensById = acc;
                });
            }
        });
    }

    function openScreen(id) {
        var doc = page.screensById[id];
        if (doc) pageStack.push(Qt.resolvedUrl("ScreenPage.qml"),
                                { screenDoc: doc, tokens: page.tokens });
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader { title: qsTr("SDUI Playground") }

            Repeater {
                model: page.categories
                delegate: Column {
                    width: parent.width
                    property var category: modelData
                    SectionHeader { text: category && category.name ? category.name : "" }
                    Repeater {
                        model: (category && category.screens) ? category.screens : []
                        delegate: BackgroundItem {
                            width: parent.width
                            property var entry: modelData
                            onClicked: page.openScreen(entry.id)
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.horizontalPageMargin
                                width: parent.width - 2 * Theme.horizontalPageMargin
                                Label {
                                    text: entry && entry.id ? entry.id : ""
                                    font.pixelSize: Theme.fontSizeMedium
                                }
                                Label {
                                    width: parent.width
                                    text: entry && entry.subtitle ? entry.subtitle : ""
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                    truncationMode: TruncationMode.Fade
                                }
                            }
                        }
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }
}
