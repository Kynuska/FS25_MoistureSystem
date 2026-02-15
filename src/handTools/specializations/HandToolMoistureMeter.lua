----------------------------------------------------------------------------------------------------
-- HandToolMoistureMeter
----------------------------------------------------------------------------------------------------
-- Purpose:  Specialization for Moisture Meter hand tool
--           Prints player location and field moisture when activated
--
-- Copyright (c) 2025
----------------------------------------------------------------------------------------------------

HandToolMoistureMeter = {}

local specName = "spec_FS25_MoistureSystem.moistureMeter"

---Register functions
function HandToolMoistureMeter.registerFunctions(handTool)
    SpecializationUtil.registerFunction(handTool, "performMeasurement", HandToolMoistureMeter.performMeasurement)
end

---Register event listeners
function HandToolMoistureMeter.registerEventListeners(handTool)
    SpecializationUtil.registerEventListener(handTool, "onPostLoad", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onDelete", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onDraw", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldStart", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onHeldEnd", HandToolMoistureMeter)
    SpecializationUtil.registerEventListener(handTool, "onRegisterActionEvents", HandToolMoistureMeter)
end

---Check if prerequisites are present
function HandToolMoistureMeter.prerequisitesPresent()
    print("[MoistureSystem] Loaded handTool: HandToolMoistureMeter")
    return true
end

---Initialize on load
function HandToolMoistureMeter:onPostLoad(savegame)
    local spec = self[specName]

    if self.isClient then
        spec.defaultCrosshair = self:createCrosshairOverlay("gui.crosshairDefault")
    end

    spec.activateText = g_i18n:getText("moistureSystem_measureLocation")
    spec.isActive = false

    print("[MoistureSystem] Moisture meter initialized")
end

---Cleanup
function HandToolMoistureMeter:onDelete()
    local spec = self[specName]

    if spec.defaultCrosshair ~= nil then
        spec.defaultCrosshair:delete()
        spec.defaultCrosshair = nil
    end
end

---Called when player picks up the tool
function HandToolMoistureMeter:onHeldStart()
    if g_localPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then return end

    local spec = self[specName]
    spec.isActive = true

    print("[MoistureSystem] Moisture meter picked up")
end

---Called when player drops/holsters the tool
function HandToolMoistureMeter:onHeldEnd()
    if g_localPlayer == nil then return end

    local spec = self[specName]
    spec.isActive = false

    print("[MoistureSystem] Moisture meter put away")
end

---Register action events (button bindings)
function HandToolMoistureMeter:onRegisterActionEvents()
    if self:getIsActiveForInput(true) then
        local _, eventId = self:addActionEvent(
            InputAction.ACTIVATE_HANDTOOL,
            self,
            HandToolMoistureMeter.onActionFired,
            false, true, false, true, nil
        )

        local spec = self[specName]
        spec.activateActionEventId = eventId

        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, spec.activateText)
        g_inputBinding:setActionEventActive(eventId, true)
    end
end

---Called when activate button is pressed
function HandToolMoistureMeter:onActionFired()
    self:performMeasurement()
end

---Perform the measurement
function HandToolMoistureMeter:performMeasurement()
    local player = self:getCarryingPlayer()
    if player == nil then return end

    -- Get player position
    local x, y, z = getWorldTranslation(player.rootNode)

    -- Print location
    print(string.format("[MoistureSystem] ========== MEASUREMENT =========="))
    print(string.format("[MoistureSystem] Player Location: X=%.2f, Y=%.2f, Z=%.2f", x, y, z))

    -- Get terrain height
    local terrainHeight = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    print(string.format("[MoistureSystem] Terrain Height: %.2f", terrainHeight))

    -- Get moisture at position (if MoistureSystem available)
    if g_currentMission.MoistureSystem then
        local moisture = g_currentMission.MoistureSystem:getMoistureAtPosition(x, z)
        print(string.format("[MoistureSystem] Field Moisture: %.2f%%", moisture * 100))

        -- Get system moisture info
        local system = g_currentMission.MoistureSystem
        print(string.format("[MoistureSystem] Current System Moisture: %.2f%%", system.currentMoisturePercent * 100))
    else
        print("[MoistureSystem] MoistureSystem not available")
    end

    print(string.format("[MoistureSystem] ==================================="))
end

---Draw UI overlay
function HandToolMoistureMeter:onDraw()
    local spec = self[specName]

    if spec.defaultCrosshair then
        spec.defaultCrosshair:render()
    end
end
