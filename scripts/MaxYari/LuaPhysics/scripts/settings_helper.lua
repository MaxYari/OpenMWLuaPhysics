local async = require("openmw.async")

--- A little helper for live settings updates without constantly hitting the storage (from Sneak Is Good Now).
--- Read settings as fields: settings.SomeKey. Values are cached and refreshed when the section changes.
--- 'store' is the storage section, e.g. storage.globalSection("SettingsLuaPhysicsAux").
local SettingsHelper = {}
SettingsHelper.__index = SettingsHelper
function SettingsHelper:new(store)
    local inst = {
        store = store,
        settings = {},
        trackedSettings = {}
    }

    inst.store:subscribe(async:callback(function()
        for key, _ in pairs(inst.trackedSettings) do
            inst.settings[key] = inst.store:get(key)
        end
    end))

    setmetatable(inst, self)

    return inst
end

function SettingsHelper:__index(key)
    if rawget(self, key) then return rawget(self, key) end
    if not self.trackedSettings[key] then
        self.trackedSettings[key] = true
        self.settings[key] = self.store:get(key)
    end
    return self.settings[key]
end

return SettingsHelper
