-- Craftseeker: settings page under Options > AddOns, and the minimap button
local _, CS = ...
local Options = CS:NewModule("Options", "AceEvent-3.0")

local ICON = "Interface\\Icons\\INV_Misc_Bag_Hearthstone"

local function OpenBrowser()
    CS:GetModule("Browser"):Toggle()
end

function CS:OpenSettings()
    if Options.categoryID then Settings.OpenToCategory(Options.categoryID) end
end

local function AddCheckbox(category, key, name, tooltip, get, set, default)
    local setting = Settings.RegisterProxySetting(category, "Craftseeker_" .. key, Settings.VarType.Boolean, name,
        default ~= false, get, set)
    Settings.CreateCheckbox(category, setting, tooltip)
end

function Options:BuildSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Craftseeker")
    local data = CS.data
    layout:AddInitializer(CreateSettingsButtonInitializer("", "Open Craftseeker", OpenBrowser,
        "Opens the Craftseeker window, as /cs and the minimap button do.", true))
    AddCheckbox(category, "minimap", "Minimap button", "Shows the Craftseeker button on the minimap.",
        function() return not data.minimap.hide end,
        function(value) CS:SetMinimapButton(value) end)
    AddCheckbox(category, "tooltip", "Reagent line in tooltips",
        "Adds how many recipes use a crafting reagent to its item tooltip.",
        function() return data.settings.tooltip end,
        function(value) data.settings.tooltip = value end)
    AddCheckbox(category, "sources", "Track reagent sources",
        "Remembers the vendors, creatures, nodes and fishing spots you get reagents and recipe items from, and counts looted corpses for drop rates.",
        function() return data.settings.sources end,
        function(value) data.settings.sources = value end)
    AddCheckbox(category, "share", "Share loot counts",
        "Trades loot counts with every Craftseeker user online, through a hidden channel, your guild, your group and your friends lists, so everyone's drop rates improve.",
        function() return data.settings.share end,
        function(value)
            data.settings.share = value
            CS:GetModule("Share"):Apply()
        end)
    AddCheckbox(category, "dt", "Read Drop Tables counts",
        "Asks Drop Tables users, through its hidden channel, about the creatures you target that drop reagents or recipe items, and adds their loot counts to the drop rates.",
        function() return data.settings.dt end,
        function(value)
            data.settings.dt = value
            CS:GetModule("Bridges"):Apply()
        end)
    AddCheckbox(category, "fd", "Read Forever Drops counts",
        "Asks Forever Drops users who announce themselves in your guild, your group or its hidden channel for their loot counts, and adds them to the drop rates.",
        function() return data.settings.fd end,
        function(value)
            data.settings.fd = value
            CS:GetModule("Bridges"):Apply()
        end)
    AddCheckbox(category, "opposite", "Show opposite faction",
        "Also lists recipes only the opposite faction can learn. The factions can't trade, so they are hidden unless you tick this.",
        function() return data.settings.opposite end,
        function(value)
            data.settings.opposite = value
            self:SendMessage("CRAFTSEEKER_FILTER")
        end, false)
    AddCheckbox(category, "debug", "Show debug messages",
        "Prints what sharing does (channel test, data received and sent, failed whispers) and names the addon behind the game's red \"doing that too fast\" errors.",
        function() return data.settings.debug end,
        function(value) data.settings.debug = value end, false)
    -- a page to leave out professions none of the characters will learn
    local sub = Settings.RegisterVerticalLayoutSubcategory(category, "Professions and classes")
    local profs, seen = {}, {}
    for _, rec in pairs(CS.recipes) do
        if rec.p and not seen[rec.p] then
            seen[rec.p] = true
            profs[#profs + 1] = rec.p
        end
    end
    table.sort(profs)
    for _, p in ipairs(profs) do
        AddCheckbox(sub, "show_" .. (p:gsub("%W", "")), p, "Lists " .. p .. " recipes or class spells. Untick it to hide them everywhere.",
            function() return not data.settings.hidden[p] end,
            function(value)
                data.settings.hidden[p] = not value or nil
                self:SendMessage("CRAFTSEEKER_FILTER")
            end)
    end
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
            tooltip:AddLine("|cffff8c33Craftseeker|r")
            tooltip:AddLine("Click to open Craftseeker.", 1, 1, 1)
            tooltip:AddLine("Right-click for settings.", 0.7, 0.7, 0.7)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register("Craftseeker", broker, CS.data.minimap)
end

function Options:OnEnable()
    self:BuildMinimapButton()
    self:BuildSettings()
end
