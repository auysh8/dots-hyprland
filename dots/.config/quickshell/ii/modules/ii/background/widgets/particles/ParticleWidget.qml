import QtQuick
import QtQuick.Particles 2.0
import qs.modules.ii.background.widgets
import qs.modules.common

AbstractBackgroundWidget {
    id: root
    configEntryName: "particles"

    // Pass the Hyprland monitor to track workspace changes
    required property var monitor
    
    // Override placement
    x: 0
    y: 0
    width: scaledScreenWidth
    height: scaledScreenHeight
    
    // Match wallpaper vibes
    property color particleColor: root.dominantColor
    property real particleOpacity: 0.6
    property int particleCount: 80
    property real particleSpeed: 25

    // Wind Simulation
    property real windForce: 0
    
    // Animation to decay the wind
    NumberAnimation {
        id: windDecay
        target: root
        property: "windForce"
        to: 0
        duration: 2000
        easing.type: Easing.OutElastic
        easing.period: 900
    }

    function applyWindImpulse(force) {
        windDecay.stop();
        root.windForce = force; // Instant snap
        windDecay.restart();
    }
    
    property int lastWs: 0
    property var activeWs: monitor?.activeWorkspace
    onActiveWsChanged: {
        if (!activeWs) return;
        const newId = activeWs.id;
        if (lastWs !== 0 && newId !== lastWs) {
            const delta = newId - lastWs;
            applyWindImpulse(-delta * 1200);
        }
        lastWs = newId;
    }

    // React to sidebars using explicit Connections
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            // Open: Move Right (positive), Close: Move Left (negative)
            applyWindImpulse(GlobalStates.sidebarLeftOpen ? 4000 : -4000);
        }
        function onSidebarRightOpenChanged() {
            // Open: Move Left (negative), Close: Move Right (positive)
            applyWindImpulse(GlobalStates.sidebarRightOpen ? -4000 : 4000);
        }
    }

    ParticleSystem {
        id: particleSystem
        anchors.fill: parent
        
        // Global wind force
        Gravity {
            angle: 0 // 0 degrees = Right. Negative magnitude will pull Left.
            magnitude: root.windForce
        }

        Emitter {
            id: emitter
            anchors.fill: parent
            enabled: root.visible
            
            emitRate: root.particleCount / 4
            lifeSpan: 6000
            lifeSpanVariation: 2000
            
            size: 6
            sizeVariation: 4
            
            velocity: AngleDirection {
                angle: 270 // Up
                angleVariation: 30
                magnitude: root.particleSpeed
                magnitudeVariation: 15
            }
            
            acceleration: AngleDirection {
                angle: 90 // Slight gravity downwards
                magnitude: 2
            }
        }

        ImageParticle {
            source: "qrc:///particleresources/glowdot" 
            color: root.particleColor
            colorVariation: 0.1
            alpha: root.particleOpacity
            alphaVariation: 0.2
        }

        Wander {
            xVariance: 50
            pace: 100
        }
    }
}
