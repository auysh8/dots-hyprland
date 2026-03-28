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
    color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    border.width: 1
    border.color: rootContext ? rootContext.pillColor : Appearance.colors.colOutline
    z: 9999
    
    visible: rootContext && rootContext.oauthDialogVisible
    opacity: visible ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        
        StyledText {
            text: rootContext && rootContext.oauthCode ? "YouTube Music Authentication" : "Starting Authentication..."
            font.pixelSize: 22
            font.weight: 800
            color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }
        
        StyledText {
            text: rootContext && rootContext.oauthCode ? "Please go to the URL below in your browser and enter the code to seamlessly link your YouTube Music account." : "Connecting to Google..."
            font.pixelSize: 14
            color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        
        Item { Layout.fillHeight: true }
        
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            spacing: 8
            opacity: rootContext && rootContext.oauthCode ? 1.0 : 0.0
            
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: rootContext ? rootContext.pillColor : Appearance.colors.colSecondaryContainer
                
                StyledText {
                    anchors.centerIn: parent
                    text: rootContext ? (rootContext.oauthCode || "...") : "..."
                    font.pixelSize: 32
                    font.weight: 900
                    color: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
                    font.letterSpacing: 8
                }
            }
            
            Rectangle {
                Layout.preferredWidth: 60
                Layout.fillHeight: true
                radius: 12
                color: rootContext ? (rootContext.oauthCopied ? rootContext.extractedColor : rootContext.pillColor) : Appearance.colors.colSecondaryContainer

                RippleButton {
                    anchors.fill: parent
                    anchors.margins: 4
                    buttonRadius: 8
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(rootContext ? (rootContext.oauthCopied ? rootContext.extractedForeground : rootContext.pillContentColor) : Appearance.colors.colOnSecondaryContainer, 0.85)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: rootContext && rootContext.oauthCopied ? "check" : "content_copy"
                        font.pixelSize: 24
                        color: rootContext ? (rootContext.oauthCopied ? rootContext.extractedForeground : rootContext.pillContentColor) : Appearance.colors.colOnSecondaryContainer
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (!rootContext) return
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

            DialogButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                buttonText: "Cancel"
                colEnabled: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
                colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colSecondaryContainer
                colBackgroundHover: rootContext ? rootContext.pillColorHover : Appearance.colors.colSecondaryContainerHover
                colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer, 0.2)

                onClicked: {
                    if (!rootContext) return
                    rootContext.oauthDialogVisible = false
                    rootContext.sendCommand({ "command": "oauth_cancel" })
                }
            }

            DialogButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                buttonText: "Open Browser"
                opacity: rootContext && rootContext.oauthCode ? 1.0 : 0.5
                enabled: rootContext && rootContext.oauthCode !== ""
                colBackground: rootContext ? rootContext.extractedColor : Appearance.colors.colPrimaryContainer
                colBackgroundHover: rootContext ? ColorUtils.mix(rootContext.extractedColor, rootContext.extractedForeground, 0.85) : Appearance.colors.colPrimaryContainerHover
                colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.extractedForeground : Appearance.colors.colOnPrimaryContainer, 0.2)
                colText: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnPrimaryContainer

                onClicked: {
                    if (rootContext) Qt.openUrlExternally(rootContext.oauthUrl)
                }
            }
        }
    }
}
