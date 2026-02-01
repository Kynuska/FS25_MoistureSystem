---
-- MoistureSystem - Calendar Frame
-- Displays monthly moisture ranges based on MoistureClamp data
--

MoistureGuiCalendar = {}

local MoistureGuiCalendar_mt = Class(MoistureGuiCalendar, TabbedMenuFrameElement)

function MoistureGuiCalendar.new(l18n)
    local self = TabbedMenuFrameElement.new(nil, MoistureGuiCalendar_mt)
    self.l18n = l18n
    self.monthCells = {}
    return self
end

function MoistureGuiCalendar:initialize()
    -- Initialize frame content here
end

function MoistureGuiCalendar:onGuiSetupFinished()
    MoistureGuiCalendar:superClass().onGuiSetupFinished(self)

    -- Map the month cells for easy access
    for i = 1, 12 do
        self.monthCells[i] = self["month" .. i]
    end

    -- Set month header texts using formatPeriod
    self:setMonthHeaders()
end

---
-- Set the month header texts
---
function MoistureGuiCalendar:setMonthHeaders()
    for month = 1, 12 do
        if self["monthHeader" .. month] then
            self["monthHeader" .. month]:setText(g_i18n:formatPeriod(month, true))
        end
    end
end

function MoistureGuiCalendar:onFrameOpen()
    MoistureGuiCalendar:superClass().onFrameOpen(self)
    self:updateCalendar()
end

function MoistureGuiCalendar:onFrameClose()
    MoistureGuiCalendar:superClass().onFrameClose(self)
end

---
-- Update the calendar display with current environment settings
---
function MoistureGuiCalendar:updateCalendar()
    if not g_currentMission or not g_currentMission.MoistureSystem then
        return
    end

    -- Get current environment setting
    local environment = g_currentMission.MoistureSystem.settings.environment

    -- Get moisture data for this environment
    local monthData = MoistureClamp.Environments[environment].Months

    -- Update each month cell with the min-max range
    for period = 1, 12 do
        local month = MoistureSystem.periodToMonth(period)
        local data = monthData[month]
        if data and self.monthCells[period] then
            local rangeText = string.format("%d-%d%%", data.Min, data.Max)
            self.monthCells[period]:setText(rangeText)
        end
    end

    -- Update the environment label
    local envName
    if environment == MoistureClampEnvironments.DRY then
        envName = g_i18n:getText("setting_moisture_environment_dry")
    elseif environment == MoistureClampEnvironments.WET then
        envName = g_i18n:getText("setting_moisture_environment_wet")
    else
        envName = g_i18n:getText("setting_moisture_environment_normal")
    end

    if self.environmentLabel then
        self.environmentLabel:setText(envName)
    end
end
