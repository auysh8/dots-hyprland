import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Item {
    id: root

    required property string time
    required property string date

    implicitHeight: Math.max(mainRow.implicitHeight + 16, 100)

    RowLayout {
        id: mainRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        // 1. Left Hero: Android Analog Clock inside M3 Cookie4Sided shape (Full 76px)
        Item {
            implicitWidth: 76
            implicitHeight: 76
            Layout.preferredWidth: 76
            Layout.preferredHeight: 76
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                anchors.fill: parent
                implicitSize: 76
                shape: MaterialShape.Shape.Cookie4Sided
                color: Appearance.colors.colPrimaryContainer

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }
            }

            AndroidClock {
                anchors.fill: parent
                anchors.margins: 4
                backgroundColor: "transparent"
                handColor: Appearance.colors.colPrimary
                minuteHandColor: Appearance.colors.colTertiary
                centerDotColor: Appearance.colors.colPrimary
            }
        }

        // 2. Middle: Large Bold Digital Time & Date Pill
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            StyledText {
                text: root.time
                font.pixelSize: 28
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            Rectangle {
                implicitHeight: 24
                implicitWidth: dateRow.implicitWidth + 14
                radius: 12
                color: Appearance.colors.colSurfaceContainerHigh

                Row {
                    id: dateRow
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "calendar_today"
                        iconSize: 12
                        color: Appearance.colors.colSecondary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.date
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }

        // 3. Right: Stacked Horizontal Capsule Glance Tiles (Weather & Battery)
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            // Weather Capsule
            Rectangle {
                implicitWidth: 84
                implicitHeight: 32
                radius: 14
                color: Appearance.colors.colSecondaryContainer

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: {
                            if (Weather.data && Weather.data.wCode)
                                return Icons.getWeatherIcon(Weather.data.wCode) ?? "wb_sunny";
                            return "wb_sunny";
                        }
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: {
                            if (Weather.data && Weather.data.temp && Weather.data.temp !== "--°")
                                return Weather.data.temp;
                            return "--°";
                        }
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            // Battery Capsule
            Rectangle {
                implicitWidth: 84
                implicitHeight: 32
                radius: 14
                color: Appearance.colors.colTertiaryContainer

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: {
                            if (Battery.isPluggedIn) return "bolt";
                            let pct = Math.round(Battery.percentage * 100);
                            return Icons.getBatteryIcon(pct);
                        }
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnTertiaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Math.round(Battery.percentage * 100) + "%"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnTertiaryContainer
                    }
                }
            }
        }
    }
}
