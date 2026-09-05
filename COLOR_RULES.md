# Quickshell Color Rules & Usage Guide

This document defines the color architecture, tokens, and rules for UI components in **dots-hyprland** based on [`Appearance.qml`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/Appearance.qml).

The color system is built on **Material Design 3 (Material You)**, dynamically generated from the current wallpaper using `matugen` or `generate_colors_material.py`.

---

## 1. How to Import and Access Colors

### Imports
Add these imports at the top of your QML file:

```qml
import qs.modules.common
import qs.modules.common.functions
import QtQuick
```

* **`qs.modules.common`**: Exposes the `Appearance` singleton.
* **`qs.modules.common.functions`**: Exposes helper singletons like `ColorUtils`.

### Accessing Colors
Always use `Appearance.colors.<token>` for UI elements:

```qml
Rectangle {
    color: Appearance.colors.colPrimaryContainer
    border.color: Appearance.colors.colOutlineVariant

    StyledText {
        text: "Active Status"
        color: Appearance.colors.colOnPrimaryContainer
    }
}
```

> [!NOTE]
> `Appearance.colors` contains pre-calculated opacity, transparency, and interaction states (hover/active). Use `Appearance.m3colors.<token>` only if you need raw, unblended hex values from the base Material 3 specification.

---

## 2. Color Categories & Where to Use Them

### A. Surface Elevation Layers (`colLayer0` – `colLayer4`)
Use these neutral surface colors to create structural depth. They adapt dynamically to wallpaper vibrancy and transparency settings.

| Token | Surface Role | Ideal Placement |
| :--- | :--- | :--- |
| **`colLayer0`** | Base Surface / Panel | Outer window canvas, sidebar backgrounds, status bar background. |
| **`colLayer1`** | Content Card / Group | Section containers, card wrappers sitting on top of `colLayer0`. |
| **`colLayer2`** | Elevated Component | Buttons, input boxes, sliders, or controls sitting on `colLayer1`. |
| **`colLayer3`** | Popups & Dropdowns | Context menus, hover tooltips, floating popouts, notification toasts. |
| **`colLayer4`** | Modals & Dialogs | High-elevation overlays, lock screen prompts, kill dialogs. |

**Companion Text & States**:
* Text on layers: `Appearance.colors.colOnLayer0`, `colOnLayer1`, `colOnLayer2`, etc.
* Secondary/Muted text: `Appearance.colors.colSubtext` or `colOnLayer1Inactive`.
* Hover/Active states: `colLayer0Hover`, `colLayer0Active`, `colLayer1Hover`, `colLayer1Active`, etc.

---

### B. Primary Accent (`colPrimary`)
The dominant accent tone directly derived from the wallpaper's primary hue.

| Token | Type | Ideal Placement |
| :--- | :--- | :--- |
| **`colPrimary`** | Main Hero Accent | Active switches/toggles, active workspace indicator, primary action FABs, filled slider bars, clock hour hand. |
| **`colOnPrimary`** | High-Contrast Foreground | Text or icon displayed directly on top of `colPrimary`. |
| **`colPrimaryContainer`** | Tonal Accent Surface | Large surfaces tinted by wallpaper (e.g. Weather card, Clock dial face, CPU stat card, selected menu items). |
| **`colOnPrimaryContainer`** | Container Foreground | Text or icons displayed inside a `colPrimaryContainer`. |

**States**:
* `colPrimaryHover`, `colPrimaryActive`
* `colPrimaryContainerHover`, `colPrimaryContainerActive`

---

### C. Secondary Accent (`colSecondary`)
A less saturated, harmonized tone sharing hue characteristics with Primary.

| Token | Type | Ideal Placement |
| :--- | :--- | :--- |
| **`colSecondary`** | Secondary Accent | Secondary controls, inactive-yet-highlighted indicators, RAM usage stats, stopwatch running indicators. |
| **`colOnSecondary`** | Foreground | Text or icons on top of `colSecondary`. |
| **`colSecondaryContainer`** | Tonal Surface | Secondary widget cards (e.g., RAM card, month indicators, secondary action buttons). |
| **`colOnSecondaryContainer`** | Container Foreground | Text or icons inside `colSecondaryContainer`. |

**States**:
* `colSecondaryHover`, `colSecondaryActive`
* `colSecondaryContainerHover`, `colSecondaryContainerActive`

---

### D. Tertiary Accent (`colTertiary`)
A complementary/contrasting accent (often warmer or cooler) providing visual variety.

| Token | Type | Ideal Placement |
| :--- | :--- | :--- |
| **`colTertiary`** | Contrasting Accent | Minute hands on clocks, warning/warm actions, task cycle indicators, network/battery meters. |
| **`colOnTertiary`** | Foreground | Text or icons on top of `colTertiary`. |
| **`colTertiaryContainer`** | Tonal Surface | Tertiary widget cards (e.g. Battery/Disk card, Pomodoro focus card, date bubbles). |
| **`colOnTertiaryContainer`** | Container Foreground | Text or icons inside `colTertiaryContainer`. |

**States**:
* `colTertiaryHover`, `colTertiaryActive`
* `colTertiaryContainerHover`, `colTertiaryContainerActive`

---

### E. Semantic & Feedback Colors

| Token | Purpose | Example |
| :--- | :--- | :--- |
| **`colError`** / **`colOnError`** | Destructive / Fatal states | Delete buttons, error badges, critical battery warnings. |
| **`colErrorContainer`** / **`colOnErrorContainer`** | Error banners or cards | Error notifications, alert containers. |
| **`m3success`** / **`m3onSuccess`** | Positive / Successful states | Completed downloads, success banners, connected status. |
| **`m3successContainer`** / **`m3onSuccessContainer`** | Success background containers | Finished task cards, active power saver banner. |

---

### F. Utility & Outline Colors

| Token | Purpose |
| :--- | :--- |
| **`colOutline`** | Prominent borders, active divider lines, focused outlines. |
| **`colOutlineVariant`** | Subtle dividers, inactive card borders (`colLayer0Border`). |
| **`colSubtext`** | Secondary labels, timestamps, metadata, captions. |
| **`colShadow`** | Drop shadow color (pre-transparentized). |
| **`colScrim`** | Screen backdrop dimmer when modals open. |

---

## 3. The Golden "On-" Pairing Rule

> [!IMPORTANT]
> **Never mix and match mismatched foregrounds and backgrounds.**
> Material Design pairs each surface with an exact high-contrast foreground counterpart to preserve WCAG accessibility:

* ✅ **`colPrimary`** ➔ text/icon must be **`colOnPrimary`**
* ✅ **`colPrimaryContainer`** ➔ text/icon must be **`colOnPrimaryContainer`**
* ✅ **`colSecondary`** ➔ text/icon must be **`colOnSecondary`**
* ✅ **`colSecondaryContainer`** ➔ text/icon must be **`colOnSecondaryContainer`**
* ✅ **`colTertiary`** ➔ text/icon must be **`colOnTertiary`**
* ✅ **`colTertiaryContainer`** ➔ text/icon must be **`colOnTertiaryContainer`**
* ✅ **`colLayer0`** / **`colLayer1`** ➔ text/icon must be **`colOnLayer0`** / **`colOnLayer1`**
* ❌ *Never put `colOnPrimary` directly on `colLayer0` or `colPrimaryContainer`.*

---

## 4. Helper Functions (`ColorUtils`)

Use [`ColorUtils.qml`](file:///home/auysh/dots-hyprland/dots/.config/quickshell/ii/modules/common/functions/ColorUtils.qml) for fine-grained tinting and transitions:

```qml
// 1. Transparentize a color (0.0 = fully opaque, 1.0 = fully clear)
color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)

// 2. Blend two colors together by weight (0.0 to 1.0)
color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colLayer1, 0.85)

// 3. Force specific HSL lightness (e.g. 0.85 for dark mode readability, 0.15 for light mode)
color: ColorUtils.colorWithLightness(Appearance.colors.colPrimary, 0.85)

// 4. Apply absolute alpha (0.0 to 1.0)
color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)
```

---

## 5. Idiomatic Component Examples

### Example 1: Action Button (Primary Accent)
```qml
Rectangle {
    id: btn
    width: 120
    height: 40
    radius: Appearance.rounding.small
    color: mouseArea.containsPress 
        ? Appearance.colors.colPrimaryActive 
        : (mouseArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)

    MaterialSymbol {
        anchors.centerIn: parent
        text: "check"
        color: Appearance.colors.colOnPrimary
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
    }
}
```

### Example 2: Widget Stat Card (Tonal Container)
```qml
Rectangle {
    width: 140
    height: 90
    radius: Appearance.rounding.normal
    color: Appearance.colors.colPrimaryContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12

        StyledText {
            text: "CPU LOAD"
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        StyledText {
            text: "34%"
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: Font.Bold
            color: Appearance.colors.colOnPrimaryContainer
        }
    }
}
```

### Example 3: Multi-Category Triad (Primary / Secondary / Tertiary)
```qml
// As seen in ResourcesWidget or TodoWidget:
property color itemBg: {
    if (index % 3 === 0) return Appearance.colors.colTertiaryContainer
    if (index % 3 === 1) return Appearance.colors.colSecondaryContainer
    return Appearance.colors.colPrimaryContainer
}

property color itemFg: {
    if (index % 3 === 0) return Appearance.colors.colOnTertiaryContainer
    if (index % 3 === 1) return Appearance.colors.colOnSecondaryContainer
    return Appearance.colors.colOnPrimaryContainer
}
```

---

## 6. Summary Checklist & Anti-Patterns

- [ ] **No Hardcoded Hex Colors**: Never use `#FFFFFF`, `#1E1E1E`, or `#333333` in UI widgets; always use `Appearance.colors` so light/dark mode and wallpaper switches work instantly.
- [ ] **Elevation Flow**: Build panels starting at `colLayer0`, cards at `colLayer1`, interactive controls at `colLayer2`, and floating elements at `colLayer3`.
- [ ] **Accent Restraint**: Use `colPrimary` sparingly for critical visual cues (toggles, active workspaces, confirm buttons). Use `colPrimaryContainer` for broad areas.
- [ ] **Pair Correctly**: Always match backgrounds with their specific `colOn...` tokens.
