import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root
    
    property var rootContext
    
    width: parent.width * 0.5
    height: 280
    radius: 20
    color: rootContext.surfaceColor
    border.width: 1
    border.color: rootContext.pillColor
    z: 9999
    
    visible: rootContext.oauthDialogVisible
    opacity: visible ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        
        StyledText {
            text: rootContext.oauthCode ? "YouTube Music Authentication" : "Starting Authentication..."
            font.pixelSize: 22
            font.weight: 800
            color: rootContext.contentColor
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
        
        StyledText {
            text: rootContext.oauthCode ? "Please go to the URL below in your browser and enter the code to seamlessly link your YouTube Music account." : "Connecting to Google..."
            font.pixelSize: 14
            color: rootContext.secondaryContentColor
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        
        Item { Layout.fillHeight: true }
        
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            spacing: 8
            opacity: rootContext.oauthCode ? 1.0 : 0.0
            
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: rootContext.pillColor
                
                StyledText {
                    anchors.centerIn: parent
                    text: rootContext.oauthCode || "..."
                    font.pixelSize: 32
                    font.weight: 900
                    color: rootContext.pillContentColor
                    font.letterSpacing: 8
                }
            }
            
            Rectangle {
                Layout.preferredWidth: 60
                Layout.fillHeight: true
                radius: 12
                color: rootContext.oauthCopied ? rootContext.extractedColor : rootContext.pillColor
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: rootContext.oauthCopied ? "check" : "content_copy"
                    font.pixelSize: 24
                    color: rootContext.oauthCopied ? rootContext.extractedForeground : rootContext.pillContentColor
                }
                
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        rootContext.sendCommand({ "command": "copy_clipboard", "text": rootContext.oauthCode })
                        rootContext.oauthCopied = true
                    }
                }
            }
        }
        
        Item { Layout.fillHeight: true }
        
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                buttonRadius: 22
                colBackground: rootContext.pillColor
                colBackgroundHover: rootContext.pillColorHover
                colRipple: ColorUtils.applyAlpha(rootContext.pillContentColor, 0.2)
                
                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: 15
                    color: rootContext.pillContentColor
                }
                
                onClicked: {
                    rootContext.oauthDialogVisible = false
                    rootContext.sendCommand({ "command": "oauth_cancel" })
                }
            }
            
            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                buttonRadius: 22
                colBackground: rootContext.extractedColor
                colBackgroundHover: ColorUtils.mix(rootContext.extractedColor, rootContext.extractedForeground, 0.15)
                colRipple: ColorUtils.applyAlpha(rootContext.extractedForeground, 0.2)
                opacity: rootContext.oauthCode ? 1.0 : 0.5
                enabled: rootContext.oauthCode !== ""
                
                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: "Open Browser"
                    font.pixelSize: 15
                    font.weight: 700
                    color: rootContext.extractedForeground
                }
                
                onClicked: {
                    Qt.openUrlExternally(rootContext.oauthUrl)
                }
            }
        }
    }
}
