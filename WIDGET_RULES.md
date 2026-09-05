# Quickshell Shared Widgets Catalog & Architecture Guide

This document is the complete index and usage reference for all **166 shared widgets** available in [`dots/.config/quickshell/ii/modules/common/widgets/`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets).

Always import and use these widgets instead of building raw primitives (`Text`, `Rectangle`, `MouseArea`) from scratch.

---

## 1. How to Import

In any QML component, include the widget module:

```qml
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.widgets.shapes // When using MaterialShape
```

---

## 2. Complete Widget Inventory (166 Widgets)

### Category 1: Typography & Text Display

| Component | Summary & Usage |
| :--- | :--- |
| [`StyledText`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledText.qml) | Primary text element across the entire shell. Automatically loads variable axes, switches to tabular font for digits, supports `animateChange`, and applies theme subpixel rendering. |
| [`SqueezedAnnotationStyledText`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/SqueezedAnnotationStyledText.qml) | Displays a main string with a subscript/annotation that smoothly squeezes/truncates when horizontal space is constrained. |
| [`ContentSubsectionLabel`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ContentSubsectionLabel.qml) | Pre-formatted section heading label for settings and options pages. |
| [`WindowDialogTitle`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogTitle.qml) | Standard bold heading for modal dialogs. |
| [`WindowDialogParagraph`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogParagraph.qml) | Standard body text paragraph formatted for dialogs. |
| [`WindowDialogSectionHeader`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogSectionHeader.qml) | Grouping header inside expanding dialogs. |

---

### Category 2: Icons, Media & Visual Assets

| Component | Summary & Usage |
| :--- | :--- |
| [`MaterialSymbol`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialSymbol.qml) | Google Material Symbols Rounded font icon. Supports `iconSize`, `fill` (0 to 1), and `color`. |
| [`OptionalMaterialSymbol`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/OptionalMaterialSymbol.qml) | Conditionally displays a symbol or collapses to zero width/height when empty. |
| [`CustomIcon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/CustomIcon.qml) | Loads custom SVG/PNG icon paths with tinting. |
| [`AppIcon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AppIcon.qml) | Desktop application icon resolver based on `.desktop` ID or binary name with fallback icon themes. |
| [`DirectoryIcon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DirectoryIcon.qml) | Standard folder icon for file trees. |
| [`Favicon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Favicon.qml) | Downloads and displays website favicons with local caching. |
| [`NotificationAppIcon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationAppIcon.qml) | Application icon badge specifically for notifications. |
| [`CliphistImage`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/CliphistImage.qml) | Decodes and renders clipboard image previews from `cliphist`. |
| [`ThumbnailImage`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ThumbnailImage.qml) | Asynchronous cached image thumbnail with fallback skeleton. |
| [`StyledImage`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledImage.qml) | Image element with corner radius clipping and smooth fade-in. |
| [`AttachedFileIndicator`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AttachedFileIndicator.qml) | Chip showing file attachment status with remove button. |
| [`BlurredArtBackground`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/BlurredArtBackground.qml) | Album art backdrop with gaussian blur. |
| [`FastBlurred`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FastBlurred.qml) | Fast hardware-accelerated blur wrapper. |
| [`StyledBlurEffect`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledBlurEffect.qml) | Reusable backdrop blur layer. |
| [`MaskMultiEffect`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaskMultiEffect.qml) | Combines mask, blur, and opacity shaders. |

---

### Category 3: Buttons & Interactivity

| Component | Summary & Usage |
| :--- | :--- |
| [`RippleButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/RippleButton.qml) | Standard button with Material Design ink ripple, toggled states, hover states, and cursor management. |
| [`RippleButtonWithIcon`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/RippleButtonWithIcon.qml) | Convenience wrapper combining `RippleButton`, `MaterialSymbol`, and text. |
| [`FloatingActionButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FloatingActionButton.qml) / `Fab` | Elevated circular/rounded action button with elevation shadow and bounce animation. |
| [`ToolbarPairedFab`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ToolbarPairedFab.qml) | Dual-action joined FAB button for toolbars. |
| [`ButtonGroup`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ButtonGroup.qml) | Horizontal segmented button group with unified borders. |
| [`GroupButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/GroupButton.qml) | Individual segment button designed to be placed inside a `ButtonGroup`. |
| [`FlowButtonGroup`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FlowButtonGroup.qml) | Wrap-around flow container for buttons. |
| [`VerticalButtonGroup`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/VerticalButtonGroup.qml) | Vertical segmented button group. |
| [`CircleUtilButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/CircleUtilButton.qml) | Circular utility icon button (Close, Back, Expand). |
| [`ToolbarButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ToolbarButton.qml) | Text button styled for top/bottom toolbars. |
| [`IconToolbarButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/IconToolbarButton.qml) | Icon-only button styled for toolbars. |
| [`IconAndTextToolbarButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/IconAndTextToolbarButton.qml) | Icon + text toolbar button. |
| [`VibrantToolbarButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/VibrantToolbarButton.qml) | High-contrast saturated button for prominent toolbar actions. |
| [`ToolbarTabBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ToolbarTabBar.qml) & `ToolbarTabButton` | Horizontal tab navigation bar for toolbars. |
| [`SecondaryTabBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/SecondaryTabBar.qml) & `SecondaryTabButton` | Sub-tab navigation bar. |
| [`VerticalTabBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/VerticalTabBar.qml) | Vertical navigation tabs. |
| [`NavigationRail`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NavigationRail.qml) | Material 3 vertical navigation rail sidebar. |
| [`NavigationRailButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NavigationRailButton.qml) | Individual rail item with icon, label pill, and active indicator. |
| [`NavigationRailExpandButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NavigationRailExpandButton.qml) | Rail collapse/expand toggle button. |
| [`NavigationRailTabArray`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NavigationRailTabArray.qml) | Array repeater for navigation rail items. |
| [`MenuButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MenuButton.qml) | Button that anchors and opens a popup dropdown menu. |
| [`DialogButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DialogButton.qml) | Confirm/Cancel action button for modal dialogs. |
| [`LightDarkPreferenceButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/LightDarkPreferenceButton.qml) | Button to toggle light and dark theme mode. |
| [`SelectionGroupButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/SelectionGroupButton.qml) | Selectable option button for choice groups. |
| [`DockButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DockButton.qml) | Icon button for bottom dock launchers. |
| [`DockSeparator`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DockSeparator.qml) | Vertical divider line for the dock. |
| [`ButtonMouseArea`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ButtonMouseArea.qml) | Reusable mouse area handling hover, pressed, and pointing hand cursor. |
| [`PointingHandInteraction`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/PointingHandInteraction.qml) | Transparent mouse area setting cursor to pointing hand. |
| [`PointingHandLinkHover`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/PointingHandLinkHover.qml) | Link-hover handler for hyperlinks. |
| [`StateLayer`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StateLayer.qml) & `StateOverlay` | Material state layers (hover, focus, pressed tint overlays). |

---

### Category 4: Form Controls & Inputs

| Component | Summary & Usage |
| :--- | :--- |
| [`MaterialTextField`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialTextField.qml) | Single-line text input with focus ring and clear button. |
| [`StyledTextInput`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledTextInput.qml) | Minimalist styled text input field. |
| [`MaterialTextArea`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialTextArea.qml) / `StyledTextArea` | Multi-line text edit box with auto-scrolling and line wrap. |
| [`ToolbarTextField`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ToolbarTextField.qml) | Compact search/input bar tailored for toolbars. |
| [`StyledSlider`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledSlider.qml) | Smooth slider with active filled track, drag handle, and hover effects. |
| [`StyledSwitch`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledSwitch.qml) | Material 3 animated toggle switch. |
| [`StyledRadioButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledRadioButton.qml) | Radio selection button with animated dot. |
| [`StyledSpinBox`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledSpinBox.qml) | Numeric stepper box with +/- buttons. |
| [`StyledComboBox`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledComboBox.qml) | Dropdown selector with popup list. |
| [`StyledComboBoxSearch`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledComboBoxSearch.qml) | Dropdown selector with integrated fuzzy search. |
| [`ClockPicker`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ClockPicker.qml) | Visual radial clock time picker. |
| [`ColorSelectionArray`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ColorSelectionArray.qml) | Swatch picker array for selecting theme colors. |

---

### Category 5: Config-Bound Option Widgets (`Config*`)

These components bind directly to `Config.options` and save changes persistently:

| Component | Summary & Usage |
| :--- | :--- |
| [`ConfigRow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigRow.qml) | Standard settings row with title, description, and slot for control. |
| [`ConfigSwitch`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigSwitch.qml) | Toggle switch bound to a persistent boolean config option. |
| [`ConfigSlider`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigSlider.qml) | Slider bound to a persistent numeric config option. |
| [`ConfigComboBox`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigComboBox.qml) | Dropdown bound to a persistent config option. |
| [`ConfigSpinBox`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigSpinBox.qml) | Spinbox bound to a persistent integer config option. |
| [`ConfigTextArea`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigTextArea.qml) | Multi-line text field bound to a persistent string option. |
| [`ConfigSelectionArray`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigSelectionArray.qml) | Multi-choice selector bound to a config option. |
| [`ConfigSelectionShapeArray`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfigSelectionShapeArray.qml) | Grid of shapes bound to a config shape option. |

---

### Category 6: Progress, Gauges & Visualizers

| Component | Summary & Usage |
| :--- | :--- |
| [`StyledProgressBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledProgressBar.qml) | Determinate linear progress bar with rounded ends. |
| [`StyledIndeterminateProgressBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledIndeterminateProgressBar.qml) | Looping indeterminate progress bar for loading states. |
| [`CircularProgress`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/CircularProgress.qml) | Circular radial arc progress meter. |
| [`ClippedProgressBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ClippedProgressBar.qml) | Progress bar with slanted edge styling. |
| [`ClippedFilledCircularProgress`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ClippedFilledCircularProgress.qml) | Radial filled gauge. |
| [`ClippedOutlineCircularProgress`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ClippedOutlineCircularProgress.qml) | Radial outlined gauge. |
| [`MaterialLoadingIndicator`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialLoadingIndicator.qml) | Material 3 spinning circular loader. |
| [`Graph`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Graph.qml) | Canvas-based real-time line/area graph for system metrics. |
| [`WaveVisualizer`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WaveVisualizer.qml) | Animated audio spectrum visualizer bars. |
| [`WavyLine`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WavyLine.qml) | Animated wavy sinusoidal path for playback scrubbing. |

---

### Category 7: Shapes, Cookies & Decorative Styling

| Component | Summary & Usage |
| :--- | :--- |
| [`MaterialShape`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialShape.qml) | Vector engine for 35+ Material shapes (`Flower`, `Sunny`, `Gem`, `Cookie7Sided`, `Bun`, `Boom`, `Heart`, etc.). |
| [`MaterialShapeWrappedMaterialSymbol`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialShapeWrappedMaterialSymbol.qml) | Icon automatically centered inside a decorative `MaterialShape` badge. |
| [`MaterialCookie`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialCookie.qml) / `SineCookie` | Scalloped / fluted cookie border container. |
| [`MaterialPill`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/MaterialPill.qml) / `Pill` | Fully rounded capsule/pill wrapper. |
| [`Circle`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Circle.qml) | Smooth circular canvas item. |
| [`RoundCorner`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/RoundCorner.qml) | Inverted rounded corner mask for seamless bar-to-screen transitions. |
| [`DashedBorder`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DashedBorder.qml) | Dashed stroke border around items. |
| [`StyledRectangle`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledRectangle.qml) | Rounded rectangle with standard theme borders and layers. |
| [`StyledRectangularShadow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledRectangularShadow.qml) | Drop shadow anchored to a target rectangle. |
| [`StyledDropShadow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledDropShadow.qml) | Drop shadow using shader effects for arbitrary shapes. |
| [`Colorizer`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Colorizer.qml) | Applies dynamic tinting and color shift shaders to children. |

---

### Category 8: Dialogs, Popups & Overlays

| Component | Summary & Usage |
| :--- | :--- |
| [`WindowDialog`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialog.qml) | Expanding modal dialog that zooms from its trigger `sourceItem`. Used for sidebar submenus. |
| [`WindowDialogButtonRow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogButtonRow.qml) | Standard action button row at the bottom of a `WindowDialog`. |
| [`WindowDialogSlider`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogSlider.qml) | Labeled slider formatted for dialogs. |
| [`WindowDialogSeparator`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WindowDialogSeparator.qml) | Subtle divider line inside dialogs. |
| [`ConfirmationDialog`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ConfirmationDialog.qml) | Standard Confirm/Cancel prompt modal. |
| [`SelectionDialog`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/SelectionDialog.qml) | Modal dialog for picking from a list of options. |
| [`StyledPopup`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledPopup.qml) / `StyledPopupMenu` | Floating popup menu with anchor support. |
| [`StyledToolTip`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledToolTip.qml) / `PopupToolTip` | Hover tooltip with auto-delay and smooth animation. |
| [`StyledToolTipContent`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledToolTipContent.qml) | Visual tooltip card container. |
| [`FullscreenPolkitWindow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FullscreenPolkitWindow.qml) | Fullscreen overlay window for Polkit elevation. |
| [`LayerManagedPanelWindow`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/LayerManagedPanelWindow.qml) | Wayland panel window with layer-shell z-order control. |

---

### Category 9: Lists, Scrolling & Reordering

| Component | Summary & Usage |
| :--- | :--- |
| [`StyledListView`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledListView.qml) | Virtualized list view with smooth deceleration and scrollbar. |
| [`StyledFlickable`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledFlickable.qml) | Smooth flickable scroll container. |
| [`StyledScrollBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/StyledScrollBar.qml) | Slim, themed scrollbar indicator. |
| [`ScrollEdgeFade`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ScrollEdgeFade.qml) | Alpha fade gradient masks at top/bottom of scroll areas. |
| [`FocusedScrollMouseArea`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FocusedScrollMouseArea.qml) | Intercepts wheel events and routes them to the active scrollable child. |
| [`ReorderableColumn`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ReorderableColumn.qml) | Drag-and-drop reorderable column container. |
| [`GroupedList`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/GroupedList.qml) | Grouped list with collapsible section headers. |
| [`DialogListItem`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DialogListItem.qml) | Clickable row inside a dialog list. |

---

### Category 10: Notifications

| Component | Summary & Usage |
| :--- | :--- |
| [`NotificationListView`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationListView.qml) | Virtualized list of active notifications. |
| [`NotificationItem`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationItem.qml) | Notification toast card with swipe-to-dismiss and action buttons. |
| [`NotificationGroup`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationGroup.qml) | Collapsible stack of notifications from the same application. |
| [`NotificationActionButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationActionButton.qml) | Button to trigger a notification action. |
| [`NotificationGroupExpandButton`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NotificationGroupExpandButton.qml) | Expand/collapse chevron for notification stacks. |

---

### Category 11: Cards, Layouts & Containers

| Component | Summary & Usage |
| :--- | :--- |
| [`Box`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Box.qml) | Standard rounded container box. |
| [`BoxLayout`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/BoxLayout.qml) | Flexbox-style responsive layout. |
| [`ContentPage`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ContentPage.qml) | Full settings page container with title and back button. |
| [`ContentSection`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ContentSection.qml) / `ContentSubsection` | Structured grouping section with headers. |
| [`LayoutSection`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/LayoutSection.qml) | Layout section wrapper. |
| [`BarIsland`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/BarIsland.qml) | Capsule pill for status bar modules. |
| [`BarWidgetSwitcher`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/BarWidgetSwitcher.qml) & `BarWidgetSwitcherArea` | Sliding module container for status bar widgets. |
| [`AddressBar`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AddressBar.qml) & `AddressBreadcrumb` | Path navigation bar with breadcrumb crumbs. |
| [`PagePlaceholder`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/PagePlaceholder.qml) | Empty state view with icon, title, and descriptive message. |
| [`NoticeBox`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/NoticeBox.qml) | Information/Alert callout box. |
| [`ResourceCard`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ResourceCard.qml) | Metric card with progress meter and icon. |
| [`PresetsCard`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/PresetsCard.qml) | Preset selection card. |
| [`AboutCard`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AboutCard.qml) | Card displaying system info and version metadata. |
| [`Carousel`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Carousel.qml) / `ThemeCarousel` | Horizontal swiping card carousel. |
| [`Revealer`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Revealer.qml) | Smooth slide-and-fade visibility animator. |
| [`FadeLoader`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/FadeLoader.qml) | Component loader with smooth cross-fade transitions. |
| [`ResizeHandler`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ResizeHandler.qml) | Grip handle for resizing panels/windows. |
| [`DragApps`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/DragApps.qml), `DragManager`, `DropShelf` | Drag-and-drop workspace window management widgets. |

---

### Category 12: Media, Clock & Specialized System Views

| Component | Summary & Usage |
| :--- | :--- |
| [`AndroidClock`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AndroidClock.qml) | Clock styled after Android lockscreen big clocks. |
| [`CalendarView`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/CalendarView.qml) & `WeekRow` | Interactive calendar grid and week days header. |
| [`WorldMap`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WorldMap.qml) | Interactive vector world map for timezones. |
| [`Player`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Player.qml), `PlayerControls`, `PlayerControlsLyrics` | Full media player widgets with playback controls and lyrics sync. |
| [`Lyrics`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/Lyrics.qml) | Auto-scrolling synchronized karaoke lyrics view. |
| [`AutostartApps`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/AutostartApps.qml) | Manager list for autostart desktop entries. |
| [`KeyboardKey`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/KeyboardKey.qml) | Realistic 3D keycap widget for hotkey shortcut displays. |
| [`WallpaperSubmenu`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WallpaperSubmenu.qml) | Wallpaper picker grid. |
| [`WidgetsSubmenu`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WidgetsSubmenu.qml) | Background widget picker. |
| [`WidgetsMonitorSelector`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/WidgetsMonitorSelector.qml), `MonitorCanvas`, `MonitorRect` | Monitor layout canvas for multi-monitor setups. |
| [`ErrorShakeAnimation`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/widgets/ErrorShakeAnimation.qml) | Reusable shake animation for invalid inputs / passwords. |
