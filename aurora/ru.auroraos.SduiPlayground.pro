# qmake project for the Aurora OS SDUI Playground.
# Build with the Aurora SDK (sfdk/mb2) — see README.md. Qt 5.6 / Silica.
TARGET = ru.auroraos.SduiPlayground

CONFIG += auroraapp          # Aurora launch API (libauroraapp); NOT sailfishapp

QT += quick

SOURCES += src/main.cpp

# Shared playground content (catalog + screens + tokens) compiled into the binary
# via aliases pointing at the ONE authored copy under ios/. Regenerate after
# adding screens: `sh tools/gen_qrc.sh`.
RESOURCES += resources.qrc

DISTFILES += \
    rpm/ru.auroraos.SduiPlayground.spec \
    ru.auroraos.SduiPlayground.desktop \
    qml/SduiPlayground.qml \
    qml/cover/DefaultCover.qml \
    qml/pages/ScreenPage.qml \
    qml/sdui/SduiRenderer.qml \
    qml/sdui/Tokens.js

# Deploy the QML tree to the app data dir so `Aurora::Application::pathTo(
# "qml/SduiPlayground.qml")` (src/main.cpp) resolves at runtime. Without this the
# QML is only listed under DISTFILES (which installs nothing) and the view never
# loads. Datadir = /usr/share/$${TARGET}; pathTo() is rooted there.
qml.files = qml
qml.path  = /usr/share/$${TARGET}
INSTALLS += qml

# The .desktop launcher entry (auroraapp usually handles this, but make it explicit).
desktop.files = ru.auroraos.SduiPlayground.desktop
desktop.path  = /usr/share/applications
INSTALLS += desktop

# TODO: add launcher icons under icons/<size>/ru.auroraos.SduiPlayground.png and
# re-enable:  AURORAAPP_ICONS = 86x86 108x108 128x128 172x172
# TODO: add translations/ and re-enable TRANSLATIONS once lupdate has run.
