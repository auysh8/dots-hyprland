-- Curves
hl.curve("expressiveFastSpatial", {
    type = "bezier",
    points = { { 0.42, 1.67 }, { 0.21, 0.90 } }
})
hl.curve("expressiveSlowSpatial", {
    type = "bezier",
    points = { { 0.39, 1.29 }, { 0.35, 0.98 } }
})
hl.curve("expressiveDefaultSpatial", {
    type = "bezier",
    points = { { 0.38, 1.21 }, { 0.22, 1.00 } }
})
hl.curve("emphasizedDecel", {
    type = "bezier",
    points = { { 0.05, 0.7 }, { 0.1, 1 } }
})
hl.curve("emphasizedAccel", {
    type = "bezier",
    points = { { 0.3, 0 }, { 0.8, 0.15 } }
})
hl.curve("standardDecel", {
    type = "bezier",
    points = { { 0, 0 }, { 0, 1 } }
})
hl.curve("menu_decel", {
    type = "bezier",
    points = { { 0.1, 1 }, { 0, 1 } }
})
hl.curve("menu_accel", {
    type = "bezier",
    points = { { 0.52, 0.03 }, { 0.72, 0.08 } }
})
hl.curve("stall", {
    type = "bezier",
    points = { { 1, -0.1 }, { 0.7, 0.85 } }
})
hl.curve("overshot", {
    type = "bezier",
    points = { { 0.05, 0.9 }, { 0.1, 1.1 } }
})
hl.curve("smoothOut", {
    type = "bezier",
    points = { { 0.25, 1 }, { 0.5, 1 } }
})
hl.curve("decel", {
    type = "bezier",
    points = { { 0.05, 0.7 }, { 0.1, 1 } }
})

-- Configs
-- windows
hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 4,
    bezier = "overshot",
    style = "popin 60%"
})
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 5,
    bezier = "overshot",
    style = "popin 60%"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 1,
    bezier = "decel",
    style = "popin 60%"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "emphasizedDecel"
})

-- layers
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 2,
    bezier = "overshot",
    style = "slide"
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    bezier = "emphasizedDecel",
    style = "popin 93%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    bezier = "menu_accel",
    style = "popin 94%"
})

-- fade
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 3,
    bezier = "overshot"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "menu_decel"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})

-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "overshot",
    style = "slidefade 35%"
})

-- specialWorkspace
hl.animation({
    leaf = "specialWorkspace",
    enabled = true,
    speed = 3,
    bezier = "overshot",
    style = "slide"
})
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.8,
    bezier = "emphasizedDecel",
    style = "slide"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "emphasizedAccel",
    style = "slide"
})

-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 6,
    bezier = "smoothOut"
})

