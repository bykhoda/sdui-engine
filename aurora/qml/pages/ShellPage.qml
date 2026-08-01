// The app's root shell — a persistent bottom tab bar (Home · Browse · Design · Settings) over the
// active screen, the Aurora sibling of the iOS TabView / Android bottom NavigationBar. Tapping a tab
// switches the shown screen in place; card taps still `dispatch` a push onto the page stack (the
// detail covers the bar, as Silica pushes do). Reuses the same SduiRenderer + state/ctx machinery as
// ScreenPage so a tab's screen behaves identically to a pushed one.
import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."
import "../sdui"
import "../sdui/Tokens.js" as T

Page {
    id: page
    allowedOrientations: Orientation.All

    property var tokens: ({})
    property var screensById: ({})
    property var dispatch

    // Tab → screen id. Browse points at the discover store-home for now (a full flat catalog screen
    // is a follow-up); Design → the Figma/tokens screen; Settings → the settings screen.
    property var tabScreens: ["home", "discover", "figma", "settings"]
    property int currentTab: 0
    property string screenId: tabScreens[currentTab]

    property var _doc: screensById[screenId]
    property var _screen: _doc ? _doc.screen : null

    // Mutable per-screen state, re-seeded when the tab (screen) changes.
    property var _state: page._seedState(_screen)
    onScreenIdChanged: page._state = page._seedState(_screen)

    property var _ctx: ({
        tokens: tokens ? tokens : {},
        state: _state,
        data: {},
        env: { locale: "en", theme: "light", platform: "aurora" },
        item: null,
        dispatch: function (action) { if (page.dispatch) page.dispatch(action, page); },
        setState: function (key, value) { page.setStateValue(key, value); },
        getState: function (key) { return page.stateValue(key); }
    })

    function _seedState(scr) {
        var out = {}; var src = (scr && scr.state) ? scr.state : null;
        if (src) { for (var k in src) out[k] = src[k]; }
        return out;
    }
    function stateValue(key) {
        var bare = (typeof key === "string" && key.indexOf("$state.") === 0) ? key.substring(7) : key;
        return page._state ? page._state[bare] : undefined;
    }
    function setStateValue(key, value) {
        var bare = (typeof key === "string" && key.indexOf("$state.") === 0) ? key.substring(7) : key;
        var next = {}; var cur = page._state ? page._state : {};
        for (var k in cur) next[k] = cur[k];
        next[bare] = value;
        page._state = next;
    }
    property string scrollTarget: ""
    function scrollToId(id) {
        page.scrollTarget = id ? id : "";
        if (id === "top") flick.scrollToTop();
        else if (id === "bottom") flick.scrollToBottom();
    }

    Rectangle {
        anchors.fill: parent
        color: T.color("$token.color.surface", page._ctx, "#F4F4F7")
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        // Extra bottom room so the last content clears the floating tab bar.
        contentHeight: content.height + tabbar.height + Theme.paddingLarge

        Column {
            id: content
            width: parent.width
            SduiRenderer {
                width: parent.width
                node: page._screen ? page._screen.content : null
                ctx: page._ctx
            }
        }
        VerticalScrollDecorator {}
    }

    TabBar {
        id: tabbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        current: page.currentTab
        onSelected: page.currentTab = index
    }
}
