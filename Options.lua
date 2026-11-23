-- Reagent Scout: settings page under Options > AddOns, and the minimap button
local _, RS = ...
local Options = RS:NewModule("Options")

local ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local function OpenBrowser()
    RS:GetModule("Browser"):Toggle()
end

function RS:OpenSettings()
    if Options.categoryID then Settings.OpenToCategory(Options.categoryID) end
end

local function AddCheckbox(category, key, name, tooltip, get, set)
    local setting = Settings.RegisterProxySetting(category, "ReagentScout_" .. key, Settings.VarType.Boolean, name, true, get, set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

function Options:BuildSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Reagent Scout")
    local data = RS.data
    layout:AddInitializer(CreateSettingsButtonInitializer("", "Open Reagent Scout", OpenBrowser,
        "Opens the reagent browser, as /rs and the minimap button do.", true))
    AddCheckbox(category, "minimap", "Minimap button", "Shows the Reagent Scout button on the minimap.",
        function() return not data.minimap.hide end,
        function(value) RS:SetMinimapButton(value) end)
    AddCheckbox(category, "sources", "Track where reagents come from",
        "Remembers the vendors, creatures, nodes and fishing spots you get reagents and recipe items from, and counts looted corpses for drop rates.",
        function() return data.settings.sources end,
        function(value) data.settings.sources = value end)
    AddCheckbox(category, "share", "Share loot counts",
        "Trades loot counts with Reagent Scout users in your guild, your group and your friends lists, so everyone's drop rates improve.",
        function() return data.settings.share end,
        function(value)
            data.settings.share = value
            if value then RS:GetModule("Share"):Hello() end
        end)
    Settings.RegisterAddOnCategory(category)
    self.categoryID = category:GetID()
end

-- Minimap button -----------------------------------------------------------------

function RS:SetMinimapButton(show)
    self.data.minimap.hide = not show
    local icon = LibStub("LibDBIcon-1.0")
    if show then icon:Show("ReagentScout") else icon:Hide("ReagentScout") end
end

function Options:BuildMinimapButton()
    local broker = LibStub("LibDataBroker-1.1"):NewDataObject("ReagentScout", {
        type = "launcher",
        text = "Reagent Scout",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then RS:OpenSettings() else OpenBrowser() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Reagent Scout")
            tooltip:AddLine("Click to open the reagent browser.", 1, 1, 1)
            tooltip:AddLine("Right-click for settings.", 0.7, 0.7, 0.7)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("ReagentScout", broker, RS.data.minimap)
end

function Options:OnEnable()
    self:BuildMinimapButton()
    self:BuildSettings()
end
