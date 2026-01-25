---
-- PlayerHUDUpdateExtension
-- Extends PlayerHUDUpdater to display moisture information for fields and filltype piles
---

MSPlayerHUDExtension = {}

---
-- Show field moisture information when standing on a field
-- Appended to PlayerHUDUpdater.showFieldInfo
---
function MSPlayerHUDExtension:showFieldInfo(x, z)
    -- Initialize box on first use
    if self.moistureBox == nil then
        self.moistureBox = g_currentMission.hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
    end

    local box = self.moistureBox
    if box == nil then return end

    box:clear()

    local moistureSystem = g_currentMission.MoistureSystem
    if moistureSystem == nil then return end

    -- Only show if we're on farmable ground
    if self.fieldInfo.groundType == FieldGroundType.NONE then return end

    -- Get moisture at player position
    local moisture = moistureSystem:getMoistureAtPosition(x, z)

    box:setTitle(g_i18n:getText("moistureSystem_fieldInfo"))

    -- Get current month for clamp ranges
    local currentMonth = g_currentMission.environment.currentPeriod
    local environment = moistureSystem.settings.currentEnvironment
    local clamp = MoistureClamp[environment][currentMonth]

    -- Show current moisture
    box:addLine(
        g_i18n:getText("moistureSystem_moisture"),
        string.format("%.1f%%", moisture * 100)
    )

    -- Show expected range for this month/environment
    box:addLine(
        g_i18n:getText("moistureSystem_range"),
        string.format("%.0f%% - %.0f%%", clamp.Min, clamp.Max)
    )

    box:showNextFrame()
end

PlayerHUDUpdater.showFieldInfo = Utils.appendedFunction(PlayerHUDUpdater.showFieldInfo,
    MSPlayerHUDExtension.showFieldInfo)

---
-- Track raycast position for filltype lookup
---
function MSPlayerHUDExtension:setCurrentRaycastFillTypeCoords(x, y, z, dirX, dirY, dirZ)
    if x == nil or y == nil or z == nil then
        self.currentRaycastFillTypeCoords = nil
        return
    end

    -- Only update if coordinates changed
    if self.currentRaycastFillTypeCoords ~= nil then
        local curX, curY, curZ = unpack(self.currentRaycastFillTypeCoords)
        if curX == x and curY == y and curZ == z then
            return
        end
    end

    self.currentRaycastFillTypeCoords = { x, y, z }
end

PlayerHUDUpdater.setCurrentRaycastFillTypeCoords = MSPlayerHUDExtension.setCurrentRaycastFillTypeCoords

---
-- Show moisture information for filltype piles being looked at
---
function MSPlayerHUDExtension:showFillTypeInfo()
    if self.currentRaycastFillTypeCoords == nil then return end

    -- Initialize box on first use
    if self.fillTypeBox == nil then
        self.fillTypeBox = g_currentMission.hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
    end

    local box = self.fillTypeBox
    if box == nil then return end

    local harvestTracker = g_currentMission.harvestPropertyTracker
    if harvestTracker == nil then
        box:clear()
        return
    end

    local x, y, z = unpack(self.currentRaycastFillTypeCoords)

    -- Get filltype at this position (sample 2m x 2m area)
    local fillTypeIndex = DensityMapHeightUtil.getFillTypeAtArea(x, z, x - 1, z - 1, x + 1, z + 1)
    if fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN then
        box:clear()
        return
    end

    -- Get pile properties from tracker
    local properties = harvestTracker:getPilePropertiesAtPosition(x, z, fillTypeIndex)
    if properties == nil then
        box:clear()
        return
    end

    local fillTypeName = g_fillTypeManager:getFillTypeTitleByIndex(fillTypeIndex)
    local moisture = properties.moisture

    box:clear()
    box:setTitle(fillTypeName)

    -- Show moisture level
    box:addLine(
        g_i18n:getText("moistureSystem_moisture"),
        string.format("%.1f%%", moisture * 100)
    )

    -- Show volume if available
    if properties.volume then
        box:addLine(
            g_i18n:getText("infohud_amount"),
            g_i18n:formatVolume(properties.volume, 0)
        )
    end

    box:showNextFrame()
end

PlayerHUDUpdater.showFillTypeInfo = MSPlayerHUDExtension.showFillTypeInfo

---
-- Call showFillTypeInfo in update loop
-- Appended to PlayerHUDUpdater.update
---
function MSPlayerHUDExtension:update(dt, x, y, z, rotY)
    self:showFillTypeInfo()
end

PlayerHUDUpdater.update = Utils.appendedFunction(PlayerHUDUpdater.update, MSPlayerHUDExtension.update)

---
-- Clean up boxes on delete
-- Appended to PlayerHUDUpdater.delete
---
function MSPlayerHUDExtension:delete()
    if self.moistureBox ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(self.moistureBox)
    end
    if self.fillTypeBox ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(self.fillTypeBox)
    end
end

PlayerHUDUpdater.delete = Utils.appendedFunction(PlayerHUDUpdater.delete, MSPlayerHUDExtension.delete)
