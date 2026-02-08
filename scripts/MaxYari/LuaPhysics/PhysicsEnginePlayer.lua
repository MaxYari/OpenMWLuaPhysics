local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')
local types = require('openmw.types')
local nearby = require('openmw.nearby')
local ui = require('openmw.ui')
local camera = require('openmw.camera')
local omwself = require('openmw.self')
local input = require('openmw.input')
local I = require('openmw.interfaces')
local async = require("openmw.async")
local storage = require("openmw.storage")

local gutils = require(mp..'scripts/gutils')
local PhysicsUtils = require(mp..'scripts/physics_utils')
local animManager = require(mp..'scripts/anim_manager')
local D = require(mp..'scripts/physics_defs')

local selfActor = gutils.Actor:new(omwself)

local settings = storage.globalSection('SettingsLuaPhysicsAux')
local interface = {
    version = 1.0,
    defaultThrowEnabled = true
}


local frame = 0


local function onUpdate(dt)
    frame = frame + 1
    local noColOnShift = settings:get("NoCollisionOnShift")
    -- Utilities update loop
    PhysicsUtils.HoldGrabbedObject(dt, noColOnShift and input.isShiftPressed())

    if PhysicsUtils.activeObject and input.getBooleanActionValue("Use") and interface.defaultThrowEnabled then        
        local throwImpulse = 500
        local direction = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()

        -- Launching!
        PhysicsUtils.activeObject:sendEvent(D.e.ApplyImpulse, {impulse=direction*throwImpulse, culprit = omwself.object })
        PhysicsUtils.DropObject()
    end

    if I.impactEffects and I.impactEffects.version < 107 then
        return ui.showMessage("LuaPhysics: OpenMW Impact Effects mod detected, but it's an old version. Please update OpenMW Impact Effects.")
    end

    
end

input.registerActionHandler('GrabPhysicsObject', async:callback(function(val)    
    if val then
        PhysicsUtils.GrabObject()
        types.Actor.setStance(omwself, types.Actor.STANCE.Nothing)
    else 
        PhysicsUtils.DropObject()
    end
end))

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
    interfaceName = "LuaPhysics",
    interface = interface
}
