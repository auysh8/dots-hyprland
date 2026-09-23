import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property bool fingerScanFailed: false
    readonly property bool fingerActive: fingerPam.active
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        root.fingerScanFailed = false;
        stopFingerPam();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
            // Restart fingerprint scanning after idle reset so it doesn't
            // go dead for the rest of the lock session.
            if (GlobalStates.screenLocked) {
                root.tryFingerUnlock();
            }
        }
    }

    Timer {
        id: fingerFailResetTimer
        interval: 2500
        onTriggered: {
            root.fingerScanFailed = false;
            // Retry after cooldown (covers both Failed and Error cases)
            if (GlobalStates.screenLocked) {
                root.tryFingerUnlock();
            }
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            fingerScanFailed = false;
            GlobalStates.screenUnlockFailed = false;
            // Pause fingerprint while typing so they don't race each other
            stopFingerPam();
        } else {
            // Text was cleared — resume fingerprint scanning
            tryFingerUnlock();
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (!root.fingerprintsConfigured && !fingerprintCheckProc.running) {
            fingerprintCheckProc.running = true;
        }
        if (root.fingerprintsConfigured && !fingerPam.active) {
            fingerPam.start();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.Failed) {
                root.fingerScanFailed = true;
                fingerFailResetTimer.restart();
                tryFingerUnlock();
            } else if (result == PamResult.Error) {
                // Wait before retrying on error to avoid an instant crash loop
                fingerFailResetTimer.restart();
            }
        }
    }

    onFingerprintsConfiguredChanged: {
        if (fingerprintsConfigured && GlobalStates.screenLocked && !fingerPam.active) {
            fingerPam.start();
        }
    }
}
