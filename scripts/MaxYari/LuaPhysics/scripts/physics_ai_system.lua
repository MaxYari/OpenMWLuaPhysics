local mp = 'scripts/MaxYari/LuaPhysics/'

local core = require("openmw.core")
local util = require('openmw.util')
local types = require('openmw.types')
local crimes = require('openmw.interfaces').Crimes

local gutils = require(mp..'scripts/gutils')
local D = require(mp..'scripts/physics_defs')
local moveUtils = require(mp..'scripts/movement_utils')

local module = {}

local maxMinorOffenses = 30
local offensiveDragDistance = 4*D.GUtoM

-- Check if the culprit is allowed to touch the object
local function canTouch(object, culprit)
    local ownerId = object.owner.recordId
    local factionId = object.owner.factionId
    local requiredRank = object.owner.factionRank or 0
    local culpritRank = 0
    if factionId then culpritRank = types.NPC.getFactionRank(culprit, factionId) end

    if ownerId and culprit.recordId ~= ownerId then
        return false
    end

    if factionId ~= nil and culpritRank < requiredRank then
        return false
    end

    return true
end
module.canTouch = canTouch

-- Check if the culprit is detected by an NPC
local maxDetectionRaysPerFrame = 2

local touchMaxDetecDist = 20*D.GUtoM
local touchMinDetecDist = 3*D.GUtoM
local touchMaxDetecDistInterior = 15*D.GUtoM

local maxSneakDistMult = 2.0

local function sneakStatDetectionCheck(culprit, npc)
    -- Calculate detection chance based on sneak skill and distance   
    local maxDist = touchMaxDetecDist
    if not culprit.cell.isExterior then maxDist = touchMaxDetecDistInterior end
    local sneakSkill = gutils.getSkill(culprit, gutils.Actor.SKILL.sneak).modified or 0    
    local distance = (culprit.position - npc.position):length()
    if distance > maxDist then return false end
    local multiplier = util.remap(util.clamp(distance, touchMinDetecDist, maxDist), touchMinDetecDist, maxDist, 1.0, maxSneakDistMult)
    local adjustedSkill = sneakSkill * multiplier
    local detectionRoll = math.random(1, 100)
    local detected = detectionRoll > adjustedSkill
    
    return detected
end
module.sneakStatDetectionCheck = sneakStatDetectionCheck

local function isDetectedBy(culprit, npc)
    local npcPos = npc.position
    local culpritPos = culprit.position
    local directionToCulprit = (culpritPos - npcPos):normalize()
    local rayWasCast = false
    local detected = false

    -- Check if NPC is facing the culprit
    if moveUtils.lookDirection(npc):dot(directionToCulprit) > 0 then
        -- Cast a ray to check line of sight
        npc:sendEvent(D.e.DetectCulprit, {culprit = culprit})  
        rayWasCast = true
    else
        detected = sneakStatDetectionCheck(culprit, npc)
    end
    
    return detected, rayWasCast
end

local function runDistributedDetection(c)
    
    local detectedBy
    local rayCasts = 0

    local function doDetectionOnce(npcs)        
        if #npcs == 0 then return end
        if detectedBy then return end
        
        local randI = math.random(1,#npcs)
        
        local randomNpc = table.remove(npcs, math.random(1,#npcs))
        
        local detected, rayWasCast = isDetectedBy(c.culprit, randomNpc)
        
        if detected then detectedBy = randomNpc end
        
        if rayWasCast then rayCasts = rayCasts + 1 end        
    end

    while rayCasts <= maxDetectionRaysPerFrame and (#c.owner > 0 or #c.factionMembers > 0 or #c.guards > 0) do        
        doDetectionOnce(c.owner)
        doDetectionOnce(c.factionMembers)
        doDetectionOnce(c.guards)      
        if detectedBy then break end
    end    
    
    if detectedBy then
        c.detectedBy = detectedBy                
    end
    
end

local cellCaches = {}
local function findRelevantNPCsInCell(cell, npcs, ownerId, factionId)
    -- Fetches owner, guards and faction members from the cell, those fetches are cached so the actual loop
    -- through all the cell actors will only happen once in rougly 3 seconds

    if not cellCaches[cell.id] then cellCaches[cell.id] = gutils.GenericCache:new(3 + math.random()) end

    local cache = cellCaches[cell.id]

    local ownerKey
    if ownerId then ownerKey = "O_"..ownerId end    
    local factionMemKey
    if factionId then factionMemKey = "F_"..factionId end
    local guardsKey = "G_"..cell.id
    
    local cachedOwner = ownerKey and cache:get(ownerKey)
    local cachedGuards = cache:get(guardsKey)
    local cachedFactionMembers = factionMemKey and cache:get(factionMemKey)

    local owner = {}
    local guards = {}
    local factionMembers = {}

    if not cachedOwner or not cachedGuards or not cachedFactionMembers then
        for _, npc in ipairs(npcs) do
            if ownerId and not cachedOwner then
                if npc.recordId == ownerId then owner = {npc} end
            end
            if not cachedGuards then
                if string.find(npc.recordId, "guard") then table.insert(guards, npc) end
            end
            if factionId and not cachedFactionMembers then
                if types.NPC.getFactionRank(npc, factionId) > 0 then table.insert(factionMembers, npc) end
            end
        end
    end

    if ownerKey and cachedOwner then
        owner = cachedOwner.data
    elseif ownerKey then
        cache:put(ownerKey, owner)
    end

    if cachedGuards then
        guards = cachedGuards.data
    else
        cache:put(guardsKey, guards)
    end

    if factionId and cachedFactionMembers then
        factionMembers = cachedFactionMembers.data
    elseif factionId then
        cache:put(factionMemKey, factionMembers)
    end
    
    return gutils.shallowArrayCopy(owner), gutils.shallowArrayCopy(guards), gutils.shallowArrayCopy(factionMembers)
end
module.findRelevantNPCsInCell = findRelevantNPCsInCell

local culpritDataTTL = 1
local fenagleCulprits = {}
local function onObjectFenagled(data)
    -- This is a convolutedly optimised function. It creates a culprit record (a player who touched an object) and stores on it all objects that been touched
    -- as well as all actrors that might be alarmed by this object being touched (actor fetching is also cached!).
    -- then in onUpdate - those actors run detection logic againts the culprit, but only few actors at a time, so the frame is not overload with raycasts
    -- If culprit is detected - all their object manipulations and offenses of past 1 second (culpritDataTTL) - become persistent/detected.
    -- If those persistent object manipulations and offenses go beyound some thresholds (checked in onUpdate) - crime is reported.
    
    -- if not data.culprit then return end
    if not data.culprit then return end
    if canTouch(data.object, data.culprit) then return end
    if not data.object.cell or not data.culprit then return end

    local now = core.getRealTime()
    
    -- Get or create data on the culprit and on this object
    local culpritData = fenagleCulprits[data.culprit.id]
    if not culpritData then        
        fenagleCulprits[data.culprit.id] = {
            detected = false,
            culprit = data.culprit,
            detectedFenagledObjects = {},
            fenagledObjects = {},
            offenses = 0,
            detectedOffenses = 0,
            isValid = function(self)
                local now = core.getRealTime()
                return now - self.updatedAt <= culpritDataTTL
            end
        }
        culpritData = fenagleCulprits[data.culprit.id]
    end

    if data.isOffensive then culpritData.offenses = culpritData.offenses + 1 end
    
    local ownerId = data.object.owner.recordId
    local factionId = data.object.owner.factionId
    
    if not culpritData.updatedAt or not culpritData:isValid() then
        culpritData.updatedAt = now
        
        local owner, guards, factionMembers = findRelevantNPCsInCell(data.object.cell, data.object.cell:getAll(types.NPC), ownerId, factionId)
        culpritData.owner = owner
        culpritData.guards = guards
        culpritData.factionMembers = factionMembers
    end

    -- print("Fenagled object"..data.object.recordId.."recorded, offenses:",culpritData.offenses,culpritData.detectedOffenses)
    -- Adding object to a list in the culprit data
    local objFenagleData = culpritData.fenagledObjects[data.object.id]
    if not objFenagleData then objFenagleData = culpritData.detectedFenagledObjects[data.object.id] end
    if not objFenagleData then 
        objFenagleData = {
            startPos = data.object.position,
            obj = data.object, 
        }
        culpritData.fenagledObjects[data.object.id] = objFenagleData
    end
end
module.onObjectFenagled = onObjectFenagled

local function onDetectCulpritResult(e) 
    if e.detectedBy and fenagleCulprits[e.culprit.id] then
        fenagleCulprits[e.culprit.id].detectedBy = e.detectedBy
    end
end
module.onDetectCulpritResult = onDetectCulpritResult

local function reportCrime(objectOrPrice, culprit, witness, isDestroyed) 
    if culprit.type ~= types.Player then return end
    
    -- fetch object value here and put it into arg
    local price = 0
    local factionId = nil
    if type(objectOrPrice) == "number" then
        price = objectOrPrice
    else 
        local object = objectOrPrice
        factionId = object.owner.factionId
        price = object.type.record(object).value
        -- print("Price from record", price)
    end
    
    if not price then price = 1 end
    
    if isDestroyed then price = price*2 
    else price = price * 0.1 end
    if price < 25 then price = 25 end

    local type = types.Player.OFFENSE_TYPE.Pickpocket
    --if isDestroyed then type = types.Player.OFFENSE_TYPE.Assault end

    print("Reporting crime",price,witness)
    crimes.commitCrime(culprit, {
        arg = price,
        faction = factionId,
        victim = witness,
        type = type
    })
end
module.reportCrime = reportCrime

local function update()
    -- When a physics object is moved around by a culprit (player) - we collect all actors that might be interested in reporting a crime
    -- and then here we check if they detected a culprit here, detetction checks use raycasts, so for optimisation purposes only few
    -- of them are done per frame
    for recordId, c in pairs(fenagleCulprits) do
        if c:isValid() then
            -- Attempt to detect culprit
            if not c.detectedBy then
                runDistributedDetection(c)
            end
            if c.detectedBy then
                -- If we were detected throughought the last second - move all important data (objects touched, offenses commited)
                -- into persistant variables. I.e npcs will "remember" the things you did during that second, since they detected you
                -- next ~= nil checks if table is not empty
                if next(c.fenagledObjects) ~= nil then
                    -- fenagledObjects are reset every 1 sec, but detected fenagled objects stay until cell transition
                    gutils.shallowMergeTables(c.detectedFenagledObjects, c.fenagledObjects)
                    c.fenagledObjects = {}
                end
                c.detectedOffenses = c.detectedOffenses + c.offenses
                c.offenses = 0
                c.lastDetectedBy = c.detectedBy
            end
        else            
            c.detectedBy = nil
            c.fenagledObjects = {}
            c.offenses = 0
        end

        -- Check if player went too far with detected object and needs to be crimed
        for _, objData in pairs(c.detectedFenagledObjects) do
            if objData.obj:isValid() and objData.obj.cell and (objData.obj.position - objData.startPos):length() > offensiveDragDistance then
                print("CRIME CRIME CRIME, "..objData.obj.recordId.." WAS MOVED TOO MUCH")
                reportCrime(objData.obj, c.culprit, c.lastDetectedBy, false)
                c.detectedFenagledObjects = {}
                break
            end
        end

        -- Check if player commited too many offenses
        if c.detectedOffenses > maxMinorOffenses then
            print("CRIME CRIME CRIME, TOO MANY OFFENSES "..c.detectedOffenses)
            for key, objData in pairs(c.detectedFenagledObjects) do
                reportCrime(objData.obj, c.culprit, c.lastDetectedBy, false)
                break
            end
            c.detectedOffenses = 0
        end

        -- Wipe culprit and objects data on cell change
        if not c.lastCell then c.lastCell = c.culprit.cell end
        if c.culprit.cell ~= c.lastCell then
            print("Culprit"..recordId.." changed cell, wiping culprit data.")
            fenagleCulprits[recordId] = nil
        end
    end
end

module.update = update

return module