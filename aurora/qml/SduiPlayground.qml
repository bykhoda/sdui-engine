// Root application window — the Aurora sibling of iOS SDUIHomeView / Android
// PlaygroundApp. Loads the shared bundled content (catalog is now the SDUI `home`
// screen), then renders it through the engine, so Aurora shows the same premium
// home as iOS/Android. `dispatch` drives server-driven navigation.
import QtQuick 2.6
import Sailfish.Silica 1.0
import "pages"
import "sdui/Tokens.js" as T

ApplicationWindow {
    id: win

    property var tokens: ({})
    property var screensById: ({})

    // Host-observable hook for `custom` actions (stories, etc.). A host embedding
    // the engine can connect to this signal; unconnected it's a clean no-op.
    signal customAction(string name, var payload)

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

    // ================= Action runtime =================
    // The Aurora counterpart of iOS ActionInterpreter.swift / Android
    // ActionInterpreter.kt. It owns control flow (sequence / parallel /
    // condition / delay) and performs the leaf side effects itself (there is no
    // separate "host" object on Aurora — the window IS the host). `host` is the
    // ScreenPage that owns the mutable state + scroll surface for the action;
    // state writes are routed to it so the correct screen re-renders. `host`
    // defaults to the current page so any legacy one-arg call still works.
    //
    // Field reads mirror the reference engines: string fields are binding-
    // resolved through Tokens.js against the host's render context; `setState`
    // values pass through unless they're a binding string. Verbs that need
    // infrastructure Aurora doesn't have yet (data layer, share/transfer plugin,
    // native permissions) are clean, clearly-commented stubs — never crashes.
    function dispatch(action, host) {
        if (!action) return;
        if (!host) host = pageStack.currentPage;
        var ctx = (host && host._ctx) ? host._ctx : { tokens: win.tokens, state: {}, data: {}, env: {}, item: null };

        // Fire any attached analytics tag first (parity with iOS/Android).
        if (action.analytics) win._track(action.analytics);

        var kind = action.action;

        if (kind === "sequence") {
            // Stepwise so an embedded `delay` can pause the sequence and resume
            // the remainder asynchronously — matching the await-in-order
            // semantics of the reference engines.
            win._runSequence(action.actions ? action.actions : [], 0, host);
            return;
        }

        if (kind === "parallel") {
            // Leaf actions touch UI/navigation state; as on iOS/Android we simply
            // run each in order (genuine concurrency belongs to the data layer).
            var pa = action.actions ? action.actions : [];
            for (var i = 0; i < pa.length; i++) win.dispatch(pa[i], host);
            return;
        }

        if (kind === "condition") {
            if (T.evalCondition(action["if"], ctx)) {
                if (action.then) win.dispatch(action.then, host);
            } else if (action["else"]) {
                win.dispatch(action["else"], host);
            }
            return;
        }

        if (kind === "delay") {
            // A lone delay has nothing to resume (there is no inner action in the
            // contract); it is meaningful only inside a `sequence`, handled there.
            return;
        }

        if (kind === "navigate") {
            var to = T.str(action.to, ctx);
            if (to && win.screensById[to]) {
                var props = { screenId: to, tokens: win.tokens,
                              screensById: win.screensById, dispatch: win.dispatch };
                if (action.transition === "replace" && pageStack.currentPage) {
                    pageStack.replace(Qt.resolvedUrl("pages/ScreenPage.qml"), props);
                } else {
                    // push / sheet / fullScreenCover all map to a Silica push.
                    pageStack.push(Qt.resolvedUrl("pages/ScreenPage.qml"), props);
                }
            } else {
                win._log("navigate: unknown screen '" + to + "'");
            }
            return;
        }

        if (kind === "dismiss") {
            if (pageStack.depth > 1) pageStack.pop();
            return;
        }

        if (kind === "dismissRoot") {
            pageStack.pop(null); // Silica: pop to the root page
            return;
        }

        if (kind === "openURL" || kind === "openDeepLink") {
            var url = T.str(action.url, ctx);
            if (url) Qt.openUrlExternally(url);
            return;
        }

        if (kind === "setState") {
            if (host && host.setStateValue && action.key !== undefined) {
                var v = action.value;
                if (typeof v === "string") v = T.resolve(v, ctx); // resolve bindings
                host.setStateValue(action.key, v);
            }
            return;
        }

        if (kind === "increment") {
            // Add `by` (default 1) to a numeric state key, then clamp to the
            // optional [min, max] range. Powers steppers / "load more" without
            // arithmetic in the payload. (`by` matches iOS/Android; min/max are a
            // superset the schema leaves open.)
            if (host && host.setStateValue && action.key !== undefined) {
                var by = (action.by !== undefined) ? Number(action.by) : 1;
                if (isNaN(by)) by = 1;
                var raw = host.stateValue ? host.stateValue(action.key) : undefined;
                var cur = Number(raw);
                if (isNaN(cur)) cur = 0;
                var nextVal = cur + by;
                if (action.min !== undefined && nextVal < Number(action.min)) nextVal = Number(action.min);
                if (action.max !== undefined && nextVal > Number(action.max)) nextVal = Number(action.max);
                host.setStateValue(action.key, nextVal);
            }
            return;
        }

        if (kind === "showToast") {
            win._showToast(T.str(action.message, ctx), action.style ? action.style : "info");
            return;
        }

        if (kind === "scrollTo") {
            if (host && host.scrollToId) host.scrollToId(T.str(action.target, ctx));
            return;
        }

        if (kind === "share") {
            // Best-effort: Aurora's share needs the transfer-engine (ShareAction)
            // plugin, which isn't wired here — so we compose the payload and log
            // it. A host can override by connecting to `customAction`.
            var stext = action.text !== undefined ? T.str(action.text, ctx) : "";
            var surl = action.url !== undefined ? T.str(action.url, ctx) : "";
            win._log("share: " + (stext + (stext && surl ? " " : "") + surl));
            return;
        }

        if (kind === "haptic") {
            // Aurora haptics (ngfd / MCE) aren't exposed to QML here. Intentional
            // no-op stub; wire to a NonGraphicalFeedback effect when available.
            return;
        }

        if (kind === "refresh") {
            // The data layer ($data sources) isn't wired into the Aurora renderer
            // yet (ctx.data is always {}), so there is nothing to re-pull. Clean
            // stub — logs the requested sources for parity/observability.
            var srcs = action.sources ? action.sources : [];
            win._log("refresh: [" + srcs.join(", ") + "] (data layer not wired)");
            return;
        }

        if (kind === "log") {
            win._log(T.str(action.message, ctx));
            return;
        }

        if (kind === "analytics") {
            // Already emitted above via action.analytics.
            return;
        }

        if (kind === "custom") {
            if (action.name) win.customAction(action.name, action.payload !== undefined ? action.payload : null);
            return;
        }

        // request / saveFile / preview / requireVersion / requestPermission:
        // unimplemented on Aurora (as on Android for several of these). They need
        // the data layer, file APIs, QuickLook-equivalent, store routing or native
        // permission plumbing — none available here. Log and move on, never crash.
        win._log("Unhandled action '" + kind + "'");
    }

    // Run actions[i..] in order; if a positive `delay` is hit, schedule the
    // remainder after that pause and return (async continuation).
    function _runSequence(actions, i, host) {
        for (; i < actions.length; i++) {
            var a = actions[i];
            if (a && a.action === "delay") {
                var secs = Number(a.seconds);
                if (isNaN(secs)) secs = 0;
                if (secs > 0) {
                    var rest = i + 1;
                    win._after(Math.min(secs, 60) * 1000, function () {
                        win._runSequence(actions, rest, host);
                    });
                    return; // paused; resumes in the timer callback
                }
                continue; // zero/absent delay: nothing to wait for
            }
            win.dispatch(a, host);
        }
    }

    // One-shot timer helper. Creates a Timer, runs `fn` once, then self-destroys.
    function _after(ms, fn) {
        var t = timerComponent.createObject(win, { interval: ms, repeat: false, running: false });
        if (!t) { fn(); return; } // if creation fails, run immediately (safe fallback)
        t.triggered.connect(function () { fn(); t.destroy(); });
        t.start();
    }

    function _log(msg) { console.log("[SDUI] " + msg); }

    function _track(tag) {
        // Analytics sink: no backend wired on Aurora — log the event for parity.
        var ev = (tag && tag.event) ? tag.event : "";
        win._log("analytics: " + ev);
    }

    function _showToast(message, style) {
        if (!message) return;
        win._log("toast(" + style + "): " + message); // always-on feedback
        toast.show(message, style);
    }

    // Reusable one-shot Timer for `delay` / async continuations.
    Component { id: timerComponent; Timer {} }

    // Lightweight, self-contained toast banner — the simplest Silica-native
    // transient surface that needs no external module (a system Notification or
    // transfer-plugin share would). Overlays the page stack (high z), fades in,
    // holds, then fades out. Colour follows the info/success/error style.
    Rectangle {
        id: toast
        z: 10000
        radius: Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent ? parent.height - height - Theme.paddingLarge * 3 : 0
        width: Math.min(toastLabel.implicitWidth + Theme.paddingLarge * 2,
                        (parent ? parent.width : 600) - Theme.paddingLarge * 2)
        height: toastLabel.implicitHeight + Theme.paddingMedium * 2
        opacity: 0
        visible: opacity > 0
        color: toast._styleColor

        property string _style: "info"
        property color _styleColor: _style === "success" ? "#2E7D32"
                                  : _style === "error" ? "#C0392B" : "#323232"

        Label {
            id: toastLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, (toast.parent ? toast.parent.width : 600) - Theme.paddingLarge * 4)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.pixelSize: Theme.fontSizeSmall
        }

        function show(message, style) {
            toast._style = style ? style : "info";
            toastLabel.text = message ? message : "";
            toastAnim.restart();
        }

        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 0.96; duration: 180; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 2200 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InQuad }
        }
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
