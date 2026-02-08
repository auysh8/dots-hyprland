import QtQuick
import QtQuick.Particles 2.0
import qs.modules.ii.background.widgets
import qs.modules.common

AbstractBackgroundWidget {
    id: root
    configEntryName: "particles"

    // Pass the Hyprland monitor to track workspace changes
    required property var monitor
    
    // Disable interaction since this is a full-screen overlay
    enabled: false
    draggable: false
    
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
    // React to sidebars using explicit properties
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    
    onSidebarLeftOpenChanged: {
        // Open: Move Right (positive), Close: Move Left (negative)
        applyWindImpulse(sidebarLeftOpen ? 1500 : -1500);
    }
    
    onSidebarRightOpenChanged: {
        // Open: Move Left (negative), Close: Move Right (positive)
        applyWindImpulse(sidebarRightOpen ? -1500 : 1500);
    }

    ParticleSystem {
        id: particleSystem
        anchors.fill: parent
        
        // --- Renderers (Painters) ---
        // Render layers in order: Far (bottom), Mid, Close (top)
        
        ImageParticle {
            groups: ["far"]
            source: "qrc:///particleresources/glowdot" 
            color: root.particleColor
            colorVariation: 0.05
            alpha: root.particleOpacity * 0.6 // Faint background
            alphaVariation: 0.1
            z: 0
        }
        
        ImageParticle {
            groups: ["mid"]
            source: "qrc:///particleresources/glowdot" 
            color: root.particleColor
            colorVariation: 0.1
            alpha: root.particleOpacity
            alphaVariation: 0.2
            z: 1
        }
        
        ImageParticle {
            groups: ["close"]
            source: "qrc:///particleresources/glowdot" 
            color: root.particleColor
            colorVariation: 0.1
            alpha: root.particleOpacity
            alphaVariation: 0.2
            z: 2
        }

        // --- Physics (Affectors) ---
        
        // Common Wander
        Wander {
            groups: ["far", "mid", "close"]
            xVariance: 50
            pace: 100
        }

        // Parallax Wind (Gravity)
        Gravity {
            groups: ["far"]
            angle: 0 
            magnitude: root.windForce * 0.25 // Less movement for background
        }
        
        Gravity {
            groups: ["mid"]
            angle: 0
            magnitude: root.windForce // Standard movement
        }
        
        Gravity {
            groups: ["close"]
            angle: 0
            magnitude: root.windForce * 1.8 // More movement for foreground feel
        }

        // --- Emitters ---

        // 1. Far Layer (Small, Slow, Background)
        Emitter {
            group: "far"
            anchors.fill: parent
            enabled: root.visible
            
            emitRate: root.particleCount * 0.4
            lifeSpan: 7000
            lifeSpanVariation: 3000
            
            size: 3
            sizeVariation: 2
            
            velocity: AngleDirection {
                angle: 270 
                angleVariation: 30
                magnitude: root.particleSpeed * 0.5
                magnitudeVariation: 5
            }
            
            acceleration: AngleDirection {
                angle: 90 
                magnitude: 1
            }
        }
        
        // 2. Mid Layer (Original)
        Emitter {
            group: "mid"
            anchors.fill: parent
            enabled: root.visible
            
            emitRate: root.particleCount * 0.2
            lifeSpan: 6000
            lifeSpanVariation: 2000
            
            size: 4
            sizeVariation: 2
            
            velocity: AngleDirection {
                angle: 270 
                angleVariation: 30
                magnitude: root.particleSpeed
                magnitudeVariation: 15
            }
            
            acceleration: AngleDirection {
                angle: 90 
                magnitude: 2
            }
        }
        
        // 3. Close Layer (Big, Fast, Foreground)
        Emitter {
            group: "close"
            anchors.fill: parent
            enabled: root.visible
            
            emitRate: root.particleCount * 0.05
            lifeSpan: 5000
            lifeSpanVariation: 1500
            
            size: 12
            sizeVariation: 5
            
            velocity: AngleDirection {
                angle: 270 
                angleVariation: 30
                magnitude: root.particleSpeed * 1.5
                magnitudeVariation: 20
            }
            
            acceleration: AngleDirection {
                angle: 90 
                magnitude: 3
            }
        }
    }
}
