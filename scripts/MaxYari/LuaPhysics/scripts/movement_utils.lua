local util = require('openmw.util')

local module = {}

local function lookDirection(actor)
    return actor.rotation:apply(util.vector3(0, 1, 0))
end
module.lookDirection = lookDirection

local function flatAngleBetween(a, b)
    ---@diagnostic disable-next-line: deprecated
    return math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
end
module.flatAngleBetween = flatAngleBetween

local function lookRotation(actor, targetPos)
    local lookDir = lookDirection(actor)
    local desiredLookDir = targetPos - actor.position
    local angle = flatAngleBetween(lookDir, desiredLookDir)
    return angle
end
module.lookRotation = lookRotation

local function calculateMovement(actor, moveDir)
    local lookDir = lookDirection(actor)
    local angle = flatAngleBetween(lookDir, moveDir)

    local forwardVec = util.vector2(1, 0)
    local movementVec = forwardVec:rotate(-angle):normalize();

    return movementVec.x, movementVec.y
end
module.calculateMovement = calculateMovement

local function calcSpeedMult(desiredSpeed, walkSpeed, runSpeed)
    local speedMult = 1
    local shouldRun = true
    if desiredSpeed == -1 then

    elseif desiredSpeed < walkSpeed then
        shouldRun = false
        speedMult = desiredSpeed / walkSpeed
    elseif desiredSpeed < runSpeed then
        shouldRun = true
        speedMult = desiredSpeed / runSpeed
    end

    return speedMult, shouldRun
end
module.calcSpeedMult = calcSpeedMult

local function directionRelativeToVec(vec, directionStr)
    local vec2D = util.vector2(vec.x, vec.y)
    local directionMult
    if directionStr == "forward" then
        directionMult = 0
    elseif directionStr == "left" then
        directionMult = 1
    elseif directionStr == "right" then
        directionMult = -1
    elseif directionStr == "back" then
        directionMult = 2
    else
        error("Wrong direction property passed into directionRelativeToVec. Direction: " .. tostring(directionStr), 2)
    end

    local moveDir2D = vec2D:rotate(directionMult * math.pi / 2)
    local moveDir3D = util.vector3(moveDir2D.x, moveDir2D.y, 0):normalize()

    return moveDir3D
end
module.directionRelativeToVec = directionRelativeToVec

return module
