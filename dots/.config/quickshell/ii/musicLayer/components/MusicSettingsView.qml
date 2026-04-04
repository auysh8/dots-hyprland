import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

Item {
    id: root

    property var rootContext: null
    property color contentColor: rootContext ? rootContext.contentColor : "#ffffff"
    property color pillColor: rootContext ? rootContext.pillColor : "#cba6f7"
    property color subtleColor: Qt.rgba(contentColor.r, contentColor.g, contentColor.b, 0.45)

    signal navigateTo(string view)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // Header
        StyledText {
            text: "Settings"
            font.pixelSize: 22
            font.weight: Font.Medium
            color: root.contentColor
        }

        // Settings entries
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // Account entry
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: {
                    if (root.rootContext && !root.rootContext.isAuthenticated) {
                        root.rootContext.startOauth()
                    } else {
                        root.navigateTo("account")
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
                            text: "person"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "Account"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: root.rootContext && root.rootContext.isAuthenticated ? (root.rootContext.accountName || "Authenticated") : "Sign in to YouTube Music"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }

                    Item { Layout.fillWidth: true }

                    MaterialSymbol {
                        text: root.rootContext && root.rootContext.isAuthenticated ? "check" : "login"
                        iconSize: 20
                        color: root.rootContext && root.rootContext.isAuthenticated ? "#a6e3a1" : root.subtleColor
                    }
                }
            }

            // Cache entry
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: root.navigateTo("cache")
                
                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 14

                    Rectangle {
                        width: 36; height: 36
                        radius: 10
                        color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "database"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "Cache"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: "Manage downloaded audio, art & canvas"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }

                    Item { Layout.fillWidth: true }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 20
                        color: root.subtleColor
                    }
                }
            }
            
            // Audio Quality Toggle
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: {
                    if (root.rootContext) {
                        root.rootContext.updateMusicSettings("high_audio_quality", !root.rootContext.musicSettingsHighQuality)
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
                            text: "high_quality"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "High Audio Quality"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: root.rootContext && root.rootContext.musicSettingsHighQuality ? "Best available quality (Opus/M4A)" : "Data saver (Lowest bitrate)"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledSwitch {
                        checked: root.rootContext ? root.rootContext.musicSettingsHighQuality : true
                        // Non-interactive so the parent RippleButton handles clicks
                        enabled: false 
                    }
                }
            }
            
            // Cache Size Limit Slider
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cacheColumn.implicitHeight + 32
                radius: 14
                color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)

                ColumnLayout {
                    id: cacheColumn
                    anchors { fill: parent; margins: 16; leftMargin: 16; rightMargin: 16 }
                    spacing: 8

                    RowLayout {
                        spacing: 14

                        Rectangle {
                            width: 36; height: 36
                            radius: 10
                            color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "sd_storage"
                                iconSize: 18
                                color: root.pillColor
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            StyledText {
                                text: "Cache Size Limit"
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: root.contentColor
                            }
                            StyledText {
                                text: "Maximum storage used for audio, art, and video"
                                font.pixelSize: 11
                                color: root.subtleColor
                            }
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: Math.round(cacheSlider.value) + " MB"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.pillColor
                        }
                    }

                    StyledSlider {
                        id: cacheSlider
                        Layout.fillWidth: true
                        Layout.leftMargin: 50 // Align with text
                        from: 100
                        to: 5000
                        stepSize: 100
                        value: root.rootContext ? root.rootContext.musicSettingsCacheLimit : 500
                        usePercentTooltip: false
                        
                        onMoved: {
                            if (root.rootContext) {
                                root.rootContext.updateMusicSettings("max_cache_size_mb", Math.round(value))
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
