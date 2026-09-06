import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.shapes
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    popupRadius: Appearance.rounding.large // Oversized, expressive outer shell

    readonly property bool fullyCharged: Battery.chargeState == 4
    readonly property bool lowAndNotCharging: Battery.isLow && !Battery.isCharging

    // State -> M3 color role mapping: containers for surfaces, on-colors for content
    readonly property color accentColor: {
        if (!Battery.available) return Appearance.colors.colSecondary;
        if (lowAndNotCharging) return Appearance.colors.colError;
        if (Battery.isCharging || fullyCharged) return Appearance.colors.colPrimary;
        return Appearance.colors.colTertiary;
    }
    readonly property color accentContainerColor: {
        if (!Battery.available) return Appearance.colors.colSecondaryContainer;
        if (lowAndNotCharging) return Appearance.colors.colErrorContainer;
        if (Battery.isCharging || fullyCharged) return Appearance.colors.colPrimaryContainer;
        return Appearance.colors.colTertiaryContainer;
    }
    readonly property color onAccentContainerColor: {
        if (!Battery.available) return Appearance.colors.colOnSecondaryContainer;
        if (lowAndNotCharging) return Appearance.colors.colOnErrorContainer;
        if (Battery.isCharging || fullyCharged) return Appearance.colors.colOnPrimaryContainer;
        return Appearance.colors.colOnTertiaryContainer;
    }

    readonly property string stateIcon: {
        if (!Battery.available) return "power";
        if (Battery.isCharging) return "battery_charging_full";
        if (fullyCharged) return "battery_full";
        if (Battery.percentage >= 0.9) return "battery_full";
        if (Battery.percentage >= 0.5) return "battery_5_bar";
        if (Battery.percentage >= 0.2) return "battery_2_bar";
        return "battery_alert";
    }

    readonly property string timeText: {
        function formatTime(seconds) {
            var h = Math.floor(seconds / 3600);
            var m = Math.floor((seconds % 3600) / 60);
            if (h > 0) return `${h}h ${m}m`;
            return `${m}m`;
        }
        if (Battery.available && !fullyCharged) {
            if (Battery.isCharging && Battery.timeToFull > 0)
                return formatTime(Battery.timeToFull);
            if (!Battery.isCharging && Battery.timeToEmpty > 0)
                return formatTime(Battery.timeToEmpty);
        }
        return "";
    }

    readonly property string badgeText: {
        if (!Battery.available) return Translation.tr("AC Power");
        if (fullyCharged) return Translation.tr("Fully Charged");
        if (lowAndNotCharging) return Translation.tr("Low Battery");
        if (Battery.isCharging)
            return timeText.length > 0
                ? `${Translation.tr("Charging")} · ${Translation.tr("%1 to full").arg(timeText)}`
                : Translation.tr("Charging");
        return timeText.length > 0
            ? `${Translation.tr("Discharging")} · ${Translation.tr("%1 left").arg(timeText)}`
            : Translation.tr("Discharging");
    }

    // Hero silhouette morph: charging = spiky 9-sided cookie (energetic), full = flower
    // (blooming), discharging = calm 12-sided cookie, no battery / low battery = plain
    // circle (still, alarming). ShapeCanvas morphs between them automatically.
    readonly property int heroShape: {
        if (!Battery.available || lowAndNotCharging) return MaterialShape.Shape.Circle;
        if (fullyCharged) return MaterialShape.Shape.Flower;
        if (Battery.isCharging) return MaterialShape.Shape.Cookie9Sided;
        return MaterialShape.Shape.Cookie12Sided;
    }

    // NOTE: the state-change and entrance animations are declared inside columnLayout —
    // StyledPopup's default property is a single Item, so non-visual objects can't be
    // direct children here.

    onStateIconChanged: heroBounce.restart()
    onHeroShapeChanged: heroBounce.restart()

    ColumnLayout { // Zone 1: Outer shell — compact vertical container, central axis
        id: columnLayout
        spacing: 14
        // Never smaller than 260, but grow to fit content so readouts never overflow
        implicitWidth: Math.max(260, statusCluster.implicitWidth, metricCards.implicitWidth)

        SequentialAnimation { // Springy "boing" when the state (glyph or shape) changes
            id: heroBounce
            NumberAnimation {
                target: heroBadge
                property: "scale"
                from: 1.15
                to: 1
                duration: Appearance.animation.clickBounce.duration
                easing.type: Appearance.animation.clickBounce.type
                easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
            }
        }

        // Zone 2: Hero badge — organic M3 shape vessel with a crisp, guaranteed-visible glyph
        Item {
            id: heroBadge
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            implicitWidth: 72
            implicitHeight: 72
            opacity: 0 // Animated in by heroEntrance
            scale: 0.9

            MaterialShapeWrappedMaterialSymbol {
                id: heroVessel
                anchors.centerIn: parent
                implicitSize: 64
                wrappedShape: root.heroShape
                text: root.stateIcon
                iconSize: 36
                fill: 1
                padding: 14
                color: root.accentContainerColor
                colSymbol: root.onAccentContainerColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            SequentialAnimation {
                id: heroEntrance
                running: true
                ParallelAnimation {
                    NumberAnimation {
                        target: heroBadge
                        property: "opacity"
                        from: 0; to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                    NumberAnimation {
                        target: heroBadge
                        property: "scale"
                        from: 0.9; to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
            }
        }

        // Zone 3: Identity & status cluster — big expressive percentage + tonal capsule
        Column {
            id: statusCluster
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            opacity: 0 // Animated in by statusClusterEntrance
            scale: 0.92

            StyledText { // Large display percentage in the numbers typeface
                anchors.horizontalCenter: parent.horizontalCenter
                text: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : "AC"
                font.family: Appearance.font.family.numbers
                font.pixelSize: 42
                font.weight: Font.Black
                font.variableAxes: ({}) // Let font.weight drive wght (override StyledText's default axes)
                color: root.accentColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Rectangle { // Tonal capsule pill badge — container/on-container pair
                id: badgePill
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: badgeLabel.implicitWidth + 26
                implicitHeight: badgeLabel.implicitHeight + 12
                radius: Appearance.rounding.full
                color: root.accentContainerColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: root.badgeText
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.3
                    color: root.onAccentContainerColor

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            SequentialAnimation {
                id: statusClusterEntrance
                running: true
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation {
                        target: statusCluster
                        property: "opacity"
                        from: 0; to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                    NumberAnimation {
                        target: statusCluster
                        property: "scale"
                        from: 0.92; to: 1
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Appearance.animation.elementMoveEnter.type
                        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                    }
                }
            }
        }

        // Zone 4: Split metric cards — two distinct elevated cards instead of one dock
        RowLayout {
            id: metricCards
            visible: Battery.available
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 10
            opacity: 0 // Animated in by cardsEntrance

            component MetricCard: Rectangle {
                id: card
                property string icon
                property color iconColor
                property string label
                property string value

                Layout.fillWidth: true
                // Size to content so the parent row knows the real space needed
                implicitWidth: cardLayout.implicitWidth + 12 * 2
                implicitHeight: cardLayout.implicitHeight + 12 * 2
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2 // Elevated component tone above the colLayer0 shell

                ColumnLayout {
                    id: cardLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 7

                    RowLayout { // Header: tonal icon chip + uppercase micro-label
                        spacing: 6
                        Layout.alignment: Qt.AlignHCenter

                        Rectangle {
                            implicitWidth: 24
                            implicitHeight: 24
                            radius: Appearance.rounding.small
                            color: ColorUtils.transparentize(card.iconColor, 0.85)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: card.icon
                                iconSize: 14
                                color: card.iconColor
                            }
                        }

                        StyledText {
                            text: card.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            font.letterSpacing: 0.6
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText { // Large bold numeric readout in the numbers typeface
                        Layout.alignment: Qt.AlignHCenter
                        text: card.value
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        font.variableAxes: ({}) // Let font.weight drive wght
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            MetricCard {
                icon: "bolt"
                iconColor: root.accentColor
                label: Translation.tr("RATE")
                value: Battery.available ? `${Battery.energyRate.toFixed(1)}W` : "—"
            }

            MetricCard {
                icon: "vital_signs"
                iconColor: Appearance.colors.colSecondary
                label: Translation.tr("HEALTH")
                value: Battery.health > 0 ? `${Battery.health.toFixed(1)}%` : "—"
            }

            SequentialAnimation {
                id: cardsEntrance
                running: Battery.available
                PauseAnimation { duration: 120 }
                NumberAnimation {
                    target: metricCards
                    property: "opacity"
                    from: 0; to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }
        }
    }
}
