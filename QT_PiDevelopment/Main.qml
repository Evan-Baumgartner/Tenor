import QtQuick
import QtQuick.Controls

Window {
    id: root
    visibility: Window.FullScreen
    title: "Home Anomaly Detector"

    property string appState: "idle"
    property var currentAlert: null
    property var pendingAlert: null
    property var alertHistory: []
    property bool alertsDisabled: false
    property int    disableSecondsRemaining: 0
    property string disableResumesAt: ""
    property real   lastAlertTime: 0   // ms since epoch of last triggered alert
    property bool disablePanelOpen: false
    property bool historyPanelOpen: false

    property int  themeIndex: 0
    property int  themeTransitionDuration: 400
    readonly property var themes: [
        {
            name: "Cream",
            bg: "#FAE8C0", surface: "#F0D8A0",
            timeColor: "#1C1A14", dateColor: "#3A3528", subColor: "#9A9070",
            accent: "#1C1A14", accentText: "#FAE8C0",
            disabledBg: "#FFF3DC", disabledBorder: "#C8860A", disabledText: "#8A5C00",
            panelBg: "#F0D8A0", panelText: "#1C1A14",
            panelBtn: "#E2C880", panelBtnHover: "#CEB060", panelBtnText: "#1C1A14",
            hintColor: "#C8A860"
        },
        {
            name: "Navy",
            bg: "#1a1a2e", surface: "#16213e",
            timeColor: "#FAE8C0", dateColor: "#C8B890", subColor: "#666678",
            accent: "#4444AA", accentText: "#FAE8C0",
            disabledBg: "#1a1400", disabledBorder: "#FFA500", disabledText: "#FFA500",
            panelBg: "#16213e", panelText: "#FAE8C0",
            panelBtn: "#22224a", panelBtnHover: "#2a2a5a", panelBtnText: "#C8B890",
            hintColor: "#333355"
        }
    ]
    readonly property var theme: themes[themeIndex]

    readonly property int dayStartHour:   7
    readonly property int nightStartHour: 20

    function checkDayNight() {
        var h = new Date().getHours();
        var shouldBeDay = (h >= dayStartHour && h < nightStartHour);
        var targetIndex = shouldBeDay ? 0 : 1;
        if (targetIndex !== themeIndex) {
            themeTransitionDuration = 3000;
            themeIndex = targetIndex;
            themeResetTimer.restart();
        }
    }

    Timer {
        id: themeResetTimer
        interval: 3200; repeat: false
        onTriggered: themeTransitionDuration = 400
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: checkDayNight()
    }

    function formatRoomName(nodeId) {
        return nodeId.split("-").map(function(w) {
            return w.charAt(0).toUpperCase() + w.slice(1);
        }).join(" ");
    }

    function appendHistory(alert) {
        var h = alertHistory.slice();
        h.push(alert);
        if (h.length > 10) h.shift();
        alertHistory = h;
    }

    function activateDisable(seconds) {
        disableSecondsRemaining = seconds;
        alertsDisabled = true;
        var resumeDate = new Date(new Date().getTime() + seconds * 1000);
        disableResumesAt = Qt.formatDateTime(resumeDate, "HH:mm");
        disablePanelOpen = false;
        appState = "idle_disabled";
    }

    function reEnableAlerts() {
        alertsDisabled = false;
        disableSecondsRemaining = 0;
        if (appState === "idle_disabled") appState = "idle";
    }

    function handleIncomingAlert(alert) {
        appendHistory(alert);
        if (alertsDisabled) return;

        // Rate limit: discard if within 15 seconds of the last triggered alert.
        var now = Date.now();
        if (now - lastAlertTime < 15000) return;

        if (appState === "idle" || appState === "idle_disabled" || appState === "flashing") {
            lastAlertTime = now;
            currentAlert = alert;
            pendingAlert = null;
            appState = "flashing";
        } else if (appState === "detail") {
            lastAlertTime = now;
            pendingAlert = alert;
            bannerTimer.restart();
        }
    }

    function switchToPendingAlert() {
        if (pendingAlert !== null) {
            currentAlert = pendingAlert;
            pendingAlert = null;
        }
    }

    function dismissAlert() {
        currentAlert = null;
        pendingAlert = null;
        appState = alertsDisabled ? "idle_disabled" : "idle";
    }

    Component.onCompleted: checkDayNight()

    Connections {
        target: mqttHelper

        function onMessageReceived(payload, topic) {
            var obj;
            try { obj = JSON.parse(payload); }
            catch (e) { return; }
            if (!obj.node_id || obj.anomaly_score === undefined) return;
            // Time is taken from the Pi clock at the moment the message arrives.
            var now = new Date();
            handleIncomingAlert({
                nodeId:   obj.node_id,
                roomName: formatRoomName(obj.node_id),
                score:    obj.anomaly_score,
                timeStr:  Qt.formatDateTime(now, "HH:mm:ss"),
                dateStr:  Qt.formatDateTime(now, "dddd, d MMMM yyyy")
            });
        }

        function onConnectedChanged(connected) {
            if (!connected) reconnectTimer.start();
        }
    }

    Timer { id: reconnectTimer; interval: 5000; repeat: false; onTriggered: mqttHelper.connectToHost() }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            var now = new Date();
            var t = Qt.formatDateTime(now, "HH:mm:ss");
            var d = Qt.formatDateTime(now, "dddd, d MMMM yyyy");
            timeLabel.text      = t;
            dateLabel.text      = d;
            flashTimeLabel.text = t;
            flashDateLabel.text = d;
        }
    }

    Timer {
        interval: 1000; running: alertsDisabled; repeat: true
        onTriggered: {
            if (disableSecondsRemaining > 1) disableSecondsRemaining--;
            else reEnableAlerts();
        }
    }

    Timer { id: bannerTimer; interval: 8000; repeat: false; onTriggered: pendingAlert = null }

    // ── Animated root background ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: theme.bg
        Behavior on color { ColorAnimation { duration: themeTransitionDuration; easing.type: Easing.OutCubic } }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SCREEN STATE 2 — RED PULSE
    // ═════════════════════════════════════════════════════════════════════════
    Rectangle {
        id: flashOverlay
        anchors.fill: parent
        visible: appState === "flashing"
        color: "#8B0000"

        SequentialAnimation on color {
            running: flashOverlay.visible
            loops:   Animation.Infinite
            ColorAnimation { to: "#FF0000"; duration: 500; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#8B0000"; duration: 500; easing.type: Easing.InOutSine }
        }

        Text {
            id: flashTimeLabel
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter:   parent.verticalCenter
                verticalCenterOffset: root.height * -0.08
            }
            text: Qt.formatDateTime(new Date(), "HH:mm:ss")
            color: "#5A1A1A"
            font.pixelSize: Math.round(root.height * 0.26)
            font.family: "DejaVu Sans Mono"
            font.weight: Font.Light
        }

        Text {
            id: flashDateLabel
            anchors {
                horizontalCenter: parent.horizontalCenter
                top:              flashTimeLabel.bottom
                topMargin:        root.height * 0.018
            }
            text: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
            color: "#5A1A1A"
            font.pixelSize: Math.round(root.height * 0.062)
            font.family: "DejaVu Sans"
            font.weight: Font.Light
        }

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.10 }
            text: "Tap to view details"
            color: "#5A1A1A"
            font.pixelSize: Math.round(root.height * 0.028)
            font.family: "DejaVu Sans"
            opacity: 0
            SequentialAnimation on opacity {
                running: flashOverlay.visible
                PauseAnimation  { duration: 2000 }
                NumberAnimation { to: 0.80; duration: 800; easing.type: Easing.InOutQuad }
            }
        }

        TapHandler { onTapped: appState = "detail" }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SCREEN STATE 1 — IDLE CLOCK
    // ═════════════════════════════════════════════════════════════════════════
    Item {
        id: idleScreen
        anchors.fill: parent
        visible: appState === "idle" || appState === "idle_disabled"
        clip: true

        // ── History panel (slides in from the LEFT) ───────────────────────────
        Item {
            id: historyPanel
            width: root.width; height: root.height
            x: historyPanelOpen ? 0 : -root.width
            Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.InOutCubic } }

            Rectangle {
                anchors.fill: parent
                color: theme.panelBg
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            // Back button.
            Text {
                id: historyBack
                anchors {
                    right:       parent.right
                    top:         parent.top
                    rightMargin: root.width * 0.05
                    topMargin:   root.height * 0.05
                }
                text: "Back  ›"
                color: theme.subColor
                font.pixelSize: Math.round(root.height * 0.032)
                font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                TapHandler { onTapped: historyPanelOpen = false }
            }

            // Title.
            Text {
                id: historyTitle
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top:              historyBack.bottom
                    topMargin:        root.height * 0.04
                }
                text: "Alert History"
                color: theme.panelText
                font.pixelSize: Math.round(root.height * 0.046)
                font.family: "DejaVu Sans"; font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            // Count badge.
            Text {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top:              historyTitle.bottom
                    topMargin:        root.height * 0.008
                }
                text: alertHistory.length === 0 ? "No alerts recorded" : alertHistory.length + " of 10 slots used"
                color: theme.subColor
                font.pixelSize: Math.round(root.height * 0.026)
                font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            // Divider.
            Rectangle {
                id: historyDivider
                anchors {
                    left:       parent.left;  right:      parent.right
                    top:        historyTitle.bottom
                    topMargin:  root.height * 0.07
                    leftMargin: root.width * 0.06; rightMargin: root.width * 0.06
                }
                height: 1; color: theme.subColor; opacity: 0.25
            }

            // Empty state.
            Text {
                anchors.centerIn: parent
                visible: alertHistory.length === 0
                text: "No alerts yet"
                color: theme.subColor
                font.pixelSize: Math.round(root.height * 0.034)
                font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            // Alert list — most recent first.
            ListView {
                anchors {
                    top:         historyDivider.bottom;  topMargin:    root.height * 0.03
                    left:        parent.left;             right:        parent.right
                    bottom:      parent.bottom;           bottomMargin: root.height * 0.04
                    leftMargin:  root.width * 0.06;       rightMargin:  root.width * 0.06
                }
                visible: alertHistory.length > 0
                model: alertHistory.length
                clip: true
                spacing: root.height * 0.016

                delegate: Rectangle {
                    required property int index
                    readonly property var entry: alertHistory[alertHistory.length - 1 - index]

                    width:  ListView.view.width
                    height: root.height * 0.115
                    radius: 12
                    color:  theme.panelBtn
                    Behavior on color { ColorAnimation { duration: themeTransitionDuration } }

                    Row {
                        anchors { fill: parent; leftMargin: root.width * 0.04; rightMargin: root.width * 0.04 }
                        spacing: root.width * 0.04

                        // Alert icon.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⚠"
                            color: "#CC3300"
                            font.pixelSize: Math.round(root.height * 0.038)
                        }

                        // Room + timestamp.
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.height * 0.008
                            width: parent.width - root.width * 0.22

                            Text {
                                text: entry ? entry.roomName : ""
                                color: theme.panelBtnText
                                font.pixelSize: Math.round(root.height * 0.036)
                                font.family: "DejaVu Sans"; font.weight: Font.Light
                                elide: Text.ElideRight; width: parent.width
                                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                            }
                            Text {
                                text: entry ? entry.dateStr + "  ·  " + entry.timeStr : ""
                                color: theme.subColor
                                font.pixelSize: Math.round(root.height * 0.022)
                                font.family: "DejaVu Sans"
                                elide: Text.ElideRight; width: parent.width
                                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                            }
                        }

                        // Anomaly score bar.
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.height * 0.006

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: entry ? Math.round(entry.score * 10) / 10 : ""
                                color: theme.panelBtnText
                                font.pixelSize: Math.round(root.height * 0.026)
                                font.family: "DejaVu Sans Mono"
                                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                            }
                            Rectangle {
                                width: root.width * 0.08; height: root.height * 0.012; radius: 4
                                color: theme.surface
                                Rectangle {
                                    width: parent.width * (entry ? Math.min(entry.score / 20, 1) : 0)
                                    height: parent.height; radius: 4
                                    color: entry && entry.score > 16 ? "#CC3300"
                                         : entry && entry.score > 12 ? "#CC8800" : "#448844"
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Clock panel ───────────────────────────────────────────────────────
        Item {
            id: clockPanel
            width: root.width; height: root.height
            // Shifts right when history opens, left when disable opens.
            x: historyPanelOpen ? root.width : disablePanelOpen ? -root.width : 0
            Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.InOutCubic } }

            Text {
                id: timeLabel
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: root.height * -0.08 }
                text: Qt.formatDateTime(new Date(), "HH:mm:ss")
                color: theme.timeColor
                font.pixelSize: Math.round(root.height * 0.26)
                font.family: "DejaVu Sans Mono"
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            Text {
                id: dateLabel
                anchors { horizontalCenter: parent.horizontalCenter; top: timeLabel.bottom; topMargin: root.height * 0.018 }
                text: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
                color: theme.dateColor
                font.pixelSize: Math.round(root.height * 0.062)
                font.family: "DejaVu Sans"
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            // Disabled banner.
            Rectangle {
                visible: appState === "idle_disabled"
                anchors { horizontalCenter: parent.horizontalCenter; bottom: reEnableBtn.top; bottomMargin: root.height * 0.02 }
                width: root.width * 0.72
                height: disabledText.implicitHeight + root.height * 0.032
                radius: 12; color: theme.disabledBg
                border.color: theme.disabledBorder; border.width: 1
                Text {
                    id: disabledText
                    anchors.centerIn: parent
                    text: "Alerts disabled — resumes at " + disableResumesAt
                    color: theme.disabledText
                    font.pixelSize: Math.round(root.height * 0.030)
                    font.family: "DejaVu Sans"; font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    width: parent.width - root.width * 0.06
                }
            }

            Rectangle {
                id: reEnableBtn
                visible: appState === "idle_disabled"
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.height * 0.08 }
                width: root.width * 0.38; height: root.height * 0.075; radius: 10
                color: reEnableHover.containsMouse ? theme.accent : theme.surface
                border.color: theme.accent; border.width: 2
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "Re-enable now"
                    color: reEnableHover.containsMouse ? theme.accentText : theme.accent
                    font.pixelSize: Math.round(root.height * 0.028)
                    font.family: "DejaVu Sans"; font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                HoverHandler { id: reEnableHover }
                TapHandler { onTapped: reEnableAlerts() }
            }

            // Swipe hint arrows — left hints at history, right hints at disable panel.
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: root.width * 0.018 }
                text: "‹"; color: theme.hintColor
                font.pixelSize: Math.round(root.height * 0.06); font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: root.width * 0.018 }
                text: "›"; color: theme.hintColor
                font.pixelSize: Math.round(root.height * 0.06); font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }
        }

        // ── Disable-duration panel (slides in from the RIGHT) ─────────────────
        Item {
            id: disablePanel
            width: root.width; height: root.height
            x: disablePanelOpen ? 0 : root.width
            Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.InOutCubic } }

            Rectangle { anchors.fill: parent; color: theme.panelBg; Behavior on color { ColorAnimation { duration: themeTransitionDuration } } }

            Text {
                id: panelBack
                anchors { left: parent.left; top: parent.top; leftMargin: root.width * 0.05; topMargin: root.height * 0.05 }
                text: "‹  Back"; color: theme.subColor
                font.pixelSize: Math.round(root.height * 0.032); font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                TapHandler { onTapped: disablePanelOpen = false }
            }

            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: panelBack.bottom; topMargin: root.height * 0.04 }
                text: "Disable alerts for…"; color: theme.panelText
                font.pixelSize: Math.round(root.height * 0.046); font.family: "DejaVu Sans"; font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            Column {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: root.height * 0.28 }
                spacing: root.height * 0.028
                width: Math.min(root.width * 0.72, 500)

                Repeater {
                    model: [
                        { label: "15 minutes", seconds: 900  },
                        { label: "30 minutes", seconds: 1800 },
                        { label: "1 hour",     seconds: 3600 },
                        { label: "2 hours",    seconds: 7200 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width; height: root.height * 0.115; radius: 14
                        color: dBtnHover.containsMouse ? theme.panelBtnHover : theme.panelBtn
                        border.color: theme.accent; border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent; text: modelData.label; color: theme.panelBtnText
                            font.pixelSize: Math.round(root.height * 0.046); font.family: "DejaVu Sans"; font.weight: Font.Light
                            Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
                        }
                        HoverHandler { id: dBtnHover }
                        TapHandler { onTapped: activateDisable(modelData.seconds) }
                    }
                }
            }
        }

        // ── Swipe handler: right-swipe = history, left-swipe = disable panel ──
        DragHandler {
            id: swipeDrag
            target: null; acceptedButtons: Qt.NoButton
            xAxis.enabled: true; yAxis.enabled: false
            onActiveChanged: {
                if (!active) {
                    var vx = swipeDrag.centroid.velocity.x;
                    // Neither panel is open — decide which one to open.
                    if (!historyPanelOpen && !disablePanelOpen) {
                        if (vx > 200)  historyPanelOpen = true;   // swipe right → history
                        if (vx < -200) disablePanelOpen = true;   // swipe left  → disable
                    }
                    // History panel is open — swipe left to close.
                    else if (historyPanelOpen && vx < -200) {
                        historyPanelOpen = false;
                    }
                    // Disable panel is open — swipe right to close.
                    else if (disablePanelOpen && vx > 200) {
                        disablePanelOpen = false;
                    }
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // SCREEN STATE 3 — ALERT DETAIL
    // ═════════════════════════════════════════════════════════════════════════
    Item {
        id: detailScreen
        anchors.fill: parent
        visible: appState === "detail"

        Rectangle {
            anchors.fill: parent
            color: theme.bg
            Behavior on color { ColorAnimation { duration: themeTransitionDuration } }

            PropertyAnimation on color {
                running: detailScreen.visible
                from:    "#FF0000"
                to:      theme.bg
                duration: 500; easing.type: Easing.OutCubic
            }
        }

        Text {
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter:   parent.verticalCenter
                verticalCenterOffset: root.height * -0.10
            }
            text: currentAlert ? currentAlert.roomName : ""
            color: theme.timeColor
            font.pixelSize: Math.round(root.height * 0.22)
            font.family: "DejaVu Sans"
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: root.width * 0.9
            Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
        }

        Text {
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter:   parent.verticalCenter
                verticalCenterOffset: root.height * 0.10
            }
            text: currentAlert ? "Alert at " + currentAlert.timeStr + "  ·  " + currentAlert.dateStr : ""
            color: theme.dateColor
            font.pixelSize: Math.round(root.height * 0.042)
            font.family: "DejaVu Sans"
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: root.width * 0.9
            Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
        }

        Rectangle {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom:           parent.bottom
                bottomMargin:     root.height * 0.07
            }
            width:  Math.min(root.width * 0.35, 320)
            height: root.height * 0.09
            radius: 12
            color:  dismissHov.containsMouse ? theme.surface : "transparent"
            border.color: theme.subColor
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text:  "Dismiss"
                color: theme.timeColor
                font.pixelSize: Math.round(root.height * 0.036)
                font.family: "DejaVu Sans"
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: themeTransitionDuration } }
            }

            HoverHandler { id: dismissHov }
            TapHandler { onTapped: dismissAlert() }
        }

        Rectangle {
            visible: pendingAlert !== null && appState === "detail"
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: root.width; height: root.height * 0.09; color: "#8B0000"
            Text {
                anchors.centerIn: parent
                text: pendingAlert ? "New alert from " + pendingAlert.roomName + "  —  tap to view" : ""
                color: "#FAE8C0"
                font.pixelSize: Math.round(root.height * 0.030)
                font.family: "DejaVu Sans"; font.weight: Font.Medium
            }
            TapHandler { onTapped: switchToPendingAlert() }
        }
    }
}
