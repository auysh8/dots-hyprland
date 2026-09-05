import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Qt5Compat.GraphicalEffects


Item {
    id: root

    readonly property string quoteText: Config.options.background.widgets.clock.quote.text

    implicitWidth: quoteBox.implicitWidth
    implicitHeight: quoteBox.implicitHeight

    DropShadow {
        source: quoteBox 
        anchors.fill: quoteBox
        horizontalOffset: 0
        verticalOffset: 2
        radius: 12
        samples: radius * 2 + 1
        color: Appearance.colors.colShadow
        transparentBorder: true
    }
    
    Rectangle {
        id: quoteBox
        readonly property bool pixelHorizontal: Config.options.background.widgets.clock.style === "pixel" && (Config.options.background.centeredWallpaper || Config.options.background.widgets.clock.pixel.orientation === "horizontal")
        readonly property bool frameActive: Config.options.background.centeredWallpaper
        readonly property string frameColorName: Config.options.background.centeredWallpaperColor ?? "primaryContainer"
        readonly property bool usePrimaryVariant: frameActive && frameColorName === "secondaryContainer"
        y: pixelHorizontal ? -26 : 0
        x: pixelHorizontal ? -20 : 0
        implicitWidth: quoteStyledText.implicitWidth + 12 * 2
        implicitHeight: quoteStyledText.implicitHeight + 6 * 2
        radius: Appearance.rounding.small
        color: usePrimaryVariant ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer

        StyledText {
            id: quoteStyledText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: Config.options.background.widgets.clock.quote.text
            color: quoteBox.usePrimaryVariant ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            font {
                family: Config.options.background.widgets.clock.quote.followClock ? Config.options.background.widgets.clock.digital.font.family : Appearance.font.family.reading 
                pixelSize: Appearance.font.pixelSize.large
                weight: Font.Normal
            }
        }
    }
}
