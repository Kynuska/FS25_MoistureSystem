MSTedderExtension = {}

-- Configuration
MSTedderExtension.DRY_THRESHOLD = 0.07

function MSTedderExtension:processDropArea(superFunc, dropArea, fillType, amount)
    local tracker = g_currentMission.harvestPropertyTracker
    if not tracker:isGrassFillType(fillType) then
        return superFunc(self, dropArea, fillType, amount)
    end

    -- Check if dropping grass into a recent hay cell - if so, convert to hay
    local sx, sy, sz = getWorldTranslation(dropArea.start)
    local wx, wy, wz = getWorldTranslation(dropArea.width)
    local hx, hy, hz = getWorldTranslation(dropArea.height)

    local startX, startY, startZ, endX, endY, endZ, radius = DensityMapHeightUtil.getLineByArea(dropArea.start,
        dropArea.width, dropArea.height, true)
    local dropped, lineOffset = DensityMapHeightUtil.tipToGroundAroundLine(self, amount, fillType, startX, startY, startZ,
        endX, endY, endZ, radius, nil, dropArea.lineOffset, false, nil, false)
    dropArea.lineOffset = lineOffset


    if dropped > 0 then
        -- Don't call addPile here - let updateGrassMoisture handle pile creation/update
        -- But store the pickup moisture so it can be used when recreating the pile

        -- Store the pickup moisture for affected grid cells
        if dropArea.outputMoisture then
            local affectedCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
            for _, cell in ipairs(affectedCells) do
                local gridKey = tracker:getSimpleGridKey(cell.gridX, cell.gridZ)
                tracker.teddedGrassMoisture[gridKey] = dropArea.outputMoisture
            end
        end

        -- Mark area as tedded so updateGrassMoisture will process it
        tracker:markAreaTedded(sx, sz, wx, wz, hx, hz)
    end
    return dropped
end

Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, MSTedderExtension.processDropArea)

function MSTedderExtension:processTedderArea(_, workArea, dt)
    local spec = self.spec_tedder
    local workAreaSpec = self.spec_workArea


    local tracker = g_currentMission.harvestPropertyTracker
    -- local grassFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("GRASS_WINDROW")
    -- local hayFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("DRYGRASS_WINDROW")

    local sx, sy, sz = getWorldTranslation(workArea.start)
    local wx, wy, wz = getWorldTranslation(workArea.width)
    local hx, hy, hz = getWorldTranslation(workArea.height)
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3

    local positionMoisture
    
    -- Check for existing grass pile moisture at this location
    for grassType, _ in pairs(HarvestPropertyTracker.GRASS_CONVERSION_MAP) do
        local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassType)
        if grassFillType then
            local existingProps = tracker:getPropertiesAtLocation(centerX, centerZ, grassFillType)
            if existingProps and existingProps.moisture then
                positionMoisture = existingProps.moisture
                break
            end
        end
    end

    local lsx, lsy, lsz, lex, ley, lez, lineRadius = DensityMapHeightUtil.getLineByAreaDimensions(sx, sy, sz, wx, wy, wz,
        hx, hy, hz, true)

    for targetFillType, inputFillTypes in pairs(spec.fillTypeConvertersReverse) do
        local pickedUpLiters = 0
        local pickedUpHay = 0
        for _, inputFillType in ipairs(inputFillTypes) do
            local inputFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(inputFillType)
            local pickup = DensityMapHeightUtil.tipToGroundAroundLine(self, -math.huge, inputFillType, lsx, lsy, lsz, lex,
                ley, lez,
                lineRadius, nil, nil, false, nil)
            if pickup ~= 0 then
                pickedUpLiters = pickedUpLiters + pickup
                if tracker:isHayFillType(inputFillType) then
                    pickedUpHay = pickedUpHay + pickup
                end
            end
        end

        if pickedUpLiters == 0 and workArea.lastDropFillType ~= FillType.UNKNOWN then
            targetFillType = workArea.lastDropFillType
        end

        local gridCells = tracker:getAffectedGridCells(sx, sz, wx, wz, hx, hz)
        if pickedUpLiters ~= 0 and tracker:isHayFillType(targetFillType) then
            for _, cell in pairs(gridCells) do
                -- Check all grass types for cleanup
                for grassType, _ in pairs(HarvestPropertyTracker.GRASS_CONVERSION_MAP) do
                    local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassType)
                    if grassFillType then
                        tracker:checkPileHasContent(cell.gridX, cell.gridZ, grassFillType)
                    end
                end
            end
        end

        workArea.lastPickupLiters = -pickedUpLiters
        workArea.litersToDrop = workArea.litersToDrop + workArea.lastPickupLiters

        -- drop
        local dropArea = workAreaSpec.workAreas[workArea.dropWindrowWorkAreaIndex]
        if dropArea ~= nil and workArea.litersToDrop > 0 then
            local dropped

            if tracker:isHayFillType(targetFillType) and pickedUpHay == 0 then
                -- override default hay drop - convert back to appropriate grass type
                local targetFillTypeName = g_fillTypeManager:getFillTypeNameByIndex(targetFillType)
                local grassTypeName = nil
                
                -- Find the grass type that converts to this hay type
                for grassType, hayType in pairs(HarvestPropertyTracker.GRASS_CONVERSION_MAP) do
                    if hayType == targetFillTypeName then
                        grassTypeName = grassType
                        break
                    end
                end
                
                if grassTypeName then
                    local grassFillType = g_fillTypeManager:getFillTypeIndexByName(grassTypeName)
                    dropArea.outputMoisture = positionMoisture
                    dropped = self:processDropArea(dropArea, grassFillType, workArea.litersToDrop)
                    dropArea.outputMoisture = nil
                else
                    dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
                end
            else
                dropped = self:processDropArea(dropArea, targetFillType, workArea.litersToDrop)
            end

            workArea.lastDropFillType = targetFillType
            workArea.lastDroppedLiters = dropped
            spec.lastDroppedLiters = spec.lastDroppedLiters + dropped
            workArea.litersToDrop = workArea.litersToDrop - dropped

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

                            if not effect.isActiveSent then
                                effect.isActiveSent = true
                                self:raiseDirtyFlags(spec.effectDirtyFlag)
                            end

                            if changedFillType then
                                g_effectManager:setEffectTypeInfo(effect.effects, targetFillType)
                            end

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

    if self:getLastSpeed() > 0.5 then
        spec.stoneLastState = FSDensityMapUtil.getStoneArea(sx, sz, wx, wz, hx, hz)
    else
        spec.stoneLastState = 0
    end

    local areaWidth = MathUtil.vector3Length(lsx - lex, lsy - ley, lsz - lez)
    local area = areaWidth * self.lastMovedDistance

    return area, area
end

Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, MSTedderExtension.processTedderArea)
