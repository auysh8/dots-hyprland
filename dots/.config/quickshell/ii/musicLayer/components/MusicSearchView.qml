import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    property string queryText: ""
    readonly property var flickable: root
    readonly property color listContainerColor: rootContext ? ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHighest, Appearance.m3colors.m3onSurface, 0.78) : "#5a5760"
    readonly property color listContainerBorderColor: rootContext ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.78) : "#38ffffff"

    anchors.fill: parent
    contentHeight: resultsColumn.implicitHeight + (rootContext.currentTrack ? 120 : 32)

    property bool show: queryText.length > 0 && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    ColumnLayout {
        id: resultsColumn
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Artists
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.artistResults.count > 0

            StyledText {
                text: "Artists"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 20

                Repeater {
                    model: rootContext.artistResults

                    delegate: ColumnLayout {
                        width: 100
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 100
                            height: 100
                            radius: 50
                            color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                            RoundedImage {
                                anchors.fill: parent
                                source: model.artUrl
                                fillMode: Image.PreserveAspectCrop
                                radius: 50
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: model.title
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Songs
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.songResults.count > 0

            StyledText {
                text: "Songs"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: songResultsColumn.height + 32
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: ColorUtils.transparentize(rootContext.contentColor, 0.9)

                ColumnLayout {
                    id: songResultsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext.songResults

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 12
                            color: songHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.8) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 16

                                Rectangle {
                                    width: 48
                                    height: 48
                                    radius: 8
                                    color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                                    RoundedImage {
                                        anchors.fill: parent
                                        source: model.artUrl
                                        fillMode: Image.PreserveAspectCrop
                                        radius: 8
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#40000000"
                                        visible: songHover.containsMouse

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: "white"
                                            iconSize: 24
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }

                                StyledText {
                                    text: model.duration
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: songHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl)
                            }
                        }
                    }
                }
            }
        }

        // Albums
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.albumResults.count > 0

            StyledText {
                text: "Albums"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16

                Repeater {
                    model: rootContext.albumResults

                    delegate: ColumnLayout {
                        width: (parent.width - 64) / 5
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 12
                            color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                            RoundedImage {
                                anchors.fill: parent
                                source: model.artUrl
                                fillMode: Image.PreserveAspectCrop
                                radius: 12
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: model.title
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: model.artist
                            font.pixelSize: 12
                            color: rootContext.secondaryContentColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Spacer
        Item {
            Layout.fillWidth: true
            height: rootContext.currentTrack ? 80 : 0
        }
    }
}
