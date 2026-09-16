import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Row {
    id: root

    property var model: []
    property var currentValue: 0
    property int horizontalPadding: 11
    property int verticalPadding: 6

    signal valueSelected(var value)

    spacing: 2

    Repeater {
        id: repeater
        model: root.model

        delegate: SelectionGroupButton {
            id: groupBtn
            required property int index
            required property var modelData
            readonly property var itemValue: modelData.value !== undefined ? modelData.value : index

            leftmost: index === 0
            rightmost: index === (root.model.length !== undefined ? root.model.length - 1 : repeater.count - 1)
            buttonText: modelData.label || modelData.displayName || ""
            buttonIcon: modelData.icon || ""
            toggled: root.currentValue === itemValue
            horizontalPadding: root.horizontalPadding
            verticalPadding: root.verticalPadding
            onClicked: {
                root.valueSelected(itemValue);
            }
        }
    }
}
