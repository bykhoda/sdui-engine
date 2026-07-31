// Aurora OS entry point for the SDUI Playground — the Aurora sibling of
// ios/Examples/DemoApp and android/app. It boots a Silica QQuickView and hands
// control to qml/SduiPlayground.qml, which renders the SAME server-driven JSON
// contract as the other two platforms. All rendering lives in QML (see
// qml/sdui/SduiRenderer.qml); no native model is needed for this demo.
#include <auroraapp.h>
#include <QtQuick>
#include <QQmlContext>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> application(Aurora::Application::application(argc, argv));
    application->setOrganizationName(QStringLiteral("ru.auroraos"));
    application->setApplicationName(QStringLiteral("SduiPlayground"));

    QScopedPointer<QQuickView> view(Aurora::Application::createView());

    // Headless snapshot leg (spec/snapshots): `--snapshot <outDir> [light|dark]` loads the
    // capture harness instead of the app — it renders every bundled screen through the same
    // renderer, writes {fixture}.aurora.{scheme}.png, and quits. See capture-aurora.sh.
    const QStringList args = application->arguments();
    const int si = args.indexOf(QStringLiteral("--snapshot"));
    if (si >= 0) {
        const QString outDir = (si + 1 < args.size()) ? args.at(si + 1) : QStringLiteral("/tmp/sdui-snap");
        const QString scheme = (si + 2 < args.size()) ? args.at(si + 2) : QStringLiteral("light");
        view->rootContext()->setContextProperty(QStringLiteral("snapshotOutDir"), outDir);
        view->rootContext()->setContextProperty(QStringLiteral("snapshotScheme"), scheme);
        view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/Snapshotter.qml")));
    } else {
        view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/SduiPlayground.qml")));
    }
    view->show();

    return application->exec();
}
