import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

Item {
    id: root

    property var rootContext: null
    property color contentColor: rootContext ? rootContext.contentColor : "#ffffff"
    property color surfaceColor: rootContext ? rootContext.surfaceColor : "#1e1e2e"
    property color pillColor: rootContext ? rootContext.pillColor : "#cba6f7"
    property color pillContentColor: rootContext ? rootContext.pillContentColor : "#1e1e2e"
    property color subtleColor: Qt.rgba(contentColor.r, contentColor.g, contentColor.b, 0.45)

    signal navigateBack()

    anchors.fill: parent

    Behavior on width {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    Component.onCompleted: {
        if (rootContext && rootContext.isAuthenticated) {
            rootContext.sendCommand({ "command": "get_account_info" })
        }
    }

    onVisibleChanged: {
        if (visible && rootContext && rootContext.isAuthenticated) {
            rootContext.sendCommand({ "command": "get_account_info" })
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Back button
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: 18
                colBackground: "transparent"
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.20)
                onClicked: root.navigateBack()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: root.contentColor
                }
            }

            StyledText {
                text: "Account"
                font.pixelSize: 22
                font.weight: Font.Medium
                color: root.contentColor
            }

            Item { Layout.fillWidth: true }
        }

        // Profile Card
        Rectangle {
            Layout.fillWidth: true
            height: 100
            radius: 16
            color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)

            RowLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 16

                // Avatar
                RoundedImage {
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    radius: 34
                    source: rootContext && rootContext.accountPhotoUrl ? rootContext.accountPhotoUrl : ""
                    visible: rootContext && rootContext.accountPhotoUrl !== ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(68, 68)
                }

                Rectangle {
                    Layout.preferredWidth: 68
                    Layout.preferredHeight: 68
                    radius: 34
                    color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                    visible: !(rootContext && rootContext.accountPhotoUrl !== "")
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        iconSize: 32
                        color: root.pillColor
                    }
                }

                // Info
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        text: rootContext && rootContext.accountName ? rootContext.accountName : "YouTube Music User"
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: root.contentColor
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        text: rootContext && rootContext.channelHandle ? rootContext.channelHandle : "Authenticated Account"
                        font.pixelSize: 13
                        color: root.subtleColor
                    }
                }
                
                Item { Layout.fillWidth: true }
            }
        }
        
        // Settings entries
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // Refresh Auth
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: {
                    if (rootContext && rootContext.isAuthenticated) {
                        rootContext.refreshAuth()
                        root.navigateBack()
                    }
                }
                
                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 14

                    Rectangle {
                        width: 36; height: 36
                        radius: 10
                        color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "sync"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "Refresh Authentication"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: "Sync tokens and cookies from browser"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                }
            }
            
            // Open YTM
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: {
                    Qt.openUrlExternally("https://music.youtube.com")
                }
                
                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 14

                    Rectangle {
                        width: 36; height: 36
                        radius: 10
                        color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_new"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "Open YouTube Music"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: "Launch the web player in your browser"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }
                    
                    Item { Layout.fillWidth: true }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Logout Button
        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: 12
            colBackground: Qt.rgba(0.94, 0.54, 0.66, 0.12)
            colBackgroundHover: Qt.rgba(0.94, 0.54, 0.66, 0.22)
            colRipple: Qt.rgba(0.94, 0.54, 0.66, 0.32)
            
            onClicked: {
                if (rootContext) {
                    rootContext.sendCommand({ "command": "logout" })
                    root.navigateBack()
                }
            }
            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "Sign Out"
                font.pixelSize: 13
                font.weight: Font.Medium
                color: "#f38ba8"
            }
        }

        Item { height: 8 }
    }
}
