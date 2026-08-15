local Config = require(script.Parent.Config)
local Version = require(script.Parent.Version)

local Branding = {}

Branding.displayName = string.format("Rojo %s — Blokblok Auto-Reconnect", Version.display(Config.version))

return Branding
