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

    // Client-local, MUTABLE screen state. Seeded once from `screen.state`
    // (cloned, so the source doc is never mutated) and thereafter owned here.
    // A setState/increment reassigns `_state` WHOLESALE — reassigning the
    // property is what QML observes, so the `_ctx` binding below re-evaluates,
    // a fresh ctx flows to the SduiRenderer, and every $state-bound label/color
    // re-resolves. This is the idiomatic Qt5/QML way to make a JS map reactive
    // (mutating a nested key in place would NOT trigger bindings).
    property var _state: page._seedState(_screen)

    // The render context. Because it READS `_state`, QML makes it depend on it;
    // when `_state` is reassigned the whole ctx object is rebuilt and pushed to
    // the renderer. `dispatch` is a thin per-page closure that hands the action
    // and THIS page (as the state/scroll host) to the central action runtime,
    // so the runtime mutates the right screen's state. The signature the
    // renderer calls — ctx.dispatch(action) — is unchanged.
    property var _ctx: ({
        tokens: tokens ? tokens : {},
        state: _state,
        data: {},
        env: { locale: "en", theme: "light", platform: "aurora" },
        item: null,
        dispatch: function (action) { if (page.dispatch) page.dispatch(action, page); },
        // Direct, continuous state hooks for two-way controls (slider drag, the
        // ticker heartbeat). They route straight to THIS page's mutable state so
        // the same $state a label/color/binding reads is written back — the
        // Aurora counterpart of iOS `ctx.doubleBinding(key)`. A key may carry a
        // leading "$state." (setStateValue normalizes it away).
        setState: function (key, value) { page.setStateValue(key, value); },
        getState: function (key) { return page.stateValue(key); }
    })

    // Shallow-clone the authored initial state so it becomes our own mutable map.
    function _seedState(scr) {
        var out = {};
        var src = (scr && scr.state) ? scr.state : null;
        if (src) { for (var k in src) out[k] = src[k]; }
        return out;
    }

    // Read one state value (bare key or a "$state.x" ref) — used by `increment`.
    function stateValue(key) {
        var bare = (typeof key === "string" && key.indexOf("$state.") === 0) ? key.substring(7) : key;
        return page._state ? page._state[bare] : undefined;
    }

    // Write one state value and re-render. `key` may carry a leading "$state."
    // which we normalize away (same as iOS/Android). We build a NEW map and
    // reassign `_state` wholesale so the ctx binding fires.
    function setStateValue(key, value) {
        var bare = (typeof key === "string" && key.indexOf("$state.") === 0) ? key.substring(7) : key;
        var next = {};
        var cur = page._state ? page._state : {};
        for (var k in cur) next[k] = cur[k];
        next[bare] = value;
        page._state = next;
    }

    // Target for a `scrollTo` action. The runtime sets this to a component id;
    // the flickable consumes it below (best-effort: an id→offset map would need
    // the renderer to register child positions, which is future work — so for
    // now we record the request and, for the sentinel ids "top"/"bottom", move
    // the surface, which covers the common "scroll to top after refresh" case).
    property string scrollTarget: ""
    function scrollToId(id) {
        page.scrollTarget = id ? id : "";
        if (id === "top") flick.scrollToTop();
        else if (id === "bottom") flick.scrollToBottom();
    }

    SilicaFlickable {
        id: flick
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
