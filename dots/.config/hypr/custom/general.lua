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

        brightness = 1,
        dark = { brightness = 0.82 },
        light = { adaptive_boost = 0.5 },

        layers = { enabled = 0 },
    })

    -- Layer surfaces: each call whitelists the namespace and configures it
    -- hg.layer("waybar", { preset = "subtle", mask_threshold = 0.05 })
    -- hg.layer("swaync")
    -- hg.layer("quickshell:bezel", { preset = "ui", mask_threshold = 0.3 })
    -- hg.layer("debug-panel", { exclude = true })

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
