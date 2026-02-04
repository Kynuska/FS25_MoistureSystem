---
-- MoistureSystem - Grades Frame
--

MoistureGuiGrades = {}

local MoistureGuiGrades_mt = Class(MoistureGuiGrades, TabbedMenuFrameElement)

function MoistureGuiGrades.new(l18n)
    local self = TabbedMenuFrameElement.new(nil, MoistureGuiGrades_mt)
    self.l18n = l18n
    self.cropGradeRenderer = CropGradeTableRenderer.new()
    return self
end

function MoistureGuiGrades:initialize()
    -- Initialize frame content here
end

function MoistureGuiGrades:onGuiSetupFinished()
    MoistureGuiGrades:superClass().onGuiSetupFinished(self)
    
    self.cropGradeTable:setDataSource(self.cropGradeRenderer)
    self.cropGradeTable:setDelegate(self.cropGradeRenderer)
end

function MoistureGuiGrades:onFrameOpen()
    MoistureGuiGrades:superClass().onFrameOpen(self)
    self:updateTable()
end

function MoistureGuiGrades:onFrameClose()
    MoistureGuiGrades:superClass().onFrameClose(self)
end

function MoistureGuiGrades:updateTable()
    local tableData = {}
    
    -- Build table data from CropValueMap
    for fillTypeIndex, ranges in pairs(CropValueMap.Data) do
        -- local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
        local fillTypeTitle = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex).title
        
        -- Collect ranges for each grade (up to 2 ranges per grade)
        local gradeData = {
            [CropValueMap.Grades.A] = {},
            [CropValueMap.Grades.B] = {},
            [CropValueMap.Grades.C] = {},
            [CropValueMap.Grades.D] = {}
        }
        
        for _, range in ipairs(ranges) do
            local lowerPercent = math.floor(range.lower * 100)
            local upperPercent = math.floor(range.upper * 100)
            local multiplierPercent = math.floor(range.multiplier * 100)
            local rangeText = string.format("%d-%d%% (%d%%)", lowerPercent, upperPercent, multiplierPercent)
            table.insert(gradeData[range.grade], rangeText)
        end
        
        table.insert(tableData, {
            name = fillTypeTitle,
            gradeA1 = gradeData[CropValueMap.Grades.A][1] or "-",
            gradeA2 = gradeData[CropValueMap.Grades.A][2] or "",
            gradeB1 = gradeData[CropValueMap.Grades.B][1] or "-",
            gradeB2 = gradeData[CropValueMap.Grades.B][2] or "",
            gradeC1 = gradeData[CropValueMap.Grades.C][1] or "-",
            gradeC2 = gradeData[CropValueMap.Grades.C][2] or "",
            gradeD1 = gradeData[CropValueMap.Grades.D][1] or "-",
            gradeD2 = gradeData[CropValueMap.Grades.D][2] or ""
        })
    end
    
    -- Sort by name
    table.sort(tableData, function(a, b) return a.name < b.name end)
    
    self.cropGradeRenderer:setData(tableData)
    self.cropGradeTable:reloadData()
end
