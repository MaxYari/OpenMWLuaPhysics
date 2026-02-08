local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require('openmw.core')
local util = require('openmw.util')
local nearby = require('openmw.nearby')
local omwself = require('openmw.self')

local gutils = require(mp..'scripts/gutils')
local PhysAiSystem = require(mp..'scripts/physics_ai_system')

local D = require(mp..'scripts/physics_defs')


local detectionZRayOffset = 1.7*D.GUtoM

local function detectCulprit(d)
    if omwself == d.culprit then return end

    local culprit = d.culprit
    local startPos = omwself.position + util.vector3(0, 0, detectionZRayOffset)
    local endPos = culprit.position + util.vector3(0, 0, detectionZRayOffset)
    local detected = false

    -- print("Casting detection ray")
    local rayResult = nearby.castRay(startPos, endPos, { ignore = omwself })
    
    detected = rayResult.hit and rayResult.hitObject == culprit

    if not detected then
        detected = PhysAiSystem.sneakStatDetectionCheck(d.culprit, omwself)
    end
    
    if detected then
        core.sendGlobalEvent(D.e.DetectCulpritResult, {
            culprit = culprit,
            detectedBy = omwself
        })
        return
    end
end



return {
    eventHandlers = {
        [D.e.DetectCulprit] = detectCulprit
    }
}
