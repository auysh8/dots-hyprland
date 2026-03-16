# Color Rules For Cross-Layer Consistency

This document defines how colors must be used in QML so UI stays consistent across all layers (`common`, `ii`, `waffle`, `lyrics`, `music`, `notes`, overlays, popups).

## 1) Single Source Of Truth

- Use `Appearance` tokens for shell-wide UI colors.
- Use `Looks` tokens only inside Waffle look components, or when building Waffle-only UI.
- Do not define new palette systems per module.
- Do not hardcode hex colors in feature components unless it is a deliberate, documented exception.

Primary definitions:
- `ii/modules/common/Appearance.qml`
- `ii/modules/waffle/looks/Looks.qml`
- `ii/services/MaterialThemeLoader.qml`

## 2) Token Hierarchy (Always Follow)

1. Semantic tokens (`Appearance.colors.*`, `Looks.colors.*`)  
2. Material tokens (`Appearance.m3colors.*`)  
3. Hardcoded literals (`"#RRGGBB"`, `Qt.rgba(...)`) only for special effects/fallbacks

If a semantic token exists, use it instead of `m3colors`.

## 3) Layer Surface Mapping (Common/II)

Use these consistently:
- Base panel/sidebar surfaces: `Appearance.colors.colLayer0`
- Cards/groups inside panel: `Appearance.colors.colLayer1`
- Elevated controls: `Appearance.colors.colLayer2`
- Dialogs/floaters: `Appearance.colors.colLayer3`
- Modals/highest overlays: `Appearance.colors.colLayer4`

Interactive states:
- Hover: `*Hover`
- Pressed/active: `*Active`
- Disabled text/icon: `colOnLayer2Disabled` (or relevant semantic disabled token)

## 4) Foreground/Text Rules

- Primary text on surfaces: `Appearance.colors.colOnSurface` or `colOnLayer*` pair.
- Secondary text/meta: `Appearance.colors.colSubtext` or `colOnSurfaceVariant`.
- Never place `colOnPrimary` text on non-primary backgrounds.
- Always pair background + foreground from same semantic family:
  - `colPrimary` + `colOnPrimary`
  - `colPrimaryContainer` + `colOnPrimaryContainer`
  - `colSecondaryContainer` + `colOnSecondaryContainer`

## 5) Accent/Status Rules

- Brand/accent actions: `colPrimary` (+ hover/active variants).
- Selection/focus containers: `colSecondaryContainer` (or `Looks.colors.selection` in Waffle).
- Error/critical only: `colError`, `colErrorContainer`, matching `colOnError*`.
- Do not reuse error colors for warnings/info.

## 6) Waffle-Specific Rules

- In Waffle look components, use `Looks.colors.*` first.
- `Looks.colors.accent*` already maps to `Appearance.colors.colPrimary*`; prefer it for Waffle controls.
- Keep Waffle background layering via `Looks.colors.bg0/bg1/bg2` and corresponding border tokens.
- Do not mix `Appearance.colors.colLayer*` with `Looks.colors.bg*` in one component unless needed for interoperability.

## 7) Transparency/Effects

- Use `ColorUtils.transparentize`, `ColorUtils.mix`, `ColorUtils.applyAlpha`, `ColorUtils.solveOverlayColor`.
- Prefer transparency derived from token colors, not raw black/white overlays.
- Scrim/shadow must use:
  - `Appearance.colors.colScrim`
  - `Appearance.colors.colShadow`

## 8) Dynamic Theme Compatibility

- Assume runtime theme can change (wallpaper theming / palette type).
- Do not cache static color literals derived from old theme values.
- Bind color properties to tokens directly so updates propagate automatically.

Theme flow:
- Generated palette file: `~/.local/state/quickshell/user/generated/colors.json`
- Loaded by `MaterialThemeLoader` into `Appearance.m3colors`.

## 9) Hardcoded Color Exception Policy

Hardcoded colors are allowed only for:
- Debug/demo/example files
- Visualizers/canvas effects
- Brand-locked logos/assets
- Temporary fallback when token is unavailable

When used:
- Add a short comment explaining why token-based color was not possible.
- Prefer a named local property (e.g. `readonly property color fallbackWarning`) over inline literals.

## 10) Component Authoring Checklist

Before merging any UI component:
- Background uses layer token (`colLayer*` or `Looks bg*`).
- Text/icon uses matching foreground token.
- Hover/active/disabled states are tokenized.
- No unexplained hardcoded hex color.
- Error/warning styles use semantic status tokens.
- Works in both dark and light mode without manual branching where tokens already handle it.

## 11) Standalone Apps (App Mode)

When building standalone windows or apps (like `music.qml` or `settings.qml`) that should NOT have transparency:
- Do NOT use standard layer tokens (`colLayer0`, `colLayer1`) as they contain alpha transparency and will show the desktop underneath.
- Do NOT fall back to `m3colors` directly.
- Instead, use the **Base** tokens (`colLayer0Base`, `colLayer1Base`, `colLayer2Base`). These map to the same semantic surfaces but are fully opaque.

## 12) Quick Reference

Use most often:
- `Appearance.colors.colLayer0..4`
- `Appearance.colors.colOnLayer0..4`
- `Appearance.colors.colPrimary`, `colPrimaryHover`, `colPrimaryActive`
- `Appearance.colors.colSecondaryContainer`, `colOnSecondaryContainer`
- `Appearance.colors.colSubtext`, `colOutline`, `colOutlineVariant`
- `Appearance.colors.colError`, `colErrorContainer`, `colOnErrorContainer`
- `Appearance.colors.colScrim`, `colShadow`
- `Looks.colors.bg0/bg1/bg2`, `fg/subfg`, `accent*`, `control*`

