pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.modules.common

/**
 * Shared audio visualizer service.
 * Manages a single background cava process and broadcasts frequency bars
 * to GlobalStates.visualizerPoints, eliminating duplicate FFT processing.
 */
Singleton {
    id: root

    function load(): void {}

    // Track active DynamicIsland instances across monitors
    property var activeIslands: ({})
    property bool dynamicIslandActive: false

    function setIslandActive(screenName: string, active: bool): void {
        let copy = Object.assign({}, activeIslands);
        if (active) {
            copy[screenName] = true;
        } else {
            delete copy[screenName];
        }
        activeIslands = copy;
        dynamicIslandActive = Object.keys(copy).length > 0;
    }

    // MediaControls popup state
    readonly property bool mediaControlsActive: GlobalStates.mediaControlsOpen

    // Background visualizer widget state
    readonly property bool backgroundWidgetEnabled: (Config.options?.background?.widgets?.visualizer?.enable ?? false)
        && !GlobalStates.screenLocked
        && !GlobalStates.overviewOpen

    // Any visualizer consumer visible
    readonly property bool anyConsumerActive: dynamicIslandActive || mediaControlsActive || backgroundWidgetEnabled

    // Master execution condition: Only run if config is ready, an MPRIS player is playing, and at least one visualizer needs data
    readonly property bool shouldRun: Config.ready
        && MprisController.isPlaying
        && anyConsumerActive

    property list<real> points: []

    Process {
        id: cavaProc
        running: root.shouldRun
        command: ["cava", "-p", `${Directories.scripts}/cava/raw_output_config.txt`]

        onRunningChanged: {
            if (!cavaProc.running) {
                root.points = [];
                GlobalStates.visualizerPoints = [];
            }
        }

        stdout: SplitParser {
            onRead: data => {
                let parsed = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.points = parsed;
                GlobalStates.visualizerPoints = parsed;
            }
        }
    }
}
