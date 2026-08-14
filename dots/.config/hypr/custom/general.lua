hl.config({
    decoration = {
        blur = {
            enabled = true,
            xray = false,
            special = false,
            new_optimizations = true,
            size = 2,
            passes = 2,
            popups = true,
            popups_ignorealpha = 0.5,
            input_methods = true,
            input_methods_ignorealpha = 0.5,
            brightness = 1,
            noise = 0.03,
            contrast = 1,
            vibrancy = 0.5,
            vibrancy_darkness = 0.1
        }
    },
    misc = {
        vrr = 1
    }
})

if hl.plugin and hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    local colors = colors or { bg0 = 0x121318FF }
    local tint = tint or function(color, alpha)
        return color
    end

    hg.config({
        default_theme = "light",
        default_preset = "glass",
        tint_color = 0x8899aa22,

        brightness = 0.5,
        dark = { brightness = 0.82 },
        light = { adaptive_boost = 0.5 },

        layers = { enabled = 1 },
    })

    -- ── Layer surfaces ────────────────────────────────────────────────
    -- Each hg.layer() call whitelists that namespace.
    -- Comment out a line to remove glass from that layer.
    --preset = "glass", mask_threshold (0.0–1.0): higher = glass only on more opaque pixels.

    -- ── Core UI ───────────────────────────────────────────────────────
    -- hg.layer("quickshell",               {preset = "glass", mask_threshold = 0.3 })  -- root surface
    hg.layer("quickshell:bar",           {preset = "glass", mask_threshold = 0.3 })  -- top bar
    hg.layer("quickshell:dynamicIsland", {preset = "glass", mask_threshold = 0.3 })  -- dynamic island
    hg.layer("quickshell:verticalBar",   {preset = "glass", mask_threshold = 0.3 })  -- left icon bar
    -- hg.layer("quickshell:dock",          {preset = "glass", mask_threshold = 0.3 })  -- bottom dock
        -- hg.layer("quickshell:screenCorners", {preset = "glass", mask_threshold = 0.5 })  -- corner overlays

    -- ── Sidebars ──────────────────────────────────────────────────────
    hg.layer("quickshell:sidebarRight",  { preset = "glass", mask_threshold = 0.3 })  -- right sidebar
    hg.layer("quickshell:sidebarLeft",   {preset = "glass", mask_threshold = 0.3 })  -- left sidebar

    -- ── Popups & Overlays ─────────────────────────────────────────────
    -- hg.layer("quickshell:popup",              { preset = "glass", mask_threshold = 0.3 })  -- styled popups
    hg.layer("quickshell:notificationPopup",  {preset = "glass", mask_threshold = 0.3 })  -- notifications
    hg.layer("quickshell:onScreenDisplay",    {preset = "glass", mask_threshold = 0.3 })  -- OSD (vol/bright)
    hg.layer("quickshell:mediaControls",      {preset = "glass", mask_threshold = 0.3 })  -- media controls
    hg.layer("quickshell:overlay",            {preset = "glass", mask_threshold = 0.3 })  -- general overlay
    -- hg.layer("quickshell:reloadPopup",        {preset = "glass", mask_threshold = 0.3 })  -- reload popup
    hg.layer("quickshell:cheatsheet",         {preset = "glass", mask_threshold = 0.3 })  -- keybind sheet

    -- ── Fullscreen / Special ──────────────────────────────────────────
    hg.layer("quickshell:overview",           {preset = "glass", mask_threshold = 0.3 })  -- window overview
    -- hg.layer("quickshell:session",            {preset = "glass", mask_threshold = 0.3 })  -- session/logout
    hg.layer("quickshell:polkit",             {preset = "glass", mask_threshold = 0.3 })  -- auth dialog
    hg.layer("quickshell:wallpaperSelector",  {preset = "glass", mask_threshold = 0.3 })  -- wallpaper picker
    -- hg.layer("quickshell:regionSelector",     {preset = "glass", mask_threshold = 0.5 })  -- screen snip
    hg.layer("quickshell:osk",               {preset = "glass", mask_threshold = 0.3 })  -- on-screen keyboard

    -- ── Non-quickshell layers ─────────────────────────────────────────
    -- hg.layer("system-monitor",                     {preset = "glass", mask_threshold = 0.3 })  -- sys monitor
    hg.layer("app-drawer",                         {preset = "glass", mask_threshold = 0.3 })  -- app drawer
    hg.layer("kde-connect-drawer",                 {preset = "glass", mask_threshold = 0.3 })  -- KDE Connect
    -- hg.layer("kde-connect-drawer-drag-trigger",    {preset = "glass", mask_threshold = 0.5 })  -- KDE drag zone

    -- ── Always skip ───────────────────────────────────────────────────
    hg.layer("quickshell:background", { exclude = true })  -- wallpaper, never glass


    -- Presets
    hg.preset("clear", {
        glass_opacity = 0.8,
        blur_strength = 1.5,
        dark = { brightness = 0.7 },
        light = { brightness = 1.2 },
    })

    hg.preset("contrasted", {
        inherits = "high_contrast",
        contrast = 1.2,
        adaptive_dim = 1.5,
        dark = { tint_color = 0x02142aa9 },
    })

    hg.preset("glass", {
        blur_strength = 1,
        blur_iterations = 1,
        chromatic_aberration = 0,
        fresnel_strength = 1,
        edge_thickness = 0.03,
        lens_distortion = 1,
        brightness = 1,
        contrast = 1.8,
        saturation = 1,
        vibrancy = 1,
        vibrancy_darkness = 1,
        adaptive_boost = 0.5,
    })
end
