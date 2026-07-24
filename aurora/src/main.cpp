// Aurora OS entry point for the SDUI Playground — the Aurora sibling of
// ios/Examples/DemoApp and android/app. It boots a Silica QQuickView and hands
// control to qml/SduiPlayground.qml, which renders the SAME server-driven JSON
// contract as the other two platforms. All rendering lives in QML (see
// qml/sdui/SduiRenderer.qml); no native model is needed for this demo.
#include <auroraapp.h>
#include <QtQuick>

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> application(Aurora::Application::application(argc, argv));
    application->setOrganizationName(QStringLiteral("ru.auroraos"));
    application->setApplicationName(QStringLiteral("SduiPlayground"));

    QScopedPointer<QQuickView> view(Aurora::Application::createView());
    view->setSource(Aurora::Application::pathTo(QStringLiteral("qml/SduiPlayground.qml")));
    view->show();

    return application->exec();
}
