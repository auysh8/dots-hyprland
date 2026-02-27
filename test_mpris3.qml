import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Window {
    width: 200; height: 200
    Component.onCompleted: {
        for(let p of Mpris.players.values) {
            console.log(p.dbusName, p.trackTitle, "(isPlaying:" + p.isPlaying + ")", "(art:" + p.trackArtUrl + ")")
        }
        Qt.quit()
    }
}
