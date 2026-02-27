import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Window {
    width: 300; height: 300; visible: true;
    Component.onCompleted: {
        console.log("Found players:", Mpris.players.values.length);
        for(let i = 0; i < Mpris.players.values.length; i++) {
            let p = Mpris.players.values[i];
            console.log("DBUS:", p.dbusName,
                "Title:'" + p.trackTitle + "'",
                "Artist:'" + p.trackArtist + "'",
                "State:", p.playbackState);
        }
        Qt.quit();
    }
}
