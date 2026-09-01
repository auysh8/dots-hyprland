pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // An rfkill soft block sits underneath BlueZ, and an adapter under one
    // cannot be powered on: the assignment goes through, nothing is raised, and
    // the switch that made it springs back by itself. Every control offering to
    // turn Bluetooth on comes through here, so the block is lifted first and the
    // adapter asked again once rfkill has answered.
    //
    // Power is asked for before the unblock as well, so a machine where rfkill
    // is absent or refuses behaves exactly as it did.
    //
    // Turning Bluetooth off leaves any block alone. The switch offers to stop
    // this machine using Bluetooth, not to hold the radio down for everything
    // else on it, and a block laid here would outlive the shell.
    property bool wantEnabled: false

    function setEnabled(on) {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter)
            return;
        root.wantEnabled = on;
        adapter.enabled = on;
        if (on && !radioUnblock.running)
            radioUnblock.running = true;
    }

    function toggle() {
        root.setEnabled(!root.enabled);
    }

    function toggleBluetooth(enable) {
        if (enable === undefined) {
            root.toggle();
        } else {
            root.setEnabled(enable);
        }
    }

    Process {
        id: radioUnblock
        command: ["rfkill", "unblock", "bluetooth"]
        // Asked again rather than assumed: the unblock takes long enough to lose
        // a race against someone turning Bluetooth straight back off, and an
        // answer arriving late must not overrule them.
        onExited: {
            if (root.wantEnabled && Bluetooth.defaultAdapter)
                Bluetooth.defaultAdapter.enabled = true;
        }
    }

    // BlueZ restores the adapter state at login but does not request a new
    // connection to remembered devices. Ask trusted audio devices once during
    // shell startup, after bluetoothd has had a chance to populate the device
    // list.

    function reconnectTrustedAudioDevicesAtStartup() {
        startupReconnectTimer.restart();
    }

    function isAudioDevice(device) {
        return (device.icon ?? "").toLowerCase().includes("audio");
    }

    Timer {
        id: startupReconnectTimer
        interval: 4000
        repeat: false

        onTriggered: {
            for (const device of Bluetooth.devices.values) {
                if (device.trusted && isAudioDevice(device) && !device.connected)
                    device.connect();
            }
        }
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }

    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
}
