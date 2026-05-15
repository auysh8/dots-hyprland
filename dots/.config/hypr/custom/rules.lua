hl.layer_rule({ match = { namespace = ".*" }, xray = false })

hl.window_rule({match = {class = ".*"}, no_blur = false})
hl.window_rule({match = {class = "^()$", title = "^()$"}, no_blur = false})

hl.layer_rule({match = {namespace = "lyrics-layer"}, blur = true})
hl.layer_rule({match = {namespace = "lyrics-layer"}, ignore_alpha = 0.5})

hl.layer_rule({match = {namespace = "quickshell:notes"}, blur = true})
hl.layer_rule({match = {namespace = "quickshell:notes"}, ignore_alpha = 0.5})

hl.layer_rule({match = {namespace = "kde-connect-drawer"}, blur = true})
hl.layer_rule({match = {namespace = "kde-connect-drawer"}, ignore_alpha = 0.5})

hl.window_rule({match = {title = "PhoneMirror"}, float = true})
hl.window_rule({match = {title = "PhoneMirror"}, size = {354, 790}})
hl.window_rule({match = {title = "PhoneMirror"}, move = {"100%-420", "100%-820"}})

hl.layer_rule({match = {namespace = "quickshell:popup"}, blur = true})
hl.layer_rule({match = {namespace = "quickshell:popup"}, ignore_alpha = 0.5})

hl.layer_rule({match = {namespace = "app-drawer"}, blur = true})
hl.layer_rule({match = {namespace = "app-drawer"}, ignore_alpha = 0.5})

hl.layer_rule({match = {namespace = "music-layer"}, blur = true})
hl.layer_rule({match = {namespace = "music-layer"}, ignore_alpha = 0.5})
