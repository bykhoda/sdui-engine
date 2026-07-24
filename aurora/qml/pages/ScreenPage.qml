// Renders one server-driven screen (by id) through the SDUI renderer — the
// Aurora sibling of iOS SDUIScreenView / Android SduiScreen. It owns the scroll
// surface; the screen's root component flows inside it. `dispatch` (threaded into
// the render context) drives navigation from taps.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "../sdui"

Page {
    id: page
    allowedOrientations: Orientation.All

    property string screenId: ""
    property var tokens: ({})
    property var screensById: ({})
    property var dispatch

    property var _doc: screensById[screenId]
    property var _screen: _doc ? _doc.screen : null
    property var _ctx: ({
        tokens: tokens ? tokens : {},
        state: (_screen && _screen.state) ? _screen.state : {},
        data: {},
        env: { locale: "en", theme: "light", platform: "aurora" },
        item: null,
        dispatch: page.dispatch
    })

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width

            // A page header (with the built-in back) only for pushed detail
            // screens that carry a title; the home draws its own header.
            Loader {
                width: parent.width
                active: page._screen && page._screen.title ? true : false
                sourceComponent: Component { PageHeader { title: page._screen ? page._screen.title : "" } }
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
