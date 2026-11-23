-- Reagent Scout: browser window (/rs, or Alt+Click an item), laid out like the profession window
local _, RS = ...
local Browser = RS:NewModule("Browser", "AceEvent-3.0", "AceBucket-3.0")

local HEADER_H, ROW_H, SPACER_H = 26, 24, 8
local LIST_W = 274
local SLOT = 44 -- one size for output, reagents and recipe item, like the profession window
local REAGENT_STEP, REAGENT_COL = 54, 250
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local MAX_REAGENTS = 8
local GREY, GOLD = "|cff9d9d9d", "|cffffd100"
local FACTION_NAME = { "Alliance", "Horde" }

local f, searchBox, title, summary, scrollBox, listEmpty
local detail -- right-hand panel widgets
local currentQuery, currentItem, selectedRecipe
local collapsed = {} -- [section title] = true, kept for the session
local Render, ShowDetail

local function ShowItemTooltip(self)
    if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    elseif self.spellID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end
end

local function LinkOrLookup(self)
    if IsShiftKeyDown() and self.itemID then
        local _, link = C_Item.GetItemInfo(self.itemID)
        if link then ChatFrameUtil.InsertLink(link) end
    elseif self.lookup then
        Browser:Show("item:" .. self.lookup)
    end
end

local function QualityColor(itemID)
    local quality = itemID and RS:ItemQuality(itemID)
    return quality and ITEM_QUALITY_COLORS[quality]
end

-- List ---------------------------------------------------------------------

local function OnRowClick(self)
    if self.recipeID and not IsShiftKeyDown() then
        selectedRecipe = self.recipeID
        scrollBox:ForEachFrame(function(frame)
            if frame.Selected then frame.Selected:SetShown(frame.recipeID ~= nil and frame.recipeID == selectedRecipe) end
        end)
        ShowDetail()
    else
        LinkOrLookup(self)
    end
end

-- Rows are pooled by the ScrollBox, so every field is reset on each init
local function InitRow(row, data)
    if not row.Label then
        row.Selected = row:CreateTexture(nil, "BACKGROUND")
        row.Selected:SetAtlas("Professions_Recipe_Active")
        row.Selected:SetAllPoints()
        row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.Highlight:SetAtlas("Professions_Recipe_Hover")
        row.Highlight:SetAllPoints()
        row.Highlight:SetAlpha(0.5)
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(20, 20)
        row.Icon:SetPoint("LEFT", 10, 0)
        row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        row.Right:SetPoint("RIGHT", -8, 0)
        row.Right:SetJustifyH("RIGHT")
        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        row.Label:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetWordWrap(false)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnEnter", ShowItemTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", OnRowClick)
    end
    row.itemID, row.lookup, row.recipeID, row.spellID = data.itemID, data.lookup, data.recipeID, data.spellID
    row.Label:SetText(data.left or "")
    row.Right:SetText(data.right or "")
    row.Label:ClearPoint("LEFT")
    if data.icon then
        row.Icon:SetTexture(data.icon)
        row.Icon:Show()
        row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    else
        row.Icon:Hide()
        row.Label:SetPoint("LEFT", 21, 0)
    end
    row.Selected:SetShown(data.recipeID ~= nil and data.recipeID == selectedRecipe)
    row.Highlight:SetShown(data.recipeID ~= nil or data.lookup ~= nil)
end

local function InitHeader(button, data)
    if not button.rsInit then
        button.rsInit = true
        button:SetTitleColor(false, NORMAL_FONT_COLOR)
        button:SetTitleColor(true, HIGHLIGHT_FONT_COLOR)
        button:SetScript("OnClick", function(self)
            collapsed[self.key] = not collapsed[self.key] or nil
            Render(true)
        end)
        button:SetScript("OnEnter", function(self) self:CheckHighlightTitle(true) end)
        button:SetScript("OnLeave", function(self) self:CheckHighlightTitle(false) end)
    end
    button.key = data.key
    button:SetHeaderText(data.text)
    button:GetCollapseButton():UpdateCollapsedState(collapsed[data.key])
end

-- Detail panel ---------------------------------------------------------------

local function ItemSlot(parent)
    local b = CreateFrame("ItemButton", nil, parent)
    b:SetSize(SLOT, SLOT)
    b:SetScript("OnEnter", ShowItemTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", LinkOrLookup)
    return b
end

local function FillSlot(slot, itemID, spellID)
    slot.itemID, slot.spellID, slot.lookup = itemID, spellID, itemID
    if itemID then
        slot:SetItemButtonTexture(C_Item.GetItemIconByID(itemID))
        slot:SetItemButtonQuality(RS:ItemQuality(itemID), itemID)
    else
        slot:SetItemButtonTexture(spellID and C_Spell.GetSpellTexture(spellID) or 134400)
        slot:SetItemButtonQuality(nil)
    end
    slot:Show()
end

local function Text(panel, font)
    local fs = panel:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    return fs
end

local function BuildDetail(panel)
    detail = {}
    detail.Background = panel:CreateTexture(nil, "BACKGROUND")
    detail.Background:SetAllPoints()
    local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
    border:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")

    detail.Output = ItemSlot(panel)
    detail.Output:SetPoint("TOPLEFT", 28, -26)
    detail.Name = Text(panel, "GameFontHighlightLarge2")
    detail.Name:SetPoint("TOPLEFT", detail.Output, "TOPRIGHT", 12, -2)
    detail.Name:SetPoint("RIGHT", -20, 0)
    detail.Name:SetWordWrap(false)
    detail.Sub = Text(panel, "GameFontHighlightMedium")
    detail.Sub:SetPoint("TOPLEFT", detail.Name, "BOTTOMLEFT", 0, -5)
    detail.Sub:SetPoint("RIGHT", -20, 0)

    detail.ReagentsLabel = Text(panel, "GameFontNormalMed2")
    detail.ReagentsLabel:SetPoint("TOPLEFT", 28, -96)
    detail.ReagentsLabel:SetText("Reagents:")
    detail.Reagents = {}
    for i = 1, MAX_REAGENTS do
        local slot = ItemSlot(panel)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        slot:SetPoint("TOPLEFT", 28 + col * REAGENT_COL, -118 - row * REAGENT_STEP)
        slot.Text = Text(panel, "GameFontHighlightMedium")
        slot.Text:SetPoint("LEFT", slot, "RIGHT", 10, 0)
        slot.Text:SetWidth(REAGENT_COL - SLOT - 20)
        slot.Text:SetMaxLines(2)
        detail.Reagents[i] = slot
    end

    detail.LearnLabel = Text(panel, "GameFontNormalMed2")
    detail.LearnLabel:SetText("How to learn it:")
    detail.Teach = ItemSlot(panel)
    detail.TeachText = Text(panel, "GameFontHighlightMedium")
    detail.TeachText:SetPoint("LEFT", detail.Teach, "RIGHT", 10, 0)
    detail.TeachText:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    detail.Learn = Text(panel, "GameFontHighlightMedium")
    detail.Learn:SetPoint("RIGHT", -20, 0)
    detail.Learn:SetSpacing(4)

    detail.SourcesLabel = Text(panel, "GameFontNormalMed2")
    detail.Sources = Text(panel, "GameFontHighlightMedium")
    detail.Sources:SetPoint("RIGHT", -20, 0)
    detail.Sources:SetSpacing(4)

    detail.Help = Text(panel, "GameFontHighlightMedium")
    detail.Help:SetPoint("TOPLEFT", 28, -28)
    detail.Help:SetPoint("RIGHT", -28, 0)
    detail.Help:SetSpacing(5)
end

-- Zone names from a flat area, faction[, level] list, keeping this character's faction only
local function AreaList(list, perEntry, withLevel)
    local mine = RS.PlayerFaction()
    local out, seen = {}, {}
    for i = 1, #list, perEntry do
        if RS.ForMe(list[i + 1], mine) then
            local area = list[i]
            local name = (area > 0 and C_Map.GetAreaInfo(area)) or "an unknown zone"
            if withLevel and list[i + 2] > 0 then name = name .. " (level " .. list[i + 2] .. ")" end
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return table.concat(out, ", ")
end

-- "Heading:" then one indented line per zone; long lists end in a count of what was left out
local function AddZoneGroups(lines, heading, groups, maxZones, maxNames)
    lines[#lines + 1] = heading
    for i = 1, math.min(#groups, maxZones) do
        local g = groups[i]
        local names = {}
        for j = 1, math.min(#g.names, maxNames) do names[j] = g.names[j] end
        local more = #g.names > maxNames and (GREY .. " +" .. (#g.names - maxNames) .. " more|r") or ""
        lines[#lines + 1] = "   " .. GOLD .. g.zone .. ":|r " .. table.concat(names, ", ") .. more
    end
    if #groups > maxZones then
        lines[#lines + 1] = "   " .. GREY .. "+" .. (#groups - maxZones) .. " more zones|r"
    end
end

local function LearnLines(recipeID, rec)
    local info = RS:GetLearnInfo(recipeID)
    if not info then return { GREY .. "Not recorded in the built-in data.|r" } end
    local lines, how = {}, info.how
    -- QuestieDB names the creatures, vendors and quests behind the recipe item
    local qs = info.teach > 0 and RS:GetQuestieSources(info.teach) or nil
    if info.skill > 0 then lines[#lines + 1] = ("Requires %s (%d)"):format(rec.p or "?", info.skill) end
    if how:find("a") then lines[#lines + 1] = "Learned automatically with the profession" end
    if how:find("t") then
        lines[#lines + 1] = "Trainer" .. (info.cost > 0 and ("  " .. RS.Money(info.cost)) or "")
    end
    if qs and #qs.vendors > 0 then
        AddZoneGroups(lines, "Sold by:", qs.vendors, 4, 3)
    elseif how:find("v") then
        local zones = AreaList(info.vendors, 2)
        if zones ~= "" or #info.vendors == 0 then lines[#lines + 1] = "Vendor" .. (zones ~= "" and (": " .. zones) or "") end
    end
    if qs and #qs.quests > 0 then
        for _, q in ipairs(qs.quests) do lines[#lines + 1] = "Quest: " .. q end
    elseif how:find("q") then
        local zones = AreaList(info.quests, 3, true)
        if zones ~= "" or #info.quests == 0 then lines[#lines + 1] = "Quest" .. (zones ~= "" and (": " .. zones) or "") end
    end
    local rates = info.teach > 0 and RS:GetDropRates(info.teach)
    if qs and #qs.drops > 0 then
        AddZoneGroups(lines, "Drops from:", qs.drops, 4, 4)
    elseif how:find("d") and not rates then
        lines[#lines + 1] = "Drops from creatures"
    end
    if rates then
        lines[#lines + 1] = "Drop rates seen by WoW Forever players:"
        for _, r in ipairs(rates) do
            lines[#lines + 1] = ("   %s  %s%.2f%%|r  %s(%d kills)|r"):format(r.name ~= "" and r.name or ("NPC " .. r.npc),
                GOLD, r.chance, GREY, r.kills)
        end
    end
    if qs and #qs.objects > 0 then
        AddZoneGroups(lines, "Found in:", qs.objects, 3, 3)
    elseif how:find("w") then
        lines[#lines + 1] = "Found in a world object"
    end
    if how:find("c") then lines[#lines + 1] = "Crafted by another profession" end
    if how == "" and not qs then lines[#lines + 1] = GREY .. "Source not recorded yet|r" end
    for i = 1, #info.rep, 2 do
        local fdata = C_Reputation.GetFactionDataByID(info.rep[i])
        local standing = _G["FACTION_STANDING_LABEL" .. info.rep[i + 1]] or info.rep[i + 1]
        lines[#lines + 1] = ("Requires %s with %s"):format(standing, fdata and fdata.name or ("faction " .. info.rep[i]))
    end
    if info.favor > 0 then lines[#lines + 1] = ("Costs %d Merchant's Favor"):format(info.favor) end
    if info.side > 0 then lines[#lines + 1] = FACTION_NAME[info.side] .. " only" end
    return lines, info
end

local function HideDetail()
    detail.Output:Hide()
    detail.Name:SetText("")
    detail.Sub:SetText("")
    detail.ReagentsLabel:Hide()
    for _, slot in ipairs(detail.Reagents) do slot:Hide(); slot.Text:SetText("") end
    detail.LearnLabel:Hide()
    detail.Teach:Hide()
    detail.TeachText:SetText("")
    detail.Learn:SetText("")
    detail.SourcesLabel:SetText("")
    detail.Sources:SetText("")
    detail.Help:SetText("")
end

function ShowDetail()
    HideDetail()
    local rec = selectedRecipe and RS.recipes[selectedRecipe]
    local atlas = rec and rec.p and ("Professions-Recipe-Background-" .. rec.p:gsub("%s", ""))
    if not (atlas and C_Texture.GetAtlasInfo(atlas)) then atlas = "Professions-Recipe-Background" end
    detail.Background:SetAtlas(atlas)
    if not rec then
        detail.Help:SetText(
            "Alt+Click any item, or search on the left.\n\n" ..
            "|cff40ff40Green|r  you know the recipe\n" ..
            "|cffffd100Yellow|r  one of your alts knows it\n" ..
            "|cff9d9d9dGrey|r  none of your characters know it yet\n\n" ..
            "Recipes only the other faction can learn are hidden.\n" ..
            "Opening a profession window marks what each character knows.")
        return
    end

    FillSlot(detail.Output, rec.o, rec.o == nil and selectedRecipe or nil)
    local color = QualityColor(rec.o)
    detail.Name:SetText((rec.n or "?") .. (rec.q and rec.q > 1 and (" x" .. rec.q) or ""))
    if color then detail.Name:SetTextColor(color.r, color.g, color.b) else detail.Name:SetTextColor(1, 1, 1) end
    local who, alt = RS:WhoKnows(selectedRecipe)
    detail.Sub:SetText((rec.p or "?") .. "   " .. (who == "me" and "|cff40ff40You know this|r"
        or who == "alt" and (GOLD .. "Known by " .. alt .. "|r") or (GREY .. "None of your characters know this|r")))

    detail.ReagentsLabel:Show()
    local count = math.min(#rec.r, MAX_REAGENTS)
    for i = 1, count do
        local id, qty = rec.r[i][1], rec.r[i][2]
        local slot = detail.Reagents[i]
        FillSlot(slot, id)
        local name = RS:ItemName(id) or ("item " .. id)
        slot.Text:SetText(qty .. " " .. (id == currentItem and (GOLD .. name .. "|r") or name))
    end

    local y = -118 - math.ceil(count / 2) * REAGENT_STEP - 8
    detail.LearnLabel:SetPoint("TOPLEFT", 28, y)
    detail.LearnLabel:Show()
    y = y - 24
    local lines, info = LearnLines(selectedRecipe, rec)
    if info and info.teach > 0 then
        FillSlot(detail.Teach, info.teach)
        detail.Teach:SetPoint("TOPLEFT", 28, y)
        local name = RS:ItemName(info.teach) or "Recipe item"
        local tq = QualityColor(info.teach)
        if tq then name = tq.hex .. name .. "|r" end
        detail.TeachText:SetText(name .. (info.bound and (GREY .. "  (binds when picked up)|r") or ""))
        y = y - SLOT - 10
    end
    detail.Learn:SetPoint("TOPLEFT", 28, y)
    detail.Learn:SetText(table.concat(lines, "\n"))
    y = y - detail.Learn:GetStringHeight() - 20

    -- the looked-up reagent: vendors from QuestieDB, then what this account has seen
    local out = {}
    local qs = currentItem and RS:GetQuestieSources(currentItem)
    if qs and #qs.vendors > 0 then AddZoneGroups(out, "Sold by:", qs.vendors, 3, 3) end
    for _, l in ipairs(currentItem and RS:SourceLines(currentItem, 4) or {}) do
        out[#out + 1] = GREY .. l[1] .. "|r  " .. l[2]
    end
    if #out > 0 then
        detail.SourcesLabel:SetPoint("TOPLEFT", 28, y)
        detail.SourcesLabel:SetText("Where to get " .. (RS:ItemName(currentItem) or "it") .. ":")
        detail.Sources:SetPoint("TOPLEFT", 28, y - 22)
        detail.Sources:SetText(table.concat(out, "\n"))
    end
end

-- Frame --------------------------------------------------------------------

local function Build()
    f = CreateFrame("Frame", "ReagentScoutBrowser", UIParent, "PortraitFrameTemplate")
    f:SetSize(830, 620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetTitle("Reagent Scout")
    f:SetPortraitToAsset(DEFAULT_ICON)
    f:Hide()
    tinsert(UISpecialFrames, "ReagentScoutBrowser")

    title = Text(f, "GameFontHighlightLarge2")
    title:SetPoint("TOPLEFT", 66, -30)
    title:SetPoint("RIGHT", -24, 0)
    title:SetWordWrap(false)
    summary = Text(f, "GameFontHighlight")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    summary:SetPoint("RIGHT", -24, 0)
    summary:SetTextColor(0.7, 0.7, 0.7)

    local list = CreateFrame("Frame", nil, f)
    list:SetWidth(LIST_W)
    list:SetPoint("TOPLEFT", 5, -72)
    list:SetPoint("BOTTOMLEFT", 5, 5)
    local listBg = list:CreateTexture(nil, "BACKGROUND")
    listBg:SetAtlas("Professions-background-summarylist")
    listBg:SetAllPoints()
    local listBorder = CreateFrame("Frame", nil, list, "NineSlicePanelTemplate")
    listBorder:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(listBorder, "InsetFrameTemplate")

    searchBox = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", 13, -8)
    searchBox:SetPoint("RIGHT", -10, 0)
    searchBox.Instructions:SetText("Search reagents")
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Browser:Show(self:GetText())
    end)
    -- live search; a short delay keeps each keystroke from rebuilding the list
    local pending
    searchBox:HookScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if pending then pending:Cancel() end
        pending = C_Timer.NewTimer(0.3, function()
            pending = nil
            local text = strtrim(self:GetText())
            if text == "" or #text >= 2 then Browser:Show(text, true) end
        end)
    end)
    Browser.searchBox = searchBox

    scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 8, -35)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 5)
    local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(function(factory, data)
        if data.header then
            factory("ListHeaderVisualTemplate", InitHeader)
        else
            factory("Button", InitRow)
        end
    end)
    view:SetElementExtentCalculator(function(_, data)
        if data.header then return HEADER_H end
        return data.spacer and SPACER_H or ROW_H
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    listEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listEmpty:SetPoint("TOP", 0, -60)
    listEmpty:SetWidth(LIST_W - 40)

    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMRIGHT", -5, 5)
    BuildDetail(panel)
end

local function SetHeading(icon, text, sub, itemID)
    f:SetPortraitToAsset(icon or DEFAULT_ICON)
    title:SetText(text)
    local color = QualityColor(itemID)
    if color then title:SetTextColor(color.r, color.g, color.b) else title:SetTextColor(NORMAL_FONT_COLOR:GetRGB()) end
    summary:SetText(sub or "")
end

-- Views return the list elements, or nil plus a message for the empty list
local function WelcomeView()
    SetHeading(nil, "Look up a reagent", ("%d recipes across every profession"):format(RS:CountRecipes()))
    return nil, ""
end

local function PickerView(hits, query)
    SetHeading(nil, "Search", #hits .. " reagent" .. (#hits == 1 and "" or "s") .. " match \"" .. query .. "\"")
    if #hits == 0 then return nil, "No reagent matches that." end
    local list = {}
    for _, itemID in ipairs(hits) do
        local n = #RS:GetUses(itemID)
        list[#list + 1] = {
            itemID = itemID, lookup = itemID,
            icon = C_Item.GetItemIconByID(itemID),
            left = RS:ItemName(itemID) or ("item " .. itemID),
            right = n .. " recipe" .. (n == 1 and "" or "s"),
        }
    end
    return list
end

local function ItemView(itemID)
    if not C_Item.GetItemNameByID(itemID) then C_Item.RequestLoadItemDataByID(itemID) end
    currentItem = itemID
    local list, first = {}, nil
    local uses = RS:GetUses(itemID)
    local nProfs = 0
    if uses then
        -- one section per profession; GetUses already put known recipes first within each
        local byProf, profs = {}, {}
        for _, recipeID in ipairs(uses) do
            local p = RS.recipes[recipeID].p or "?"
            if not byProf[p] then
                byProf[p] = {}
                profs[#profs + 1] = p
            end
            table.insert(byProf[p], recipeID)
        end
        table.sort(profs)
        nProfs = #profs
        for _, p in ipairs(profs) do
            local ids = byProf[p]
            list[#list + 1] = { header = true, key = p, text = p .. "  " .. GREY .. #ids .. "|r" }
            for _, recipeID in ipairs(ids) do
                first = first or recipeID
                if not collapsed[p] then
                    local rec = RS.recipes[recipeID]
                    local _, text = RS:RecipeLine(recipeID, itemID)
                    local info = RS:GetLearnInfo(recipeID)
                    list[#list + 1] = {
                        recipeID = recipeID, itemID = rec.o, spellID = rec.o == nil and recipeID or nil,
                        left = text,
                        right = info and info.skill > 0 and tostring(info.skill) or nil,
                    }
                end
            end
        end
    end
    local keep = false
    for _, id in ipairs(uses or {}) do if id == selectedRecipe then keep = true end end
    if not keep then selectedRecipe = first end

    local n = uses and #uses or 0
    SetHeading(C_Item.GetItemIconByID(itemID), RS:ItemName(itemID) or ("item " .. itemID),
        n > 0 and ("Used in %d recipe%s across %d profession%s"):format(n, n == 1 and "" or "s", nProfs, nProfs == 1 and "" or "s")
            or "Not used in any recipe you can learn", itemID)
    if #list == 0 then return nil, "No recipe uses this item." end
    return list
end

local function BuildView(query)
    currentItem = nil
    if query == "" then return WelcomeView() end
    local itemID = RS.ItemIDFromText(query)
    if itemID then return ItemView(itemID) end
    local hits = RS:SearchReagentsByName(query)
    if #hits == 1 then return ItemView(hits[1]) end
    return PickerView(hits, query)
end

function Render(keepScroll)
    local list, message = BuildView(currentQuery)
    if not currentItem then selectedRecipe = nil end
    scrollBox:SetDataProvider(CreateDataProvider(list or {}),
        keepScroll and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition)
    listEmpty:SetText(message or "")
    ShowDetail()
end

-- fromTyping: the search box already holds the text, so don't overwrite it mid-edit
function Browser:Show(query, fromTyping)
    if not f then Build() end
    f:Show()
    currentQuery = strtrim(query or "")
    if not fromTyping then searchBox:SetText(currentQuery) end
    Render(false)
end

function Browser:Toggle()
    if f and f:IsShown() then f:Hide() else self:Show("") end
end

-- Names and icons of uncached items arrive in bursts
function Browser:ItemInfoReceived()
    if f and f:IsShown() and currentQuery ~= "" then Render(true) end
end

function Browser:OnEnable()
    self:RegisterBucketEvent("GET_ITEM_INFO_RECEIVED", 0.3, "ItemInfoReceived")
    -- Alt+Click any item (bags, bank, loot...) to look it up; Shift+Click drops it into a focused search box
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not link or RS.IsSecret(link) or not link:find("item:") then return end
        if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
            self:Show(link)
        elseif IsShiftKeyDown() and searchBox and searchBox:HasFocus() then
            searchBox:ClearFocus()
            self:Show(link)
        end
    end)
end
