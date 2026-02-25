
local opts = require 'mp.options'
local o = { title = "", artist = "", arturl = "" }
opts.read_options(o, "mdata")

function update_metadata()
    if o.title ~= "" then 
        mp.set_property("metadata/by-key/Title", o.title) 
        mp.set_property("force-media-title", o.title)
    end
    if o.artist ~= "" then 
        mp.set_property("metadata/by-key/Artist", o.artist) 
    end
    if o.arturl ~= "" then 
        -- Set both standard and mpris specific keys for best compatibility
        mp.set_property("metadata/by-key/mpris:artUrl", o.arturl)
        mp.set_property("metadata/by-key/icy-name", o.title) -- some clients use this
    end
end
mp.register_event("file-loaded", update_metadata)
