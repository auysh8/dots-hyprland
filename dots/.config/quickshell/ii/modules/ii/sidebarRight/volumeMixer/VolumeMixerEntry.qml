import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    required property PwNode node
    PwObjectTracker {
        objects: [root.node]
    }

    implicitHeight: mainLayout.implicitHeight + 24
    radius: 18
    color: Appearance.colors.colLayer1

    RowLayout {
        id: mainLayout
        anchors {
            fill: parent
            leftMargin: 14
            rightMargin: 14
            topMargin: 12
            bottomMargin: 12
        }
        spacing: 12

        // App Icon Badge & Mute Click Area
        Rectangle {
            id: iconContainer
            Layout.alignment: Qt.AlignVCenter
            width: 40
            height: 40
            radius: 12
            color: root.node?.audio.muted ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.node.audio.muted = !root.node.audio.muted
                hoverEnabled: true

                StyledToolTip {
                    text: root.node?.audio.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
                }

                StyledImage {
                    id: iconImg
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    visible: false
                    source: {
                        let icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                        if (AppSearch.iconExists(icon))
                            return Quickshell.iconPath(icon, "image-missing");
                        icon = AppSearch.guessIcon(root.node?.properties["node.name"] ?? "");
                        return Quickshell.iconPath(icon, "image-missing");
                    }
                }

                Desaturate {
                    anchors.fill: iconImg
                    source: iconImg
                    desaturation: root.node?.audio.muted ? 1.0 : 0.0
                    visible: iconImg.source !== "" && !(root.node?.audio.muted ?? false)
                    opacity: root.node?.audio.muted ? 0.3 : 1.0
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: (root.node?.audio.muted ?? false) || iconImg.source === ""
                    text: root.node?.audio.muted ? (root.node?.isSink ? "volume_off" : "mic_off") : (root.node?.isSink ? "volume_up" : "mic")
                    iconSize: 20
                    color: root.node?.audio.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnSurface
                }
            }
        }

        // App Name & Slider Column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: root.node?.audio.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    text: {
                        const app = Audio.appNodeDisplayName(root.node);
                        const media = root.node.properties["media.name"];
                        return media != undefined ? `${app} • ${media}` : app;
                    }
                }

                StyledText {
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: root.node?.audio.muted ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                    text: `${Math.round((root.node?.audio.volume ?? 0) * 100)}%`
                }
            }

            StyledSlider {
                id: slider
                Layout.fillWidth: true
                value: root.node?.audio.volume ?? 0
                onMoved: root.node.audio.volume = value
                configuration: StyledSlider.Configuration.S
            }
        }
    }
}
