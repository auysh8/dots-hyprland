// added smoother transitions to the Slider layout changes and spring physics on toggle popups x
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import QtQuick.Effects

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property Item activeSourceItem: null
    readonly property bool anyDialogOpen: showAudioOutputDialog || showAudioInputDialog || showBluetoothDialog || showNightLightDialog || showWifiDialog

    // Auto-collapse bottom widgets when entering edit mode to prevent overlap
    onEditModeChanged: {
        if (editMode) {
            bottomWidgetGroup.setCollapsed(true);
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showNightLightDialog = false;
                root.editMode = false;
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        property real blurRadius: root.anyDialogOpen ? 48 : 0
        Behavior on blurRadius { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
        layer.enabled: blurRadius > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 48
            blur: sidebarRightBackground.blurRadius / 48
            saturation: 0.5
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }

            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: opacity > 0
                opacity: active ? 1 : 0
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
            }

            BottomWidgetGroup {
                id: bottomWidgetGroup
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog { isSink: true }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog { isSink: false }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                bluetoothStartTimer.stop();
                bluetoothStopTimer.start();
            } else {
                bluetoothStopTimer.stop();
                bluetoothStartTimer.start();
            }
        }
        Timer {
            id: bluetoothStartTimer
            interval: 150
            onTriggered: {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
        Timer {
            id: bluetoothStopTimer
            // Let the close morph finish before touching bluetooth state.
            interval: 450
            onTriggered: {
                if (!shown && Bluetooth.defaultAdapter) {
                    Bluetooth.defaultAdapter.discovering = false;
                }
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) {
                wifiStartTimer.stop();
            } else {
                wifiStartTimer.start();
            }
        }
        Timer {
            id: wifiStartTimer
            interval: 150
            onTriggered: {
                if (Network.wifiEnabled) {
                    Network.rescanWifi();
                } else {
                    Network.enableWifi(true);
                }
            }
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        active: shown || (item && item.visible)
        
        onActiveChanged: {
            if (active && item) {
                if (item.sourceItem !== undefined) item.sourceItem = root.activeSourceItem;
                // Defer showing to allow initial geometry (startRect) to settle
                // so the animation plays from start->target instead of jumping.
                openTimer.restart();
            }
        }
        
        Timer {
            id: openTimer
            interval: 10
            repeat: false
            onTriggered: {
                if (toggleDialogLoader.item) {
                    toggleDialogLoader.item.animationsEnabled = true;
                    toggleDialogLoader.item.show = true;
                    toggleDialogLoader.item.forceActiveFocus();
                }
            }
        }

        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                // Start closing animation
                toggleDialogLoader.item.show = false
                // Update state; loader stays active due to item.visible binding
                root[toggleDialogLoader.shownPropertyString] = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog(sourceItem) {
                root.activeSourceItem = sourceItem;
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog(sourceItem) {
                root.activeSourceItem = sourceItem;
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog(sourceItem) {
                root.activeSourceItem = sourceItem;
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog(sourceItem) {
                root.activeSourceItem = sourceItem;
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog(sourceItem) {
                root.activeSourceItem = sourceItem;
                root.showWifiDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: 40

        // Left: Uptime Pill Capsule (40px height matching buttons)
        Pill {
            id: uptimeContainer
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
            }
            height: 40
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            implicitWidth: uptimeRow.implicitWidth + 20

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8

                // Mint/Teal/Primary Circular Icon Badge
                Pill {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "timer"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                verticalCenter: parent.verticalCenter
                right: parent.right
            }
            height: 40
            color: "transparent"
            spacing: 6
            padding: 0
            implicitWidth: (Config.options.sidebar.quickToggles.style === "android" ? 4 : 3) * 40 + ((Config.options.sidebar.quickToggles.style === "android" ? 4 : 3) - 1) * 6
            width: implicitWidth

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"])
                    Quickshell.reload(true);
                }
                StyledToolTip { text: Translation.tr("Reload Hyprland & Quickshell") }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached(["qs", "-p", root.settingsQmlPath]);
                }
                StyledToolTip { text: Translation.tr("Settings") }
            }
            QuickToggleButton {
                id: shutdownButton
                toggled: false
                buttonIcon: "power_settings_new"
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colError
                colBackgroundActive: Appearance.colors.colErrorContainer
                colIcon: shutdownButton.hovered ? Appearance.colors.colOnError : Appearance.colors.colOnLayer1
                onClicked: { GlobalStates.sessionOpen = true; }
                StyledToolTip { text: Translation.tr("Session") }
            }
        }
    }
}
