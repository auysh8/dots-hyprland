import sys

file_path = "/home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/ii/overview/ApplicationDrawer.qml"

with open(file_path, "r") as f:
    content = f.read()

# Replace Main Content ColumnLayout with a Rectangle wrapping it
old_main_content = """            // --- Main Content ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                spacing: 16

                // Header & Search"""

new_main_content = """            // --- Main Content ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.large

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Header & Search"""

content = content.replace(old_main_content, new_main_content)

# Remove the inner Rectangle around the grid
old_grid_container = """                // Grid Container
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.large

                    StyledFlickable {"""

new_grid_container = """                // Grid Container
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledFlickable {"""

content = content.replace(old_grid_container, new_grid_container)

insert_point = "        // Context Menu Overlay (positioned outside layout to not affect grid)"
content = content.replace(insert_point, "            }\\n" + insert_point)

# I wrote `\\n` so it produces an actual newline instead of a python syntax error. Wait, normal string literal `\n` works, but I wrote it across lines? Oh wait, in previous one I wrote `"            }\n" + insert_point`. That's valid. The error showed `SyntaxError: unterminated string literal`. 
# Wait, look at the error log from earlier:
# content = content.replace(insert_point, "            }
#                                            ^
# I will use triple quotes to be safe.

content = content.replace(insert_point, "            }\n" + insert_point)

with open(file_path, "w") as f:
    f.write(content)
