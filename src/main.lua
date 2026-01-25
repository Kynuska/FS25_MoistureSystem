MoistureSystem = {}

MoistureSystem.dir = g_currentModDirectory
MoistureSystem.SaveKey = "MoistureSystem"

function MoistureSystem:loadMap()
    g_currentMission.MoistureSystem = self
    self.didLoadFromXML = false
    self.midHeight = 0
    self.currentMoisturePercent = 0
    self.timeSinceLastUpdate = 0
    self.updateInterval = 5000 -- Update every 5 seconds (in milliseconds)

    -- Initialize settings
    self.settings = {
        environment = MoistureClampEnvironments.NORMAL -- Default to NORMAL
    }

    -- Initialize property tracker
    g_currentMission.harvestPropertyTracker = HarvestPropertyTracker.new()

    -- Load from XML file (called directly during loadMap, not via hook)
    self:loadFromXMLFile()

    -- Inject menu after GUI is ready
    if g_gui then
        MoistureSettings.injectMenu()
    end
end

function MoistureSystem:update(dt)
    if not g_currentMission:getIsServer() then return end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + dt

    -- Only update every updateInterval milliseconds
    if self.timeSinceLastUpdate >= self.updateInterval then
        self:updateMoistureLevel(self.timeSinceLastUpdate)
        self.timeSinceLastUpdate = 0
    end
end

---
-- Update moisture level based on weather conditions
-- @param timescale: Time elapsed in milliseconds since last update
---
function MoistureSystem:updateMoistureLevel(timescale)
    local weather = g_currentMission.environment.weather

    -- Get current weather conditions
    local rainfall = weather:getRainFallScale()
    local snowfall = weather:getSnowFallScale()
    local temperature = weather.temperatureUpdater.currentTemperature or 20
    local currentHour = g_currentMission.environment.currentHour

    -- Calculate moisture delta
    local moistureDelta = 0

    -- Gain moisture from rain/snow
    if rainfall > 0 or snowfall > 0 then
        moistureDelta = moistureDelta + (rainfall + snowfall * 0.75) * 0.009 * (timescale / 100000)
    end

    -- Lose moisture from temperature (warmer = more loss)
    -- Only lose during daytime (6am-8pm) or reduced loss at night
    local daylightStart = 6
    local daylightEnd = 20
    local sunFactor = (currentHour >= daylightStart and currentHour < daylightEnd) and 1 or 0.33

    if temperature >= 45 then
        moistureDelta = moistureDelta - (temperature * 0.000012 * (timescale / 100000) * sunFactor)
    elseif temperature >= 35 then
        moistureDelta = moistureDelta - (temperature * 0.0000088 * (timescale / 100000) * sunFactor)
    elseif temperature >= 25 then
        moistureDelta = moistureDelta - (temperature * 0.0000038 * (timescale / 100000) * sunFactor)
    elseif temperature >= 15 then
        moistureDelta = moistureDelta - (temperature * 0.0000012 * (timescale / 100000) * sunFactor)
    elseif temperature > 0 then
        moistureDelta = moistureDelta - (temperature * 0.0000005 * (timescale / 100000) * sunFactor)
    end

    -- Apply moisture change with clamping
    self:adjustMoisture(moistureDelta)
end

---
-- Adjust current moisture level while respecting min/max clamps
-- @param delta: Amount to change moisture (can be positive or negative)
---
function MoistureSystem:adjustMoisture(delta)
    -- Get current month and environment
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment

    -- Get min/max for current month and environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min / 100 -- Convert to 0-1 scale
    local maxMoisture = monthData.Max / 100 -- Convert to 0-1 scale

    -- Apply delta and clamp to min/max range
    self.currentMoisturePercent = math.max(minMoisture, math.min(maxMoisture, self.currentMoisturePercent + delta))
end

function MoistureSystem:getMoistureAtPosition(x, z)
    local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)

    -- At midHeight, return currentMoisturePercent
    -- Higher elevation = lower moisture, lower elevation = higher moisture
    local heightRange = self.maxHeight - self.minHeight
    if heightRange > 0 then
        -- Calculate proportional difference from midHeight (-1 to +1 range)
        local heightDiff = height - self.midHeight
        local heightFactor = heightDiff / (heightRange / 2)

        -- Adjust moisture: higher elevation reduces moisture, lower increases it
        local moistureLevel = self.currentMoisturePercent - (heightFactor * 0.2)
        return math.max(0, math.min(1, moistureLevel))
    else
        return self.currentMoisturePercent
    end
end

function MoistureSystem:firstLoad()
    self:findMidHeight()

    -- Get current month and environment
    local month = MoistureSystem.periodToMonth(g_currentMission.environment.currentPeriod)
    local environment = self.settings.environment

    -- Get min/max for current month and environment
    local monthData = MoistureClamp.Environments[environment].Months[month]
    local minMoisture = monthData.Min
    local maxMoisture = monthData.Max

    -- Set current moisture to middle of range, converted to 0-1 scale
    local midMoisture = (minMoisture + maxMoisture) / 2
    self.currentMoisturePercent = midMoisture / 100
end

function MoistureSystem:findMidHeight()
    local minHeight = math.huge
    local maxHeight = -math.huge
    local count = 0
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen and farmland.field ~= nil then
            local field = farmland.field
            local x, z = field:getCenterOfFieldWorldPosition()
            local height = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
            minHeight = math.min(minHeight, height)
            maxHeight = math.max(maxHeight, height)
            count = count + 1
        end
    end
    if count > 0 then
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.midHeight = (minHeight + maxHeight) / 2
    else
        self.minHeight = 0
        self.maxHeight = 0
        self.midHeight = 0
    end
end

function MoistureSystem.periodToMonth(period)
    period = period + 2
    if period > 12 then
        period = period - 12
    end
    return period
end

function MoistureSystem:onStartMission()
    local ms = g_currentMission.MoistureSystem

    if g_currentMission:getIsServer() then
        -- Initialize mod on new game
        if not ms.didLoadFromXML then
            ms:firstLoad()
        end
    end
end

function MoistureSystem:loadFromXMLFile()
    if not g_currentMission:getIsServer() then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(), g_currentMission.missionInfo.savegameIndex)
    end
    savegameFolderPath = savegameFolderPath .. "/"

    if fileExists(savegameFolderPath .. MoistureSystem.SaveKey .. ".xml") then
        local xmlFile = loadXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml")

        -- Load settings
        local environment = getXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#environment")
        if environment then
            self.settings.environment = environment
        end

        if g_currentMission.harvestPropertyTracker then
            g_currentMission.harvestPropertyTracker:loadFromXMLFile(xmlFile, MoistureSystem.SaveKey)
        end

        self.didLoadFromXML = true
        delete(xmlFile)
    end
end

function MoistureSystem:saveToXmlFile()
    if not g_currentMission:getIsServer() then return end

    local savegameFolderPath = g_currentMission.missionInfo.savegameDirectory .. "/"
    if savegameFolderPath == nil then
        savegameFolderPath = ('%ssavegame%d'):format(getUserProfileAppPath(),
            g_currentMission.missionInfo.savegameIndex .. "/")
    end

    local xmlFile = createXMLFile(MoistureSystem.SaveKey, savegameFolderPath .. MoistureSystem.SaveKey .. ".xml",
        MoistureSystem.SaveKey)

    -- Save settings
    setXMLInt(xmlFile, MoistureSystem.SaveKey .. ".settings#environment", self.settings.environment)

    if g_currentMission.harvestPropertyTracker then
        g_currentMission.harvestPropertyTracker:saveToXMLFile(xmlFile, MoistureSystem.SaveKey)
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, MoistureSystem.saveToXmlFile)
FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, MoistureSystem.onStartMission)
addModEventListener(MoistureSystem)
