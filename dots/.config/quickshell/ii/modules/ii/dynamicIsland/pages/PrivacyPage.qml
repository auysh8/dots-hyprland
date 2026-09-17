import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent

    readonly property bool hasCam: Privacy.camActive
    readonly property bool hasMic: Privacy.micActive
    readonly property bool hasScreen: Privacy.screenSharing
    readonly property bool isMuted: Privacy.micMuted

    readonly property color camColor: Appearance.m3colors.m3success
    readonly property color camContainerColor: Appearance.m3colors.m3successContainer
    readonly property color camOnContainerColor: Appearance.m3colors.m3onSuccessContainer

    readonly property color micColor: isMuted ? Appearance.colors.colError : Appearance.colors.colTertiary
    readonly property color micContainerColor: isMuted ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
    readonly property color micOnContainerColor: isMuted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer

    readonly property color heroColor: {
        if (hasCam) return camColor;
        if (hasMic) return micColor;
        return Appearance.colors.colPrimary;
    }
    readonly property color heroContainerColor: {
        if (hasCam) return camContainerColor;
        if (hasMic) return micContainerColor;
        return Appearance.colors.colPrimaryContainer;
    }
    readonly property color heroOnContainerColor: {
        if (hasCam) return camOnContainerColor;
        if (hasMic) return micOnContainerColor;
        return Appearance.colors.colOnPrimaryContainer;
    }

    implicitHeight: 110

    // =========================================================================
    // CASE A: DUAL HARDWARE ACTIVE (Camera + Mic) -> Side-by-Side Dual Tiles
    // =========================================================================
    RowLayout {
        id: dualTilesRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8
        visible: root.hasCam && root.hasMic

        // Left Tile: Camera Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 96
            radius: Appearance.rounding.large
            color: ColorUtils.applyAlpha(root.camContainerColor, 0.45)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 3

                // Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "videocam"
                        iconSize: 16
                        fill: 1
                        color: root.camColor
                    }

                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        width: 8
                        height: 8

                        Rectangle {
                            anchors.centerIn: parent
                            width: 4
                            height: 4
                            radius: 2
                            color: root.camColor
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: ColorUtils.applyAlpha(root.camColor, 0.4)

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                running: root.hasCam && root.visible
                                NumberAnimation { from: 0.7; to: 1.4; duration: 1000; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1.4; to: 0.7; duration: 1000; easing.type: Easing.InOutSine }
                            }
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: root.hasCam && root.visible
                                NumberAnimation { from: 0.7; to: 0.0; duration: 1000; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.0; to: 0.7; duration: 1000; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Camera"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.camColor
                    }
                }

                // App Name Label
                StyledText {
                    Layout.fillWidth: true
                    text: Privacy.camAppName || "Integrated Camera"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.SemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                // Status Badge
                Rectangle {
                    implicitWidth: camBadgeRow.implicitWidth + 12
                    implicitHeight: 22
                    radius: Appearance.rounding.small
                    color: ColorUtils.applyAlpha(root.camContainerColor, 0.65)

                    Row {
                        id: camBadgeRow
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5
                            height: 5
                            radius: 2.5
                            color: root.camColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Streaming"
                            font.pixelSize: 10
                            font.weight: Font.SemiBold
                            color: root.camColor
                        }
                    }
                }
            }
        }

        // Right Tile: Microphone Card with Inline Mute Button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 96
            radius: Appearance.rounding.large
            color: ColorUtils.applyAlpha(root.micContainerColor, 0.45)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 3

                // Header Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.isMuted ? "mic_off" : "mic"
                        iconSize: 16
                        fill: 1
                        color: root.micColor
                    }

                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1.5
                        visible: !root.isMuted

                        Repeater {
                            model: 3
                            Rectangle {
                                width: 2
                                readonly property real minH: index === 1 ? 5 : 3
                                readonly property real maxH: index === 1 ? 14 : 9
                                readonly property real level: (Privacy.micLevels.length > index ? Privacy.micLevels[index] : 0) / 100.0
                                height: minH + level * (maxH - minH)
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 1
                                color: root.micColor

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 65
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.isMuted ? "Muted" : "Microphone"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.micColor
                    }
                }

                // App Name Label
                StyledText {
                    Layout.fillWidth: true
                    text: Privacy.micAppName || "Microphone Stream"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.SemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                // Inline M3 Pill Mute Button
                GroupButton {
                    Layout.fillWidth: true
                    baseHeight: 24
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.small
                    buttonRadiusPressed: Appearance.rounding.verysmall
                    bounce: true

                    colBackground: ColorUtils.applyAlpha(root.micContainerColor, 0.8)
                    colBackgroundHover: root.micContainerColor
                    colBackgroundActive: root.micColor

                    onClicked: Privacy.toggleMicMute()

                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isMuted ? "mic" : "mic_off"
                            iconSize: 13
                            fill: 1
                            color: root.micColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isMuted ? "Unmute" : "Mute"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: root.micColor
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // CASE B: SINGLE HARDWARE ACTIVE (Only Camera OR Only Mic) -> Hero Card
    // =========================================================================
    Rectangle {
        id: singleHeroCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        implicitHeight: 96
        radius: Appearance.rounding.large
        color: ColorUtils.applyAlpha(root.heroContainerColor, 0.45)
        visible: !(root.hasCam && root.hasMic)
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 10

            // Left Hero Squircle Icon
            Item {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: ColorUtils.applyAlpha(root.heroContainerColor, 0.7)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: {
                        if (root.hasCam) return "videocam";
                        if (root.hasMic) return root.isMuted ? "mic_off" : "mic";
                        if (root.hasScreen) return "screen_share";
                        return "security";
                    }
                    iconSize: 22
                    fill: 1
                    color: root.heroColor
                }
            }

            // Center Details Column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                // Title
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (root.hasCam) return "Camera Active";
                        if (root.hasMic) return root.isMuted ? "Microphone Muted" : "Microphone Active";
                        if (root.hasScreen) return "Screen Sharing Active";
                        return "Privacy Guard";
                    }
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                // Accessing App Name
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        if (root.hasCam && Privacy.camAppName) return Privacy.camAppName;
                        if (root.hasMic && Privacy.micAppName) return Privacy.micAppName;
                        if (root.hasScreen) return "Display Server";
                        return "Active Hardware Stream";
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.SemiBold
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                // Subtitle Badge
                Rectangle {
                    implicitWidth: singleStatusRow.implicitWidth + 10
                    implicitHeight: 20
                    radius: Appearance.rounding.small
                    color: ColorUtils.applyAlpha(root.heroContainerColor, 0.7)

                    Row {
                        id: singleStatusRow
                        anchors.centerIn: parent
                        spacing: 4

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1.5
                            visible: root.hasMic && !root.isMuted

                            Repeater {
                                model: 3
                                Rectangle {
                                    width: 2
                                    readonly property real minH: index === 1 ? 4.5 : 3
                                    readonly property real maxH: index === 1 ? 10 : 6.5
                                    readonly property real level: (Privacy.micLevels.length > index ? Privacy.micLevels[index] : 0) / 100.0
                                    height: minH + level * (maxH - minH)
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 1
                                    color: root.heroColor

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 65
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 5
                            height: 5
                            radius: 2.5
                            color: root.heroColor
                            visible: !root.hasMic || root.isMuted
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.hasCam ? "V4L2 Monitored" : (root.isMuted ? "Input Silenced" : "PipeWire Audio Link")
                            font.pixelSize: 10
                            font.weight: Font.SemiBold
                            color: root.heroColor
                        }
                    }
                }
            }

            // Right Action Controls
            Item {
                Layout.preferredWidth: muteBtn.visible ? muteBtn.width : (shieldBadge.visible ? shieldBadge.width : 0)
                Layout.preferredHeight: 30
                implicitWidth: Layout.preferredWidth
                implicitHeight: 30
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

                // Mute / Unmute Button (for Mic)
                GroupButton {
                    id: muteBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasMic
                    baseWidth: Math.max(76, muteButtonContent.implicitWidth + 20)
                    baseHeight: 30
                    buttonRadius: Appearance.rounding.normal
                    buttonRadiusPressed: Appearance.rounding.small
                    bounce: true

                    colBackground: ColorUtils.applyAlpha(root.micContainerColor, 0.8)
                    colBackgroundHover: root.micContainerColor
                    colBackgroundActive: root.micColor

                    onClicked: Privacy.toggleMicMute()

                    contentItem: Row {
                        id: muteButtonContent
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isMuted ? "mic" : "mic_off"
                            iconSize: 14
                            fill: 1
                            color: root.micColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isMuted ? "Unmute" : "Mute"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: root.micColor
                        }
                    }
                }

                // Security Shield Badge (for Cam only)
                Rectangle {
                    id: shieldBadge
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.hasMic && root.hasCam
                    implicitWidth: 84
                    implicitHeight: 28
                    radius: Appearance.rounding.normal
                    color: ColorUtils.applyAlpha(root.camContainerColor, 0.65)

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "verified_user"
                            iconSize: 13
                            fill: 1
                            color: root.camColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Protected"
                            font.pixelSize: 10
                            font.weight: Font.SemiBold
                            color: root.camColor
                        }
                    }
                }
            }
        }
    }
}
