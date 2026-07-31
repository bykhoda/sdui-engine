// Headless capture harness — the Aurora leg of the visual snapshot suite
// (spec/snapshots). main.cpp loads THIS instead of SduiPlayground.qml when the app is
// launched with `--snapshot <outDir> [scheme]`. It renders every bundled screen through
// the SAME SduiRenderer the app uses, grabs each to a PNG named to the harness convention
// ({fixture}.aurora.{scheme}.png), then quits — no UI navigation, deterministic and
// scriptable, the Aurora analogue of the Android Roborazzi / iOS ImageRenderer legs.
//
// It runs on an Aurora device/emulator (the renderer needs Silica + QtGraphicalEffects,
// which don't exist on a host Qt). See spec/snapshots/capture-aurora.sh.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "sdui"
import "sdui/Tokens.js" as T

ApplicationWindow {
    id: win

    // Injected by main.cpp via context properties (with safe fallbacks for a bare run).
    property string outDir: (typeof snapshotOutDir !== "undefined" && snapshotOutDir) ? snapshotOutDir : "/tmp/sdui-snap"
    property string scheme: (typeof snapshotScheme !== "undefined" && snapshotScheme) ? snapshotScheme : "light"

    // Fixed phone viewport so Aurora columns line up with iOS/Android in the glued sheets.
    readonly property int vpW: 1080
    readonly property int vpH: 2340

    property var tokens: ({})
    property var screens: []   // [{ id, content, state }]
    property int _i: -1

    Component.onCompleted: _load()

    // Same XHR/JSON pattern as SduiPlayground.qml — read a bundled qrc resource.
    function _readJson(url, cb) {
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

    // Load tokens, then every screen listed in the bundled manifest (+ the home screen,
    // which lives outside the screens/ list), preserving order, then start grabbing.
    function _load() {
        _readJson("qrc:/content/tokens.json", function (t) {
            win.tokens = t ? t : {};
            _readJson("qrc:/content/manifest.json", function (m) {
                var list = (m && m.screens) ? m.screens.slice() : [];
                list.unshift("content/screens/home.json");
                var acc = [];
                var remaining = list.length;
                if (remaining === 0) { _finish(); return; }
                for (var i = 0; i < list.length; i++) {
                    (function (path) {
                        _readJson("qrc:/" + path, function (doc) {
                            var s = (doc && doc.screen) ? doc.screen : null;
                            if (s && s.id) acc.push({ id: s.id, content: s.content, state: s.state ? s.state : {} });
                            if (--remaining === 0) { win.screens = acc; _next(); }
                        });
                    })(list[i]);
                }
            });
        });
    }

    // A render context matching ScreenPage's — read-only here (no dispatch/state writes
    // are needed for a static capture). `env.theme` carries the scheme so token colours
    // resolve light/dark exactly as they do in the running app.
    function _ctxFor(s) {
        return {
            tokens: win.tokens,
            state: s && s.state ? s.state : {},
            data: {},
            env: { locale: "en", theme: win.scheme, platform: "aurora" },
            item: null,
            dispatch: function () {},
            setState: function () {},
            getState: function () { return undefined; }
        };
    }

    // The offscreen stage the renderer draws into; grabbed once per screen. Sized to the
    // fixed viewport regardless of the device window so every sheet is the same shape.
    Rectangle {
        id: stage
        width: win.vpW
        height: win.vpH
        color: win.scheme === "dark" ? "#000000" : "#ffffff"
        SduiRenderer {
            id: renderer
            anchors.fill: parent
            node: null
            ctx: ({})
        }
    }

    function _next() {
        win._i += 1;
        if (win._i >= win.screens.length) { _finish(); return; }
        var s = win.screens[win._i];
        renderer.node = s.content ? s.content : null;
        renderer.ctx = _ctxFor(s);
        grabTimer.restart(); // let the scene graph settle one tick, then capture
    }

    // grabToImage renders the item's own layer to a texture (independent of what the device
    // window shows), so a fixed-size offscreen grab is reliable on the emulator.
    Timer {
        id: grabTimer
        interval: 150
        repeat: false
        onTriggered: {
            var s = win.screens[win._i];
            var path = win.outDir + "/" + s.id + ".aurora." + win.scheme + ".png";
            stage.grabToImage(function (result) {
                if (result) result.saveToFile(path);
                win._next();
            }, Qt.size(win.vpW, win.vpH));
        }
    }

    function _finish() {
        console.log("[SDUI-SNAP] captured " + win.screens.length + " screen(s) -> " + win.outDir);
        Qt.quit();
    }
}
