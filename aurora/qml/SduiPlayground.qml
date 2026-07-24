// Root application window — the Aurora sibling of iOS SDUIHomeView / Android
// PlaygroundApp. Loads the shared bundled content (catalog is now the SDUI `home`
// screen), then renders it through the engine, so Aurora shows the same premium
// home as iOS/Android. `dispatch` drives server-driven navigation.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow {
    id: win

    property var tokens: ({})
    property var screensById: ({})

    Component.onCompleted: loadAll()

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
        readJson("qrc:/content/tokens.json", function (t) { win.tokens = t ? t : {}; });
        readJson("qrc:/content/manifest.json", function (m) {
            var list = (m && m.screens) ? m.screens : [];
            var acc = {};
            var remaining = list.length + 1;
            function done() { remaining -= 1; if (remaining === 0) win.screensById = acc; }
            // The home/catalog screen (not in the screens/ manifest).
            readJson("qrc:/content/screens/home.json", function (doc) {
                if (doc && doc.screen && doc.screen.id) acc[doc.screen.id] = doc;
                done();
            });
            for (var i = 0; i < list.length; i++) {
                readJson("qrc:/" + list[i], function (doc) {
                    if (doc && doc.screen && doc.screen.id) acc[doc.screen.id] = doc;
                    done();
                });
            }
            if (list.length === 0) done();
        });
    }

    // Server-driven action dispatch. Navigate pushes another screen; the rest
    // degrade gracefully for now (Aurora action runtime is still growing).
    function dispatch(action) {
        if (!action) return;
        if (action.action === "sequence" && action.actions) {
            for (var i = 0; i < action.actions.length; i++) win.dispatch(action.actions[i]);
            return;
        }
        if (action.action === "navigate" && action.to && win.screensById[action.to]) {
            pageStack.push(Qt.resolvedUrl("pages/ScreenPage.qml"),
                { screenId: action.to, tokens: win.tokens, screensById: win.screensById, dispatch: win.dispatch });
        }
        // custom (stories) / setState / haptic ... : TODO as the runtime grows.
    }

    initialPage: Component {
        ScreenPage {
            screenId: "home"
            tokens: win.tokens
            screensById: win.screensById
            dispatch: win.dispatch
        }
    }

    cover: Qt.resolvedUrl("cover/DefaultCover.qml")
    allowedOrientations: defaultAllowedOrientations
}
