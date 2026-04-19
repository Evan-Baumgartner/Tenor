#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStringLiteral>
#include "MqttHelper.h"

using namespace Qt::StringLiterals;

int main(int argc, char *argv[])
{
    // Use OpenGL RHI backend — safe default for Pi with Mesa/V3D drivers.
    // Override at runtime with: export QSG_RHI_BACKEND=software
    qputenv("QSG_RHI_BACKEND", "opengl");

    QGuiApplication app(argc, argv);
    app.setApplicationName("Home Anomaly Detector");
    app.setOrganizationName("HomeAutomation");

    // Create the MQTT helper and connect immediately.
    MqttHelper mqttHelper;
    mqttHelper.connectToHost();

    QQmlApplicationEngine engine;

    // Expose mqttHelper to QML as a named context property.
    // Main.qml accesses it via: Connections { target: mqttHelper }
    engine.rootContext()->setContextProperty("mqttHelper", &mqttHelper);

    const QUrl url(u"qrc:/AnomalyDetector/Main.qml"_s);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection
    );

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical("Failed to load Main.qml — check QML syntax and imports.");
        return -1;
    }

    return app.exec();
}
