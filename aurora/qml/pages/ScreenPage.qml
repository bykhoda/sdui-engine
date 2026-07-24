// Renders one server-driven screen through the SDUI renderer — the Aurora
// sibling of iOS SDUIScreenView / Android SduiScreen. It owns the scroll surface;
// the screen's root component flows inside it.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "../sdui"

Page {
    id: page
    allowedOrientations: Orientation.All

    property var screenDoc              // the parsed { version, screen } document
    property var tokens: ({})

    property var _screen: screenDoc ? screenDoc.screen : null
    property var _ctx: ({
        tokens: tokens ? tokens : {},
        state: (_screen && _screen.state) ? _screen.state : {},
        data: {},
        env: { locale: "en", theme: "light", platform: "aurora" },
        item: null
    })

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            PageHeader {
                title: (page._screen && page._screen.title) ? page._screen.title : ""
            }

            SduiRenderer {
                width: parent.width
                node: page._screen ? page._screen.content : null
                ctx: page._ctx
            }
        }
        VerticalScrollDecorator {}
    }
}
