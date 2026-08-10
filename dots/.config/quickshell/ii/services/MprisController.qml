pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
        id: root;
        property var players: {
                // Ensure dependency on Mpris.players.values
                let rawPlayers = Mpris.players.values;
                let arr = rawPlayers.filter(player => {
                        if (!isRealPlayer(player)) return false;
                        // Hide music-backend when it has nothing playing
                        if (player.dbusName === "org.mpris.MediaPlayer2.music-backend"
                            && !player.trackTitle
                            && player.playbackState === MprisPlaybackState.Stopped) {
                                return false;
                        }
                        return true;
                });
                return arr.sort((a, b) => {
                        if (a.dbusName === "org.mpris.MediaPlayer2.music-backend") return -1;
                        if (b.dbusName === "org.mpris.MediaPlayer2.music-backend") return 1;
                        return 0;
                });
        }
        property MprisPlayer trackedPlayer: null;
        property MprisPlayer activePlayer: trackedPlayer ?? players[0] ?? null;
        signal trackChanged(reverse: bool);

        property bool __reverse: false;

        property var activeTrack;

        readonly property bool hasActivePlasmaIntegration: Mpris.players.values.some(
                p => (p.dbusName || "").includes("plasma-browser-integration")
        )
        function isRealPlayer(player) {
            if (!Config.options.media.filterDuplicatePlayers) {
                return true;
            }
            let name = player.dbusName || "";
            let isBrowserNative = name.includes("firefox") || name.includes("chromium") || name.includes("chrome");
            if (hasActivePlasmaIntegration && isBrowserNative && !name.includes("plasma-browser-integration")) {
                console.log("[MprisController] Filtering out duplicate native browser player:", name);
                return false;
            }
            if (name.includes("playerctld")) return false;
            if (name.endsWith(".mpd") && !name.endsWith("MediaPlayer2.mpd")) return false;
            return true;
        }

        // Original stuff from fox below
        Instantiator {
                model: root.players;

                Connections {
                        required property MprisPlayer modelData;
                        target: modelData;

                        Component.onCompleted: {
                                if (root.trackedPlayer == null || modelData.isPlaying) {
                                        root.trackedPlayer = modelData;
                                }
                        }

                        Component.onDestruction: {
                                if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
                                        for (const player of root.players) {
                                                if (player.playbackState.isPlaying) {
                                                        root.trackedPlayer = player;
                                                        break;
                                                }
                                        }

                                        if (trackedPlayer == null && root.players.length != 0) {
                                                trackedPlayer = root.players[0];
                                        }
                                }
                        }

                        function onPlaybackStateChanged() {
                                if (root.trackedPlayer !== modelData && modelData.playbackState === MprisPlaybackState.Playing) {
                    root.trackedPlayer = modelData;
                }
                        }
                }
        }

    // Watchdog to catch players that start playing without emitting a proper signal (common with KDE Connect/Web browsers)
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            // If current player is NOT playing, look for one that IS
            if (!root.trackedPlayer || root.trackedPlayer.playbackState !== MprisPlaybackState.Playing) {
                for (const player of root.players) {
                    if (player.playbackState === MprisPlaybackState.Playing) {
                        root.trackedPlayer = player;
                        return;
                    }
                }
            }
        }
    }

        Connections {
                target: activePlayer

                function onPostTrackChanged() {
                        root.updateTrack();
                }

                function onTrackArtUrlChanged() {
                        // console.log("arturl:", activePlayer.trackArtUrl)
                        // root.updateTrack();
                        if (root.activePlayer && root.activeTrack && root.activePlayer.uniqueId == root.activeTrack.uniqueId && root.activePlayer.trackArtUrl != root.activeTrack.artUrl) {
                                // cantata likes to send cover updates *BEFORE* updating the track info.
                                // as such, art url changes shouldn't be able to break the reverse animation
                                const r = root.__reverse;
                                root.updateTrack();
                                root.__reverse = r;

                        }
                }
        }

        onActivePlayerChanged: this.updateTrack();

        function updateTrack() {
                let meta = this.activePlayer?.metadata || {};
                let trackUrl = meta["xesam:url"] || meta["url"] || this.activePlayer?.url || this.activePlayer?.trackUrl || "";
                this.activeTrack = {
                        uniqueId: this.activePlayer?.uniqueId ?? 0,
                        artUrl: this.activePlayer?.trackArtUrl ?? "",
                        title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
                        artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
                        album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
                        url: String(trackUrl),
                };

                this.trackChanged(__reverse);
                this.__reverse = false;
        }

        property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
        property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
        function togglePlaying() {
                if (this.canTogglePlaying) this.activePlayer.togglePlaying();
        }

        property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
        function previous() {
                if (this.canGoPrevious) {
                        this.__reverse = true;
                        this.activePlayer.previous();
                }
        }

        property bool canGoNext: this.activePlayer?.canGoNext ?? false;
        function next() {
                if (this.canGoNext) {
                        this.__reverse = false;
                        this.activePlayer.next();
                }
        }

        property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;

        property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
        property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
        function setLoopState(loopState: var) {
                if (this.loopSupported) {
                        this.activePlayer.loopState = loopState;
                }
        }

        property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
        property bool hasShuffle: this.activePlayer?.shuffle ?? false;
        function setShuffle(shuffle: bool) {
                if (this.shuffleSupported) {
                        this.activePlayer.shuffle = shuffle;
                }
        }

        function setActivePlayer(player: MprisPlayer) {
                const targetPlayer = player ?? root.players[0];
                console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

                if (targetPlayer && this.activePlayer) {
                        this.__reverse = root.players.indexOf(targetPlayer) < root.players.indexOf(this.activePlayer);
                } else {
                        // always animate forward if going to null
                        this.__reverse = false;
                }

                this.trackedPlayer = targetPlayer;
        }

        IpcHandler {
                target: "mpris"

                function pauseAll(): void {
                        for (const player of root.players) {
                                if (player.canPause) player.pause();
                        }
                }

                function playPause(): void { root.togglePlaying(); }
                function previous(): void { root.previous(); }
                function next(): void { root.next(); }
        }
}
