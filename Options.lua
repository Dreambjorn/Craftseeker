-- Craftseeker: settings page under Options > AddOns, and the minimap button
local _, CS = ...
local Options = CS:NewModule("Options")

local ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local function OpenBrowser()
    CS:GetModule("Browser"):Toggle()
end

function CS:OpenSettings()
    if Options.categoryID then Settings.OpenToCategory(Options.categoryID) end
end

local function AddCheckbox(category, key, name, tooltip, get, set)
    local setting = Settings.RegisterProxySetting(category, "Craftseeker_" .. key, Settings.VarType.Boolean, name, true, get, set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

function Options:BuildSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Craftseeker")
    local data = CS.data
    layout:AddInitializer(CreateSettingsButtonInitializer("", "Open Craftseeker", OpenBrowser,
        "Opens the reagent browser, as /cs and the minimap button do.", true))
    AddCheckbox(category, "minimap", "Minimap button", "Shows the Craftseeker button on the minimap.",
        function() return not data.minimap.hide end,
        function(value) CS:SetMinimapButton(value) end)
    AddCheckbox(category, "sources", "Track where reagents come from",
        "Remembers the vendors, creatures, nodes and fishing spots you get reagents and recipe items from, and counts looted corpses for drop rates.",
        function() return data.settings.sources end,
        function(value) data.settings.sources = value end)
    AddCheckbox(category, "share", "Share loot counts",
        "Trades loot counts with Craftseeker users in your guild, your group and your friends lists, so everyone's drop rates improve.",
        function() return data.settings.share end,
        function(value)
            data.settings.share = value
            if value then CS:GetModule("Share"):Hello() end
        end)
    Settings.RegisterAddOnCategory(category)
    self.categoryID = category:GetID()
end

-- Minimap button -----------------------------------------------------------------

function CS:SetMinimapButton(show)
    self.data.minimap.hide = not show
    local icon = LibStub("LibDBIcon-1.0")
    if show then icon:Show("Craftseeker") else icon:Hide("Craftseeker") end
end

function Options:BuildMinimapButton()
    local broker = LibStub("LibDataBroker-1.1"):NewDataObject("Craftseeker", {
        type = "launcher",
        text = "Craftseeker",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then CS:OpenSettings() else OpenBrowser() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Craftseeker")
            tooltip:AddLine("Click to open the reagent browser.", 1, 1, 1)
            tooltip:AddLine("Right-click for settings.", 0.7, 0.7, 0.7)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("Craftseeker", broker, CS.data.minimap)
end

function Options:OnEnable()
    self:BuildMinimapButton()
    self:BuildSettings()
end
