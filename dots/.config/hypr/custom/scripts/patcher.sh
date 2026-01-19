#!/bin/bash

echo "Searching for files and applying fixes..."

# ==============================================================================
# 1. DYNAMICALLY FIND FILES (Don't guess paths)
# ==============================================================================
# Find the first matching file in the quickshell directory
DOCK_FILE=$(find "$HOME/.config/quickshell" -name "DockAppButton.qml" -print -quit)
OSD_FILE=$(find "$HOME/.config/quickshell" -name "OnScreenDisplay.qml" -print -quit)
NETWORK_FILE=$(find "$HOME/.config/quickshell" -name "Network.qml" -print -quit)
FOCUSGRAB_FILE=$(find "$HOME/.config/quickshell" -name "GlobalFocusGrab.qml" -print -quit)

echo "Found Dock File at:       $DOCK_FILE"
echo "Found OSD File at:        $OSD_FILE"
echo "Found Network File at:    $NETWORK_FILE"
echo "Found FocusGrab File at:  $FOCUSGRAB_FILE"

# ==============================================================================
# 2. FIX THE DOCK
# ==============================================================================
if [ -n "$DOCK_FILE" ]; then
    if grep -q "readonly property var desktopEntry" "$DOCK_FILE"; then
        sed -i 's/readonly property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)/property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)\n    Connections {\n        target: DesktopEntries\n        function onApplicationsChanged() {\n            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);\n        }\n    }/' "$DOCK_FILE"
        echo "[OK] Dock app fix applied."
    else
        echo "[SKIP] Dock fix already present."
    fi
else
    echo "[ERROR] DockAppButton.qml NOT FOUND."
fi

# ==============================================================================
# 3. FIX THE NATIVE POPUP
# ==============================================================================
if [ -n "$OSD_FILE" ]; then
    if ! grep -q "startupBlocked" "$OSD_FILE"; then
        sed -i '/function triggerOsd() {/i \    property bool startupBlocked: true\n    Timer {\n        interval: 5000\n        running: true\n        repeat: false\n        onTriggered: root.startupBlocked = false\n    }\n' "$OSD_FILE"
        sed -i '/function triggerOsd() {/a \        if (root.startupBlocked) return;' "$OSD_FILE"
        echo "[OK] Native Popup silence fix applied."
    else
        echo "[SKIP] Native Popup fix already present."
    fi
else
    echo "[ERROR] OnScreenDisplay.qml NOT FOUND."
fi

# ==============================================================================
# 4. FIX NETWORK.QML - WiFi Icon and Network Name Issues
# ==============================================================================
if [ -n "$NETWORK_FILE" ]; then
    echo "Updating Network.qml with fixed version..."
    # Copy Network.qml from qml folder
    QML_SRC="$HOME/.config/hypr/custom/qml/Network.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$NETWORK_FILE"
        echo "[OK] Network.qml copied from qml folder."
    else
        echo "[WARN] Network.qml not found in qml folder."
    fi
    echo "[OK] Network.qml updated with fixed version."
else
    echo "[ERROR] Network.qml NOT FOUND."
fi

# ==============================================================================
# 5. FIX GLOBALFOCUSGRAB.QML - Focus Management for Persistent Windows
# ==============================================================================
if [ -n "$FOCUSGRAB_FILE" ]; then
    echo "Checking GlobalFocusGrab.qml for fixes..."
    
    # Fix 1: Add hasActive function if not present
    if ! grep -q "function hasActive" "$FOCUSGRAB_FILE"; then
        sed -i '/function removeDismissable(window) {/,/^    }$/a\
\
    function hasActive(element) {\
        return element.activeFocus || Array.from(\
            element.children\
        ).some(\
            (child) => hasActive(child)\
        );\
    }' "$FOCUSGRAB_FILE"
        echo "[OK] Added hasActive function."
    else
        echo "[SKIP] hasActive function already present."
    fi
    
    # Fix 2: Update HyprlandFocusGrab windows property
    if grep -q 'windows: \[\.\.\.root\.persistent, \.\.\.root\.dismissable\]' "$FOCUSGRAB_FILE"; then
        sed -i 's|windows: \[\.\.\.root\.persistent, \.\.\.root\.dismissable\]|windows: root.dismissable.some(w => hasActive(w.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]|' "$FOCUSGRAB_FILE"
        echo "[OK] Updated HyprlandFocusGrab windows property for dynamic focus management."
    else
        echo "[SKIP] HyprlandFocusGrab windows property already updated."
    fi
    
    echo "[OK] GlobalFocusGrab.qml fixes completed."
else
    echo "[ERROR] GlobalFocusGrab.qml NOT FOUND."
fi

# ==============================================================================
# 6. FIX HYPRLAND 0.53+ CONFIG (Fullscreen & Layer rules)
# ==============================================================================
GENERAL_CONF="$HOME/.config/hypr/hyprland/general.conf"
RULES_CONF="$HOME/.config/hypr/hyprland/rules.conf"

if [ -f "$GENERAL_CONF" ]; then
    echo "Checking general.conf..."
    if grep -q "new_window_takes_over_fullscreen" "$GENERAL_CONF"; then
        sed -i 's/new_window_takes_over_fullscreen = 2/# new_window_takes_over_fullscreen = 2\n    on_focus_under_fullscreen = 2/' "$GENERAL_CONF"
        echo "[OK] Replaced deprecated fullscreen option."
    else
        echo "[SKIP] Fullscreen option already updated."
    fi
else
    echo "[ERROR] general.conf NOT FOUND."
fi

if [ -f "$RULES_CONF" ]; then
    echo "Checking rules.conf..."
    # Check for layerrule with comma syntax (e.g. layerrule = xray, .*)
    if grep -q "layerrule = [a-z]\+, " "$RULES_CONF"; then
        sed -i -E 's/layerrule = ([^,]*),[[:space:]]*(.*)/layerrule = \1 \2/' "$RULES_CONF"
        echo "[OK] Fixed layerrule syntax (removed commas)."
    else
        echo "[SKIP] Layerrule syntax already correct."
    fi
else
    echo "[ERROR] rules.conf NOT FOUND."
fi


# ==============================================================================
# 7. ADD POPUP FEATURE (PR #2742)
# ==============================================================================
QUICKSHELL_DIR="$HOME/.config/quickshell/ii"
SHELL_QML="$QUICKSHELL_DIR/shell.qml"
OTHER_POPUP="$QUICKSHELL_DIR/OtherPopup.qml"

if [ -d "$QUICKSHELL_DIR" ]; then
    echo "Checking Popup Feature..."
    
    # Create OtherPopup.qml if missing
    if [ ! -f "$OTHER_POPUP" ]; then
        # Copy OtherPopup.qml from qml folder
        QML_SRC="$HOME/.config/hypr/custom/qml/OtherPopup.qml"
        if [ -f "$QML_SRC" ]; then
            cp "$QML_SRC" "$OTHER_POPUP"
            echo "[OK] OtherPopup.qml copied from qml folder."
        else
            echo "[WARN] OtherPopup.qml not found in qml folder."
        fi
        echo "[OK] Created OtherPopup.qml."
    else
        echo "[SKIP] OtherPopup.qml already exists."
    fi

    # Patch shell.qml to include OtherPopup
    if [ -f "$SHELL_QML" ]; then
        if ! grep -q "OtherPopup {}" "$SHELL_QML"; then
            sed -i '/ReloadPopup {}/a \    OtherPopup {}' "$SHELL_QML"
            echo "[OK] Integrated OtherPopup into shell.qml."
        else
            echo "[SKIP] shell.qml already patched."
        fi
    else
        echo "[ERROR] shell.qml NOT FOUND."
    fi
else
    echo "[ERROR] Quickshell directory ($QUICKSHELL_DIR) NOT FOUND."
fi


echo ""
echo "=========================================="
echo "All Done! Summary:"
echo "=========================================="
[ -n "$DOCK_FILE" ] && echo "✓ DockAppButton.qml checked/patched"
[ -n "$OSD_FILE" ] && echo "✓ OnScreenDisplay.qml checked/patched"
[ -n "$NETWORK_FILE" ] && echo "✓ Network.qml updated with fixed version"
[ -n "$FOCUSGRAB_FILE" ] && echo "✓ GlobalFocusGrab.qml checked/patched"
echo "✓ Hyprland 0.53+ Config checked/patched"
echo "✓ Popup Feature (PR #2742) checked/implemented"
echo "=========================================="
echo ""
echo "Please restart Quickshell for changes to take effect."


# ==============================================================================
# 8. ADD NETWORK SPEED FEATURE
# ==============================================================================
QUICKSHELL_DIR="$HOME/.config/quickshell/ii"
NET_SPEED_FILE="$QUICKSHELL_DIR/modules/ii/bar/NetworkSpeed.qml"
RESOURCE_USAGE="$QUICKSHELL_DIR/services/ResourceUsage.qml"
BAR_CONTENT="$QUICKSHELL_DIR/modules/ii/bar/BarContent.qml"
CONFIG_QML="$QUICKSHELL_DIR/modules/common/Config.qml"

if [ -d "$QUICKSHELL_DIR" ]; then
    echo "Checking Network Speed Feature..."

    # 1. Create NetworkSpeed.qml
    if [ ! -f "$NET_SPEED_FILE" ]; then
        mkdir -p "$(dirname "$NET_SPEED_FILE")"
        # Copy NetworkSpeed.qml from qml folder
        QML_SRC="$HOME/.config/hypr/custom/qml/NetworkSpeed.qml"
        if [ -f "$QML_SRC" ]; then
            cp "$QML_SRC" "$NET_SPEED_FILE"
            echo "[OK] NetworkSpeed.qml copied from qml folder."
        else
            echo "[WARN] NetworkSpeed.qml not found in qml folder."
        fi
        echo "[OK] Created NetworkSpeed.qml."
    else
        echo "[SKIP] NetworkSpeed.qml already exists."
    fi

    # 2. Patch ResourceUsage.qml
    if ! grep -q "networkDownloadSpeed" "$RESOURCE_USAGE"; then
       # Properties
       sed -i '/property real swapUsedPercentage/a \    property real networkDownloadSpeed: 0\n    property real networkUploadSpeed: 0\n    property real lastRx: 0\n    property real lastTx: 0' "$RESOURCE_USAGE"
       # FileView
       sed -i '/FileView { id: fileStat/a \    FileView { id: fileNetDev; path: "/proc/net/dev" }' "$RESOURCE_USAGE"
       
       # Logic via Python
       python3 -c "
import sys
path = '$RESOURCE_USAGE'
try:
    with open(path, 'r') as f: content = f.read()
    # Use single quotes for inner raw string to avoid conflict
    logic = r'''
            // Network Speed
            fileNetDev.reload()
            var lines = fileNetDev.text().split('\n')
            var rx = 0; var tx = 0;
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (line.indexOf(':') === -1) continue
                var parts = line.split(/\s+/)
                if (parts.length > 9 && parts[0] !== 'lo:') {
                     if (parts[0].indexOf(':') !== -1) {
                         rx += Number(parts[1]); tx += Number(parts[9]);
                     }
                }
            }
            if (lastRx > 0) {
                 networkDownloadSpeed = rx - lastRx; networkUploadSpeed = tx - lastTx;
                 if (networkDownloadSpeed < 0) networkDownloadSpeed = 0;
                 if (networkUploadSpeed < 0) networkUploadSpeed = 0;
            }
            lastRx = rx; lastTx = tx;
'''
    if 'root.updateHistories()' in content and '// Network Speed' not in content:
       content = content.replace('root.updateHistories()', logic + '\n            root.updateHistories()')
       with open(path, 'w') as f: f.write(content)
except Exception as e:
    print('Error patching ResourceUsage:', e)
"
       echo "[OK] Patched ResourceUsage.qml."
    else
       echo "[SKIP] ResourceUsage.qml already patched."
    fi

    # 3. Patch BarContent.qml
    if ! grep -q "NetworkSpeed {" "$BAR_CONTENT"; then
        # Insert before // Weather
        sed -i '/\/\/ Weather/i \            NetworkSpeed {\n                Layout.alignment: Qt.AlignVCenter\n            }' "$BAR_CONTENT"
        echo "[OK] Added NetworkSpeed to BarContent.qml."
    else
        echo "[SKIP] BarContent.qml already has NetworkSpeed."
    fi
    
    # 4. Patch Config.qml
    if ! grep -q "showNetworkSpeed" "$CONFIG_QML"; then
        sed -i '/property JsonObject bar: JsonObject {/a \               property bool showNetworkSpeed: false' "$CONFIG_QML"
        echo "[OK] Added showNetworkSpeed to Config.qml."
    else
         echo "[SKIP] Config.qml already has showNetworkSpeed."
    fi
fi




# ==============================================================================
# 9. APP DRAWER FEATURE
# ==============================================================================
echo ""
echo "=========================================="
echo "Checking App Drawer Feature..."
echo "=========================================="

QUICKSHELL_DIR="$HOME/.config/quickshell/ii"
OVERVIEW_DIR="$QUICKSHELL_DIR/modules/ii/overview"
SHELL_QML="$QUICKSHELL_DIR/shell.qml"
KEYBINDS_FILE="$HOME/.config/hypr/custom/keybinds.conf"

if [ -d "$QUICKSHELL_DIR" ]; then
    mkdir -p "$OVERVIEW_DIR"

    # 1. Create list_apps.py
    if [ ! -f "$OVERVIEW_DIR/list_apps.py" ]; then
        # Copy list_apps.py from qml folder
        QML_SRC="$HOME/.config/hypr/custom/qml/list_apps.py"
        if [ -f "$QML_SRC" ]; then
            cp "$QML_SRC" "$OVERVIEW_DIR/list_apps.py"
            chmod +x "$OVERVIEW_DIR/list_apps.py"
            echo "[OK] list_apps.py copied from qml folder."
        else
            echo "[WARN] list_apps.py not found in qml folder."
        fi
        chmod +x "$OVERVIEW_DIR/list_apps.py"
        echo "[OK] Created list_apps.py"
    else
        echo "[SKIP] list_apps.py already exists"
    fi

    # 2. Create AppDrawerWindow.qml
    if [ ! -f "$OVERVIEW_DIR/AppDrawerWindow.qml" ]; then
        # Copy AppDrawerWindow.qml from qml folder (overview)
        QML_SRC="$HOME/.config/hypr/custom/qml/AppDrawerWindow.qml"
        if [ -f "$QML_SRC" ]; then
            cp "$QML_SRC" "$OVERVIEW_DIR/AppDrawerWindow.qml"
            echo "[OK] AppDrawerWindow.qml copied from qml folder."
        else
            echo "[WARN] AppDrawerWindow.qml not found in qml folder."
        fi
        echo "[OK] Created AppDrawerWindow.qml"
    else
        echo "[SKIP] AppDrawerWindow.qml already exists"
    fi

    # 3. Create ApplicationDrawer.qml (full embedded version)
    # Copy ApplicationDrawer.qml from qml folder (overview version)
    QML_SRC="$HOME/.config/hypr/custom/qml/ApplicationDrawer.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$OVERVIEW_DIR/ApplicationDrawer.qml"
        echo "[OK] ApplicationDrawer.qml copied from qml folder."
    else
        echo "[WARN] ApplicationDrawer.qml not found in qml folder."
    fi
    echo "[OK] Created/Updated ApplicationDrawer.qml"

    # 4. Patch shell.qml (add import AND component)
    if [ -f "$SHELL_QML" ]; then
        # Add import for overview module
        if ! grep -q 'import "modules/ii/overview"' "$SHELL_QML"; then
            sed -i '/import "panelFamilies"/a import "modules/ii/overview"' "$SHELL_QML"
            echo "[OK] Added overview module import to shell.qml"
        else
            echo "[SKIP] shell.qml already has overview import"
        fi
        
        # Add AppDrawerWindow component
        if ! grep -q "AppDrawerWindow {}" "$SHELL_QML"; then
            sed -i '/ReloadPopup {}/a \    AppDrawerWindow {}' "$SHELL_QML"
            echo "[OK] Added AppDrawerWindow to shell.qml"
        else
            echo "[SKIP] shell.qml already has AppDrawerWindow"
        fi
    fi

    # 5. Add keybind (SUPER+R)
    if [ -f "$KEYBINDS_FILE" ]; then
        if ! grep -q 'app-drawer' "$KEYBINDS_FILE"; then
            echo "" >> "$KEYBINDS_FILE"
            echo "# App Drawer" >> "$KEYBINDS_FILE"
            echo 'bind = SUPER, R, exec, qs -c ii ipc call app-drawer toggle' >> "$KEYBINDS_FILE"
            echo "[OK] Added SUPER+R keybind"
        else
            echo "[SKIP] Keybind already exists"
        fi
    fi

    echo "[DONE] App Drawer feature checked/installed"
else
    echo "[ERROR] Quickshell directory not found"
fi

# ==============================================================================
# 5. FIX SYSTEM MONITOR (Polish, Animations, Search) & GLOBAL BLUR
# ==============================================================================
echo "Applying Polish to System Monitor and App Drawer..."

SYSMON_WINDOW=$(find "$HOME/.config/quickshell" -name "SystemMonitorWindow.qml" -print -quit)
APPDRAWER_WINDOW=$(find "$HOME/.config/quickshell" -name "AppDrawerWindow.qml" -print -quit)
SYSMON_CONTENT=$(find "$HOME/.config/quickshell" -name "SystemMonitor.qml" -print -quit)
APPDRAWER_CONTENT=$(find "$HOME/.config/quickshell" -name "ApplicationDrawer.qml" -print -quit)

# SystemMonitorWindow.qml
if [ -n "$SYSMON_WINDOW" ]; then
    echo "Patching SystemMonitorWindow.qml..."
    # Copy SystemMonitorWindow.qml from qml folder (polish)
    QML_SRC="$HOME/.config/hypr/custom/qml/SystemMonitorWindow.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$SYSMON_WINDOW"
        echo "[OK] SystemMonitorWindow.qml copied from qml folder."
    else
        echo "[WARN] SystemMonitorWindow.qml not found in qml folder."
    fi
fi

# AppDrawerWindow.qml
if [ -n "$APPDRAWER_WINDOW" ]; then
    echo "Patching AppDrawerWindow.qml..."
    # Copy AppDrawerWindow.qml from qml folder (polish)
    QML_SRC="$HOME/.config/hypr/custom/qml/AppDrawerWindow.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$APPDRAWER_WINDOW"
        echo "[OK] AppDrawerWindow.qml copied from qml folder."
    else
        echo "[WARN] AppDrawerWindow.qml not found in qml folder."
    fi
fi

# SystemMonitor.qml
if [ -n "$SYSMON_CONTENT" ]; then
    echo "Patching SystemMonitor.qml..."
    # Copy SystemMonitor.qml from qml folder
    QML_SRC="$HOME/.config/hypr/custom/qml/SystemMonitor.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$SYSMON_CONTENT"
        echo "[OK] SystemMonitor.qml copied from qml folder."
    else
        echo "[WARN] SystemMonitor.qml not found in qml folder."
    fi
fi

# ApplicationDrawer.qml
if [ -n "$APPDRAWER_CONTENT" ]; then
    echo "Patching ApplicationDrawer.qml..."
    # Copy ApplicationDrawer.qml from qml folder (polish version)
    QML_SRC="$HOME/.config/hypr/custom/qml/ApplicationDrawer.qml"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$APPDRAWER_CONTENT"
        echo "[OK] ApplicationDrawer.qml copied from qml folder."
    else
        echo "[WARN] ApplicationDrawer.qml not found in qml folder."
    fi
fi

# get_processes.py
if [ -n "$SYSMON_CONTENT" ]; then
    GET_PROC_SCRIPT="$(dirname "$SYSMON_CONTENT")/get_processes.py"
    echo "Creating get_processes.py..."
    # Copy get_processes.py from qml folder
    QML_SRC="$HOME/.config/hypr/custom/qml/get_processes.py"
    if [ -f "$QML_SRC" ]; then
        cp "$QML_SRC" "$GET_PROC_SCRIPT"
        chmod +x "$GET_PROC_SCRIPT"
        echo "[OK] get_processes.py copied from qml folder."
    else
        echo "[WARN] get_processes.py not found in qml folder."
    fi
    chmod +x "$GET_PROC_SCRIPT"
fi

# rules.conf
RULES_CONF="$HOME/.config/hypr/custom/rules.conf"
if [ -f "$RULES_CONF" ]; then
    if ! grep -q "layerrule = match:namespace .*, xray 0" "$RULES_CONF"; then
        echo "Applying Global Blur Fix and Animations to rules.conf..."
        echo "" >> "$RULES_CONF"
        echo "# Custom Polished Rules" >> "$RULES_CONF"
        echo "layerrule = match:namespace .*, xray 0" >> "$RULES_CONF"
    else
        echo "[SKIP] Global blur fix already present."
    fi
     if ! grep -q "layerrule = match:namespace app-drawer, no_anim on" "$RULES_CONF"; then
         echo "layerrule = match:namespace app-drawer, no_anim on" >> "$RULES_CONF"
     fi
     if ! grep -q "layerrule = match:namespace system-monitor, no_anim on" "$RULES_CONF"; then
         echo "layerrule = match:namespace system-monitor, no_anim on" >> "$RULES_CONF"
     fi
fi

echo "Detailed Polish Patch Applied Successfully!"


# ==============================================================================
# SYSTEM MONITOR MODULE - Create directory & files if missing
# ==============================================================================
SYSMON_DIR="$HOME/.config/quickshell/ii/modules/ii/sysmon"
if [ ! -d "$SYSMON_DIR" ]; then
    echo "Creating sysmon module directory..."
    mkdir -p "$SYSMON_DIR"
    
    # Create qmldir
    cat << 'EOF_QMLDIR' > "$SYSMON_DIR/qmldir"
module qs.modules.ii.sysmon
SystemMonitor 1.0 SystemMonitor.qml
SystemMonitorWindow 1.0 SystemMonitorWindow.qml
EOF_QMLDIR
    echo "[OK] sysmon module directory created."

    # Copy SystemMonitor.qml from scratch if exists
    SCRATCH_SYSMON="$HOME/.config/hypr/custom/qml/SystemMonitor.qml"
    if [ -f "$SCRATCH_SYSMON" ]; then
        cp "$SCRATCH_SYSMON" "$SYSMON_DIR/"
        echo "[OK] SystemMonitor.qml copied from scratch."
    else
        echo "[WARN] SystemMonitor.qml not found in scratch - you may need to copy it manually."
    fi
    
    # Copy get_processes.py from scratch if exists
    SCRATCH_PROC="$HOME/.config/hypr/custom/qml/get_processes.py"
    if [ -f "$SCRATCH_PROC" ]; then
        cp "$SCRATCH_PROC" "$SYSMON_DIR/"
        chmod +x "$SYSMON_DIR/get_processes.py"
        echo "[OK] get_processes.py copied from scratch."
    else
        echo "[WARN] get_processes.py not found in scratch - you may need to copy it manually."
    fi
else
    echo "[SKIP] sysmon directory already exists."
fi

# ==============================================================================
# SYSTEM MONITOR WINDOW - Copy from qml folder
# ==============================================================================
SYSMON_WINDOW_FILE="$SYSMON_DIR/SystemMonitorWindow.qml"
QML_SOURCE="$HOME/.config/hypr/custom/qml/SystemMonitorWindow.qml"
if [ -f "$QML_SOURCE" ]; then
    cp "$QML_SOURCE" "$SYSMON_WINDOW_FILE"
    echo "[OK] SystemMonitorWindow.qml copied from qml folder."
else
    echo "[WARN] SystemMonitorWindow.qml not found in qml folder."
fi
echo "[OK] SystemMonitorWindow.qml patched."

# ==============================================================================
# SYSTEM MONITOR - FocusScope Fix (sed patch for large file)
# ==============================================================================
SYSMON_FILE="$SYSMON_DIR/SystemMonitor.qml"
if [ -f "$SYSMON_FILE" ]; then
    if grep -q "^Item {" "$SYSMON_FILE" || grep -q "^Item{" "$SYSMON_FILE"; then
        sed -i 's/^Item {/FocusScope {/' "$SYSMON_FILE"
        sed -i 's/^Item{/FocusScope{/' "$SYSMON_FILE"
        echo "[OK] SystemMonitor.qml root changed to FocusScope."
    else
        echo "[SKIP] SystemMonitor.qml already uses FocusScope."
    fi
else
    echo "[WARN] SystemMonitor.qml not found - you may need to copy it manually."
fi
# ==============================================================================
# APP DRAWER WINDOW - Copy from qml folder
# ==============================================================================
APPDRAWER_DEST="$HOME/.config/quickshell/ii/modules/ii/overview/AppDrawerWindow.qml"
APPDRAWER_SRC="$HOME/.config/hypr/custom/qml/AppDrawerWindow.qml"
if [ -f "$APPDRAWER_SRC" ]; then
    cp "$APPDRAWER_SRC" "$APPDRAWER_DEST"
    echo "[OK] AppDrawerWindow.qml copied from qml folder."
else
    echo "[WARN] AppDrawerWindow.qml not found in qml folder."
fi
# ==============================================================================
# APPLICATION DRAWER - FocusScope Fix
# ==============================================================================
APPDRAWER_FILE=$(find "$HOME/.config/quickshell" -name "ApplicationDrawer.qml" -path "*/overview/*" -print -quit)
if [ -n "$APPDRAWER_FILE" ]; then
    if grep -q "^Item {" "$APPDRAWER_FILE" || grep -q "^Item{" "$APPDRAWER_FILE"; then
        sed -i 's/^Item {/FocusScope {/' "$APPDRAWER_FILE"
        sed -i 's/^Item{/FocusScope{/' "$APPDRAWER_FILE"
        echo "[OK] ApplicationDrawer.qml root changed to FocusScope."
    else
        echo "[SKIP] ApplicationDrawer.qml already uses FocusScope."
    fi
else
    echo "[WARN] ApplicationDrawer.qml NOT FOUND."
fi

# ==============================================================================
# SHELL INTEGRATION - Add sysmon import & loader to IllogicalImpulseFamily
# ==============================================================================
FAMILY_FILE=$(find "$HOME/.config/quickshell" -name "IllogicalImpulseFamily.qml" -print -quit)
if [ -n "$FAMILY_FILE" ]; then
    # Add import if missing
    if ! grep -q "qs.modules.ii.sysmon" "$FAMILY_FILE"; then
        echo "Adding sysmon import to IllogicalImpulseFamily.qml..."
        sed -i '/import qs.modules.ii.wallpaperSelector/a import qs.modules.ii.sysmon' "$FAMILY_FILE"
        echo "[OK] sysmon import added."
    else
        echo "[SKIP] sysmon import already present."
    fi
    
    # Add loader if missing
    if ! grep -q "SystemMonitorWindow" "$FAMILY_FILE"; then
        echo "Adding SystemMonitorWindow loader..."
        sed -i '/PanelLoader { component: WallpaperSelector {} }/a \    PanelLoader { component: SystemMonitorWindow {} }' "$FAMILY_FILE"
        echo "[OK] SystemMonitorWindow loader added."
    else
        echo "[SKIP] SystemMonitorWindow loader already present."
    fi
else
    echo "[WARN] IllogicalImpulseFamily.qml NOT FOUND."
fi

echo ""
echo "=============================================="
echo "  All patches applied successfully!"
echo "  Run: pkill -f 'qs.*ii' && qs -c ii &"
echo "=============================================="
