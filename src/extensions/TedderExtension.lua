---
-- TedderExtension
-- Reduces moisture when tedding grass and converts to dry grass when threshold is reached
---

MSTedderExtension = {}

-- Configuration
MSTedderExtension.MOISTURE_REDUCTION_PER_PASS = 0.05
MSTedderExtension.DRY_THRESHOLD = 0.07

---
-- Extended to handle moisture tracking when dropping tedded grass
-- Prevents automatic grass-to-hay conversion, only converting when moisture is low enough
-- @param superFunc: Original function
-- @param dropArea: The drop area parameters
-- @param fillType: The filltype being dropped
-- @param amount: Amount to drop
---
function MSTedderExtension:processDropArea(superFunc, dropArea, fillType, amount)
    -- Only handle grass windrows, let everything else (including hay) go through original function
    if g_fillTypeManager:getFillTypeNameByIndex(fillType) ~= "GRASS_WINDROW" then
        return superFunc(self, dropArea, fillType, amount)
    end

    local moistureSystem = g_currentMission.MoistureSystem
    local tracker = g_currentMission.harvestPropertyTracker
    local spec = self.spec_tedder

    if not moistureSystem or not tracker or not self.isServer then
        return superFunc(self, dropArea, fillType, amount)
    end

    -- Get the work area coordinates to check for existing piles
    local sx, _, sz = getWorldTranslation(dropArea.start)
    local wx, _, wz = getWorldTranslation(dropArea.width)
    local hx, _, hz = getWorldTranslation(dropArea.height)

    local moisture = nil

    -- First priority: use moisture from the pile we just picked up (stored during pickup)
    if spec.lastPickedMoisture then
        moisture = spec.lastPickedMoisture
        spec.lastPickedMoisture = nil  -- Clear after use
    else
        -- Fallback: check for existing pile at drop location
        local centerX = (sx + wx + hx) / 3
        local centerZ = (sz + wz + hz) / 3
        local properties = tracker:getPropertiesAtLocation(centerX, centerZ, fillType)
        
        if properties and properties.moisture then
            moisture = properties.moisture
        else
            -- Last resort: use field moisture
            moisture = moistureSystem:getMoistureAtPosition(centerX, centerZ)
        end
    end

    -- Reduce moisture by configured amount (simulating drying from tedding)
    moisture = math.max(0, moisture - MSTedderExtension.MOISTURE_REDUCTION_PER_PASS)

    -- Determine correct fillType based on moisture BEFORE dropping
    local dropFillType = fillType
    local shouldTrack = true
    
    if moisture <= MSTedderExtension.DRY_THRESHOLD then
        -- Convert to hay for smooth dropping
        dropFillType = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")
        shouldTrack = false  -- Don't track hay
    end

    -- Drop using base game logic for smooth piles
    local dropped = superFunc(self, dropArea, dropFillType, amount)

    -- Only track grass piles (not hay)
    if dropped > 0 and self.isServer and shouldTrack then
        tracker:addPile(sx, sz, wx, wz, hx, hz, dropFillType, dropped, {
            moisture = moisture
        })
    end

    return dropped
end

---
-- Extended to intercept hay conversion - forces DRYGRASS_WINDROW to GRASS_WINDROW
-- This lets our processDropArea control conversion based on moisture
-- @param superFunc: Original function
-- @param workArea: The work area being processed
-- @param dt: Delta time
---
function MSTedderExtension:processTedderArea(superFunc, workArea, dt)
    local spec = self.spec_tedder
    local workAreaSpec = self.spec_workArea

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)

    -- Pick up grass
    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(sx, sy, sz, wx, wy, wz,
        hx, hy, hz, true)

    -- Only process hay conversions - skip any reverse conversions (hay back to grass)
    local hayFillType = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")

    for targetFillType, inputFillTypes in pairs(spec.fillTypeConvertersReverse) do
        -- Skip if target is not hay - prevents hay->grass conversion
        if targetFillType ~= hayFillType then
            continue
        end

        local pickedUpLiters = 0
        local actuallyPickedUpHay = false
        local totalMoisture = 0
        local moistureCount = 0

        for _, inputFillType in ipairs(inputFillTypes) do
            local liters = DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFillType, lsx, lsy, lsz, lex,
                ley, lez, lineRadius, nil, nil, false, nil)

            -- Track if we actually picked up hay (not just grass that game wants to convert)
            if liters > 0 and g_fillTypeManager:getFillTypeNameByIndex(inputFillType) == "DRYGRASS_WINDROW" then
                actuallyPickedUpHay = true
            end

            pickedUpLiters = pickedUpLiters + liters

            -- Get moisture from picked-up pile and clean up tracked piles
            if liters > 0 and self.isServer then
                local tracker = g_currentMission.harvestPropertyTracker
                if tracker then
                    -- Get moisture from pickup location before removing
                    local centerX = (sx + wx + hx) / 3
                    local centerZ = (sz + wz + hz) / 3
                    local properties = tracker:getPropertiesAtLocation(centerX, centerZ, inputFillType)
                    
                    if properties and properties.moisture then
                        totalMoisture = totalMoisture + properties.moisture
                        moistureCount = moistureCount + 1
                    end
                    
                    tracker:removePileAtArea(sx, sz, wx, wz, hx, hz, inputFillType)
                end
            end
        end
        
        -- Store average moisture from picked-up piles for use in processDropArea
        if moistureCount > 0 then
            spec.lastPickedMoisture = totalMoisture / moistureCount
        else
            spec.lastPickedMoisture = nil
        end

        if pickedUpLiters == 0 and workArea.lastDropFillType ~= FillType.UNKNOWN then
            targetFillType = workArea.lastDropFillType
        end

        workArea.lastPickupLiters = -pickedUpLiters
        workArea.litersToDrop = workArea.litersToDrop + workArea.lastPickupLiters

        -- Drop the tedded grass
        local dropArea = workAreaSpec.workAreas[workArea.dropWindrowWorkAreaIndex]
        if dropArea ~= nil and workArea.litersToDrop > 0 then
            local dropped

            -- Only intercept auto-conversion when we picked up GRASS and game wants to make it HAY
            -- If we actually picked up HAY, let it stay as HAY
            if g_fillTypeManager:getFillTypeNameByIndex(targetFillType) == "DRYGRASS_WINDROW" and not actuallyPickedUpHay then
                local grassFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
                dropped = self:processDropArea(dropArea, grassFillTypeIndex, workArea.litersToDrop)
            else
                dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
            end

            workArea.lastDropFillType = targetFillType
            workArea.lastDroppedLiters = dropped
            spec.lastDroppedLiters = spec.lastDroppedLiters + dropped
            workArea.litersToDrop = workArea.litersToDrop - dropped

            -- Handle particles and effects
            if self.isServer then
                local lastSpeed = self:getLastSpeed(true)
                if dropped > 0 and lastSpeed > 0.5 then
                    local changedFillType = false
                    if spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] ~= targetFillType then
                        spec.tedderWorkAreaFillTypes[workArea.tedderWorkAreaIndex] = targetFillType
                        self:raiseDirtyFlags(spec.fillTypesDirtyFlag)
                        changedFillType = true
                    end

                    local effects = spec.workAreaToEffects[workArea.index]
                    if effects ~= nil then
                        for _, effect in ipairs(effects) do
                            effect.activeTime = g_currentMission.time + effect.activeTimeDuration

                            -- sync mp
                            if not effect.isActiveSent then
                                effect.isActiveSent = true
                                self:raiseDirtyFlags(spec.effectDirtyFlag)
                            end

                            if changedFillType then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                            end

                            -- enable effect
                            if not effect.isActive then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                                g_effectManager:startEffects(effect.effects)
                            end

                            g_effectManager:setDensity(effect.effects, math.max(lastSpeed / self:getSpeedLimit(), 0.6))

                            effect.isActive = true
                        end
                    end
                end
            end
        end
    end

    -- Handle stone detection
    if self:getLastSpeed() > 0.5 then
        spec.stoneLastState = FSDensityMapUtil.getStoneArea(sx, sz, wx, wz, hx, hz)
    else
        spec.stoneLastState = 0
    end

    -- Calculate area
    local areaWidth = MathUtil.vector3Length(lsx - lex, lsy - ley, lsz - lez)
    local area = areaWidth * self.lastMovedDistance

    return area, area
end

-- Hook the functions
Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, MSTedderExtension.processDropArea)
Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, MSTedderExtension.processTedderArea)
