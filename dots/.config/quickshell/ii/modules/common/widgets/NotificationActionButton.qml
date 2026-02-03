import qs.modules.common
import qs.services
import QtQuick
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string buttonText
    property string urgency

    implicitHeight: 34
    leftPadding: 15
    rightPadding: 15
    buttonRadius: Appearance.rounding.small
    colBackground: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
    colBackgroundHover: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
    colRipple: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSecondaryContainerActive

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        text: buttonText
        color: (urgency == NotificationUrgency.Critical) ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSecondaryContainer
    }
}