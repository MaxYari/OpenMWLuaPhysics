local storage = require('openmw.storage')
local I = require('openmw.interfaces')


I.Settings.registerGroup {
    key = 'SettingsLuaPhysics',
    page = 'LuaPhysicsPage',
    l10n = 'LuaPhysics',
    name = 'General Settings',
    order = 2,
    permanentStorage = true,    
    settings = {
        {
            key = 'SelfCollisions',
            renderer = 'checkbox',
            default = true,
            name = 'Self-collisions',
            description = "Do physics objects collide with each other? Keeping disabled may improve performance."
        },
        {
            key="DebrisPerExteriorCell",
            renderer = "number",
            default = 30,
            argument = {
                min = 1,
                max = 10000
            },
            name = "Max. Debris in Exterior Cell",
            description = "Amount of debris (spawned from destroyed objects) allowed to exist in an exterior cell"
        },
        {
            key="DebrisPerInteriorCell",
            renderer = "number",
            default = 40,
            argument = {
                min = 1,
                max = 10000
            },
            name = "Max. Debris in Interior Cell",
            description = "Amount of debris (spawned from destroyed objects) allowed to exist in an interior cell"
        },
        {
            key="CrimeSystemActive",
            renderer = 'checkbox',
            default = true,
            name = "Crime System Active",
            description = "Messing around too much with owned items, destroying them, or destroying too many non-owned items under a vigilant watch of a guard - will be treated as a crime."
        },
        {
            key="SFXVolume",
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 10
            },
            name = "Sound Effects Volume"            
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsLuaPhysicsAux',
    page = 'LuaPhysicsPage',
    l10n = 'LuaPhysics',
    name = 'Auxiliary',
    permanentStorage = true,    
    order = 3,
    settings = {
        {
            key = 'NoCollisionOnShift',
            renderer = 'checkbox',
            default = false,
            name = 'Hold shift to ignore collisions',
            description = "While dragging an item around - holding shift will make item phase through things. Not entirely fair, but useful for getting items unstuck."
        }
    },
}



return {
    
}
