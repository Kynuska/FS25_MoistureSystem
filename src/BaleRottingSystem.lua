---
-- BaleRottingSystem
-- Manages bale rotting during rain with grace period and gradual drying
---

BaleRottingSystem = {}
local BaleRottingSystem_mt = Class(BaleRottingSystem)

BaleRottingSystem.GRACE_PERIOD_MS = 15 * 60 * 1000 -- 15 game minutes
BaleRottingSystem.UPDATE_INTERVAL_MS = 1000 -- Check every 1 second
BaleRottingSystem.BASE_ROT_RATE = 0.0001 -- Base volume loss per timescale unit
BaleRottingSystem.DECAY_RATE = 0.375 -- Decay rate when dry (15min exposure / 40min = 0.375)

---
-- Create new BaleRottingSystem instance
-- @return BaleRottingSystem instance
---
function BaleRottingSystem.new()
    local self = setmetatable({}, BaleRottingSystem_mt)
    
    self.mission = g_currentMission
    self.isServer = self.mission:getIsServer()
    
    -- Track accumulated rain exposure time and status
    -- { [uniqueId] = { exposure = timeMS, status = "getting_wet"|"rotting"|"drying" } }
    -- Increments during rain, decrements slowly when dry
    -- Persisted in save game (exposure only, status computed on update)
    self.baleRainExposureTimes = {}
    
    -- Track last update time
    self.timeSinceLastUpdate = 0
    
    return self
end

---
-- Update bale exposure time (accumulate or decay) and determine status
-- @param uniqueId: Bale unique ID
-- @param timescaledDt: Delta time in milliseconds (already timescaled)
-- @param isExposedToRain: Boolean - is bale currently exposed to precipitation
-- @param sunDryingMultiplier: Sunshine drying bonus (1.0-1.25)
-- @return Current exposure time in milliseconds, status string
---
function BaleRottingSystem:updateBaleExposure(uniqueId, timescaledDt, isExposedToRain, sunDryingMultiplier)
    if not self.isServer then return 0, nil end
    
    local baleData = self.baleRainExposureTimes[uniqueId]
    local currentExposure = baleData and baleData.exposure or 0
    
    if isExposedToRain then
        -- Accumulate exposure during rain (cap at 2x grace period)
        currentExposure = math.min(currentExposure + timescaledDt, self.GRACE_PERIOD_MS * 2)
    else
        -- Decay exposure when dry (slower than accumulation)
        -- 15 minutes of exposure takes ~40 minutes to fully decay
        -- Apply sunshine bonus (up to 25% faster drying)
        local decayRate = self.DECAY_RATE * (g_currentMission.MoistureSystem.settings.baleExposureDecayRate or 1.0)
        currentExposure = math.max(currentExposure - (timescaledDt * decayRate * sunDryingMultiplier), 0)
    end
    
    -- Determine status
    local status = nil
    if currentExposure > 0 then
        if isExposedToRain then
            if currentExposure >= self.GRACE_PERIOD_MS then
                status = "rotting"
            else
                status = "getting_wet"
            end
        else
            status = "drying"
        end
    end
    
    -- Store or remove tracking
    if currentExposure > 0 then
        self.baleRainExposureTimes[uniqueId] = {
            exposure = currentExposure,
            status = status
        }
    else
        self.baleRainExposureTimes[uniqueId] = nil
    end
    
    return currentExposure, status
end

---
-- Main update loop - process all bales
-- @param dt: Delta time in milliseconds
---
function BaleRottingSystem:update(dt)
    if not self.isServer then return end
    
    -- Check if bale rotting is enabled
    if not g_currentMission.MoistureSystem.settings.baleRotEnabled then
        return
    end
    
    self.timeSinceLastUpdate = self.timeSinceLastUpdate + dt
    if self.timeSinceLastUpdate < self.UPDATE_INTERVAL_MS then
        return
    end
    
    -- Use accumulated time, not just last frame's dt
    local timescale = self.timeSinceLastUpdate * self.mission:getEffectiveTimeScale()
    local weather = self.mission.environment.weather
    local rainfall = weather:getRainFallScale()
    local snowfall = weather:getSnowFallScale()
    local hailfall = weather:getHailFallScale()
    
    local isRaining = rainfall > 0 or snowfall > 0 or hailfall > 0
    local indoorMask = self.mission.indoorMask
    local items = self.mission.itemSystem.itemByUniqueId
    local balesToDelete = {}
    
    -- Calculate sunshine drying bonus (up to 25% faster drying during daylight)
    local currentHour = self.mission.environment.currentHour
    local daylightStart = 6
    local daylightEnd = 20
    local isDaylight = currentHour >= daylightStart and currentHour < daylightEnd
    
    -- Process ALL tracked bales (even when not raining, for decay)
    -- Plus any rottable bales we encounter
    local balesToProcess = {}
    
    -- Add all currently tracked bales
    for uniqueId, _ in pairs(self.baleRainExposureTimes) do
        if items[uniqueId] then
            balesToProcess[uniqueId] = items[uniqueId]
        else
            -- Bale no longer exists, remove tracking
            self.baleRainExposureTimes[uniqueId] = nil
        end
    end
    
    -- Add any untracked rottable bales (if it's raining)
    if isRaining then
        for uniqueId, item in pairs(items) do
            if self:isBaleRottable(item) and not balesToProcess[uniqueId] then
                balesToProcess[uniqueId] = item
            end
        end
    end
    
    -- Process each bale
    for uniqueId, item in pairs(balesToProcess) do
        local x, _, z = getWorldTranslation(item.nodeId)
        
        -- Check if exposed to rain (outdoors, unwrapped, raining)
        local isIndoors = indoorMask:getIsIndoorAtWorldPosition(x, z)
        local isExposedToRain = isRaining and not isIndoors
        
        -- Calculate sun drying multiplier (1.0 to 1.25)
        -- Only apply bonus when: not raining, outdoors, and daylight
        local sunDryingMultiplier = 1.0
        if not isRaining and not isIndoors and isDaylight then
            sunDryingMultiplier = 1.25
        end
        
        -- Update exposure time (accumulate or decay)
        local exposureTime, status = self:updateBaleExposure(uniqueId, timescale, isExposedToRain, sunDryingMultiplier)
        
        -- Apply rotting if currently rotting
        if status == "rotting" then
            local rotLoss = self:calculateRotLoss(item, rainfall, snowfall, hailfall, timescale)
            item.fillLevel = math.max(item.fillLevel - rotLoss, 0)
            
            -- Mark for deletion if empty
            if item.fillLevel <= 0 then
                table.insert(balesToDelete, item)
            end
        end
    end
    
    -- Delete empty bales
    for i = #balesToDelete, 1, -1 do
        local bale = balesToDelete[i]
        self.baleRainExposureTimes[bale.uniqueId] = nil
        bale:delete()
    end
    
    self.timeSinceLastUpdate = 0
end

---
-- Calculate volume loss for a bale
-- @param bale: Bale object
-- @param rainfall: Rain intensity (0-1)
-- @param snowfall: Snow intensity (0-1)
-- @param hailfall: Hail intensity (0-1)
-- @param timescale: Adjusted delta time
-- @return Volume loss in liters
---
function BaleRottingSystem:calculateRotLoss(bale, rainfall, snowfall, hailfall, timescale)
    -- Base calculation (aligned with MoistureSystem weather factors)
    local weatherFactor = rainfall + (snowfall * 0.55) + (hailfall * 0.5)
    local baseLoss = weatherFactor * self.BASE_ROT_RATE * timescale
    
    -- Apply settings multiplier
    local settingsMultiplier = g_currentMission.MoistureSystem.settings.baleRotRate or 1.0
    
    return baseLoss * settingsMultiplier
end

---
-- Check if a bale should be processed for rotting
-- @param item: Item to check
-- @return Boolean - true if rottable
---
function BaleRottingSystem:isBaleRottable(item)
    -- Must be a Bale object
    if g_currentMission.objectsToClassName[item] ~= "Bale" then
        return false
    end
    
    -- Must have valid data
    if item.fillLevel == nil or item.nodeId == 0 then
        return false
    end
    
    -- Must be unwrapped
    if item.wrappingState ~= 0 then
        return false
    end
    
    -- Build rottable fillTypes dynamically from GRASS_CONVERSION_MAP
    local rottableFillTypes = {
        [FillType.SILAGE] = true,
    }
    
    -- Add all grass types (keys) and hay types (values) from conversion map
    for grassTypeName, hayTypeName in pairs(GroundPropertyTracker.GRASS_CONVERSION_MAP) do
        local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
        local hayFillType = g_fillTypeManager:getFillTypeIndexByName(hayTypeName)
        
        if grassFillType then
            rottableFillTypes[grassFillType] = true
        end
        if hayFillType then
            rottableFillTypes[hayFillType] = true
        end
    end
    
    return rottableFillTypes[item.fillType] or false
end

---
-- Clean up tracking when bale is deleted
-- @param bale: Bale being deleted
---
function BaleRottingSystem:onBaleDeleted(bale)
    if not self.isServer then return end
    self.baleRainExposureTimes[bale.uniqueId] = nil
end

---
-- Save exposure times to XML
-- @param xmlFile: XML file handle
-- @param key: Base XML key
---
function BaleRottingSystem:saveToXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    for uniqueId, baleData in pairs(self.baleRainExposureTimes) do
        -- Only save if bale still exists
        if g_currentMission.itemSystem.itemByUniqueId[uniqueId] then
            local baleKey = string.format("%s.baleRotting.bale(%d)", key, i)
            setXMLInt(xmlFile, baleKey .. "#uniqueId", uniqueId)
            setXMLInt(xmlFile, baleKey .. "#exposureTime", math.floor(baleData.exposure))
            i = i + 1
        end
    end
end

---
-- Load exposure times from XML
-- @param xmlFile: XML file handle
-- @param key: Base XML key
---
function BaleRottingSystem:loadFromXMLFile(xmlFile, key)
    if not self.isServer then return end
    
    local i = 0
    while true do
        local baleKey = string.format("%s.baleRotting.bale(%d)", key, i)
        
        if not hasXMLProperty(xmlFile, baleKey) then
            break
        end
        
        local uniqueId = getXMLInt(xmlFile, baleKey .. "#uniqueId")
        local exposureTime = getXMLInt(xmlFile, baleKey .. "#exposureTime")
        
        -- Only restore if bale still exists
        if g_currentMission.itemSystem.itemByUniqueId[uniqueId] then
            -- Status will be computed on first update
            self.baleRainExposureTimes[uniqueId] = {
                exposure = exposureTime,
                status = "drying"  -- Default status until next update
            }
        end
        
        i = i + 1
    end
end

-- Hook into Bale deletion
Bale.delete = Utils.prependedFunction(Bale.delete, function(self)
    if g_currentMission.baleRottingSystem then
        g_currentMission.baleRottingSystem:onBaleDeleted(self)
    end
end)
