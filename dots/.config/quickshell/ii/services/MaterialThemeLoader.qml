pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        if (!fileContent) return;
        try {
            const json = JSON.parse(fileContent)
            Quickshell.execDetached(["bash", "-c", `echo "ThemeLoader: Starting application of colors" >> /tmp/quickshell_theme_debug.log`])
            for (const key in json) {
                if (json.hasOwnProperty(key)) {
                    if (key === "darkmode" || key === "transparent") {
                        Appearance.m3colors[key] = json[key]
                        continue
                    }
                    const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                    const m3Key = `m3${camelCaseKey.charAt(0).toLowerCase()}${camelCaseKey.slice(1)}`
                    
                    if (m3Key in Appearance.m3colors) {
                        Appearance.m3colors[m3Key] = json[key]
                    }
                }
            }

            if (json.darkmode !== undefined) {
                 Appearance.m3colors.darkmode = json.darkmode
            } else {
                const bg = Appearance.m3colors.m3background
                Appearance.m3colors.darkmode = (bg.hslLightness < 0.5)
            }
            
            Appearance.triggerColorUpdate()
            Quickshell.execDetached(["bash", "-c", `echo "ThemeLoader: Successfully updated theme, darkmode=${Appearance.m3colors.darkmode}" >> /tmp/quickshell_theme_debug.log`])
        } catch (e) {
            Quickshell.execDetached(["bash", "-c", `echo "ThemeLoader ERROR: ${e}" >> /tmp/quickshell_theme_debug.log`])
        }
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView {
        id: themeFileView
        path: root.filePath.startsWith("/") ? ("file://" + root.filePath) : root.filePath
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            if (loaded) {
                const fileContent = themeFileView.text()
                root.applyColors(fileContent)
            }
        }
        onLoadFailed: root.resetFilePathNextTime();
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", currentlyDark ? "light" : "dark", "--noswitch"]);
    }

    GlobalShortcut {
        name: "toggleLightDark"
        description: "Toggles between dark theme and light theme"

        onPressed: {
            root.toggleLightDark();
        }
    }

    IpcHandler {
        target: "theme"

        function reload(): void {
            root.reapplyTheme()
        }

        function toggleLightDark(): void {
            root.toggleLightDark();
        }
    }
}
