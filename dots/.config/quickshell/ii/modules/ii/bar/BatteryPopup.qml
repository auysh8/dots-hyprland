import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    
    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 16

        // Large circular indicator
        Item {
            width: 80
            height: 80
            Layout.alignment: Qt.AlignHCenter

            CircularProgress {
                anchors.fill: parent
                implicitSize: 80
                lineWidth: 7
                value: Battery.percentage
                colPrimary: {
                    if (Battery.isCharging) return Appearance.m3colors.m3primary;
                    if (Battery.percentage <= 0.2) return Appearance.m3colors.m3error;
                    return Appearance.m3colors.m3secondary;
                }
                colSecondary: Appearance.colors.colLayer1
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: {
                    if (Battery.isCharging) return "battery_charging_full";
                    if (Battery.percentage >= 0.9) return "battery_full";
                    if (Battery.percentage >= 0.5) return "battery_5_bar";
                    if (Battery.percentage >= 0.2) return "battery_2_bar";
                    return "battery_alert";
                }
                iconSize: 32
                color: {
                    if (Battery.isCharging) return Appearance.m3colors.m3primary;
                    if (Battery.percentage <= 0.2) return Appearance.m3colors.m3error;
                    return Appearance.m3colors.m3secondary;
                }
            }
        }

        Column {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: `${Math.round(Battery.percentage * 100)}%`
                font.weight: Font.Black
                font.pixelSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (Battery.chargeState == 4) return Translation.tr("Fully Charged");
                    if (Battery.isCharging) return Translation.tr("Charging");
                    return Translation.tr("Discharging");
                }
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.8
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        // Details Section
        Column {
            spacing: 4
            Layout.fillWidth: true
            Layout.topMargin: 4

            StyledPopupValueRow {
                visible: {
                    let timeValue = Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty;
                    let power = Battery.energyRate;
                    return !(Battery.chargeState == 4 || timeValue <= 0 || power <= 0.01);
                }
                icon: "schedule"
                label: Battery.isCharging ? Translation.tr("To full:") : Translation.tr("Left:")
                value: {
                    function formatTime(seconds) {
                        var h = Math.floor(seconds / 3600);
                        var m = Math.floor((seconds % 3600) / 60);
                        if (h > 0) return `${h}h ${m}m`;
                        return `${m}m`;
                    }
                    return formatTime(Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty);
                }
                bold: true
            }

            StyledPopupValueRow {
                icon: "bolt"
                label: Translation.tr("Rate:")
                value: `${Battery.energyRate.toFixed(2)}W`
            }

            StyledPopupValueRow {
                icon: "heart_check"
                label: Translation.tr("Health:")
                value: `${(Battery.health).toFixed(1)}%`
            }
        }
    }
}
