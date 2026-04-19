#pragma once

#include <QObject>
#include <QMqttClient>
#include <QMqttTopicFilter>
#include <QMqttTopicName>

// MqttHelper wraps QMqttClient and exposes two signals to QML:
//   - messageReceived(payload, topic)
//   - connectedChanged(bool)
//
// It is registered in main.cpp as a QML context property named "mqttHelper".
// Main.qml uses a Connections block to handle these signals without needing
// the QtMqtt QML plugin (which is not distributed for Linux ARM64).

class MqttHelper : public QObject
{
    Q_OBJECT

public:
    explicit MqttHelper(QObject *parent = nullptr) : QObject(parent)
    {
        m_client.setHostname("127.0.0.1");
        m_client.setPort(1883);
        m_client.setClientId("anomaly-detector-ui");

        // Subscribe to wildcard topic once connected.
        connect(&m_client, &QMqttClient::connected, this, [this]() {
            m_client.subscribe(QMqttTopicFilter("home/anomaly/#"), 1);
            emit connectedChanged(true);
        });

        connect(&m_client, &QMqttClient::disconnected, this, [this]() {
            emit connectedChanged(false);
        });

        // Forward incoming messages to QML as plain strings.
        connect(&m_client, &QMqttClient::messageReceived,
                this, [this](const QByteArray &message, const QMqttTopicName &topic) {
            emit messageReceived(QString::fromUtf8(message), topic.name());
        });
    }

    // Called from QML via reconnectTimer and on startup.
    Q_INVOKABLE void connectToHost()
    {
        m_client.connectToHost();
    }

signals:
    void messageReceived(const QString &payload, const QString &topic);
    void connectedChanged(bool connected);

private:
    QMqttClient m_client;
};
