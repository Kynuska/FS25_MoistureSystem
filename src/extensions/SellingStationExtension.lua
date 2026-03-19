---
-- SellingStationExtension
-- Extends SellingStation to apply moisture-based price modifiers when selling crops
---

SellingStationExtension = {}

---
-- Override addFillLevelFromTool to inject moisture-based price multiplier
-- This is called before sellFillType, allowing us to modify extraAttributes
-- @param superFunc: Original function
-- @param farmId: Farm ID selling the crop
-- @param deltaFillLevel: Amount being sold
-- @param fillTypeIndex: Type of crop being sold
-- @param fillInfo: Information about the fill source (may contain vehicle/position)
-- @param toolType: Type of tool (e.g., ToolType.BALE)
-- @param extraAttributes: Additional attributes (we'll inject priceScale here)
---
function SellingStationExtension:addFillLevelFromTool(superFunc, farmId, deltaFillLevel, fillTypeIndex, fillInfo, toolType, extraAttributes)
    -- Only apply moisture modifiers on server
    if g_currentMission:getIsServer() and deltaFillLevel > 0 then
        local moistureMultiplier = self:getMoistureMultiplierForSale(fillTypeIndex, fillInfo)

        if moistureMultiplier ~= nil and moistureMultiplier ~= 1.0 then
            -- Initialize extraAttributes if needed
            if extraAttributes == nil then
                extraAttributes = {}
            end
            extraAttributes.priceScale = moistureMultiplier
        end
    end

    -- Call original function with potentially modified extraAttributes
    return superFunc(self, farmId, deltaFillLevel, fillTypeIndex, fillInfo, toolType, extraAttributes)
end

---
-- Determine moisture multiplier for a crop being sold
-- Attempts to find moisture level from multiple sources in priority order:
-- 1. Vehicle-based moisture (from fillInfo.sourceUniqueId set by DischargeableExtension)
-- 2. Ground pile moisture (from GroundPropertyTracker)
-- @param fillTypeIndex: Type of crop being sold
-- @param fillInfo: Information about the fill source (includes sourceUniqueId from dischargeNode.info)
-- @param extraAttributes: Extra attributes
-- @return multiplier (number) or nil if no moisture data available
---
function SellingStationExtension:getMoistureMultiplierForSale(fillTypeIndex, fillInfo)
    -- Check if CropValueMap is initialized
    if CropValueMap == nil or CropValueMap.Data == nil then
        return nil
    end
    
    -- Get moisture level from various sources
    local moisture = nil
    
    -- Try to get moisture from vehicle/trailer being unloaded (via fillInfo)
    -- fillInfo comes from dischargeNode.info which we set in DischargeableExtension
    if fillInfo ~= nil and fillInfo.sourceUniqueId ~= nil then
        moisture = g_currentMission.MoistureSystem:getObjectMoisture(fillInfo.sourceUniqueId, fillTypeIndex)
    end
    
    -- If no moisture data found, return 1 (no price modification)
    if moisture == nil then
        return 1
    end
    
    -- Get grade and multiplier from CropValueMap
    local grade, multiplier = CropValueMap.getGrade(fillTypeIndex, moisture)
    
    return multiplier
end

-- Assign function to SellingStation
SellingStation.getMoistureMultiplierForSale = SellingStationExtension.getMoistureMultiplierForSale

-- Override SellingStation function
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(
    SellingStation.addFillLevelFromTool,
    SellingStationExtension.addFillLevelFromTool
)
