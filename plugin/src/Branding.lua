local Config = require(script.Parent.Config)
local Version = require(script.Parent.Version)

local Branding = {}

Branding.displayName = string.format("Rojo %s - BlokBlok Fork", Version.display(Config.version))

return Branding
