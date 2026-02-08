local I = require('openmw.interfaces')

local input = require('openmw.input')

input.registerAction {
    key = 'GrabPhysicsObject',
    type = input.ACTION_TYPE.Boolean,
    l10n = 'LuaPhysics',
    defaultValue = false,
}

I.Settings.registerPage {
    key = 'LuaPhysicsPage',
    l10n = 'LuaPhysics',
    name = 'Lua Physics Engine',
    description = '<< A Funky Lua Physics Engine by Max Yari >> Some settings here are not applied in realtime. Execute a "reloadlua" command in ~ tilda console or restart the game to apply the settings.',
}

I.Settings.registerGroup {
    key = 'SettingsLuaPhysicsControls',
    page = 'LuaPhysicsPage',
    l10n = 'LuaPhysics',
    name = 'Controls',
    permanentStorage = true,   
    order = 1,
    settings = {
        {
            key = "GrabPhysicsObjectButton",
            renderer = "inputBinding",            
            default = "Grab_physics_object_button",
            name = "Drag Object",
            description = 'Hold to drag an object around, release to drop.',
            argument = {
                type = "action",
                key = "GrabPhysicsObject"
            },
        }
    }
}

return {
    
}
