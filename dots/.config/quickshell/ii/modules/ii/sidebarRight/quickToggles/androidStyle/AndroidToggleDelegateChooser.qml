pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

DelegateChooser {
    id: root
    property bool editMode: false
    property int dragIndex: -1
    property string dragType: ""
    property bool hideWhileDragging: false
    property real dragCursorX: 0
    property real dragCursorY: 0
    property real dragPressOffsetX: 0
    property real dragPressOffsetY: 0
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    required property int startingIndex

    signal openAudioOutputDialog(var sourceItem)
    signal openAudioInputDialog(var sourceItem)
    signal openBluetoothDialog(var sourceItem)
    signal openNightLightDialog(var sourceItem)
    signal openWifiDialog(var sourceItem)

    role: "type"

    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openNightLightDialog(this)
        }
    } }

    DelegateChoice { roleValue: "audio"; AndroidAudioToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openAudioOutputDialog(this)
        }
    } }

    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle {
        id: bluetoothToggle
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openBluetoothDialog(bluetoothToggle)
        }
    } }

    DelegateChoice { roleValue: "cloudflareWarp"; AndroidCloudflareWarpToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "darkMode"; AndroidDarkModeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "easyEffects"; AndroidEasyEffectsToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "mic"; AndroidMicToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openAudioInputDialog(this)
        }
    } }

    DelegateChoice { roleValue: "musicRecognition"; AndroidMusicRecognition {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "network"; AndroidNetworkToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openWifiDialog(this)
        }
    } }

    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openNightLightDialog(this)
        }
    } }

    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "onScreenKeyboard"; AndroidOnScreenKeyboardToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        dragIndex: root.dragIndex
        dragType: root.dragType
        hideWhileDragging: root.hideWhileDragging
        dragCursorX: root.dragCursorX
        dragCursorY: root.dragCursorY
        dragPressOffsetX: root.dragPressOffsetX
        dragPressOffsetY: root.dragPressOffsetY
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }
}
