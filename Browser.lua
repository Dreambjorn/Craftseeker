-- Reagent Scout: browser window (/rs, or Alt+Click an item), laid out like the profession window
local _, RS = ...
local Browser = RS:NewModule("Browser", "AceEvent-3.0", "AceBucket-3.0")

local HEADER_H, ROW_H, SPACER_H = 26, 24, 8
local LIST_W = 274
local SLOT = 44 -- one size for output, reagents and recipe item, like the profession window
local REAGENT_STEP, REAGENT_COL = 54, 250
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
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
-- The right pane scrolls, so every source can be listed in full: drops, vendors and trainers are tables.

local PAD, DETAIL_W, ROW = 28, 484, 20
local pool = { text = {}, rows = {}, slots = {} } -- widgets reused across selections
local used = { text = 0, rows = 0, slots = 0 }
local content, cursor

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

local function Text(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Flow layout: each call places a widget at the cursor and moves the cursor down
local function NextText(font)
    used.text = used.text + 1
    local fs = pool.text[used.text]
    if not fs then
        fs = Text(content, font)
        pool.text[used.text] = fs
    end
    fs:SetFontObject(font)
    fs:ClearAllPoints()
    fs:SetWidth(DETAIL_W)
    fs:SetWordWrap(true)
    fs:Show()
    return fs
end

local function AddText(text, font, gap)
    local fs = NextText(font or "GameFontHighlightMedium")
    fs:SetPoint("TOPLEFT", 0, cursor)
    fs:SetText(text)
    cursor = cursor - fs:GetStringHeight() - (gap or 4)
    return fs
end

local function AddHeading(text)
    cursor = cursor - 6
    AddText(text, "GameFontNormalMed2", 6)
end

local function RowTooltip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tip[1], 1, 1, 1)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

-- One table row: columns are { text, width, justify }; tip is shown on hover
local function AddRow(columns, tip, font)
    used.rows = used.rows + 1
    local row = pool.rows[used.rows]
    if not row then
        row = CreateFrame("Button", nil, content)
        row:SetSize(DETAIL_W, ROW)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAtlas("Professions_Recipe_Hover")
        hl:SetAllPoints()
        hl:SetAlpha(0.4)
        row.cols = {}
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        pool.rows[used.rows] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, cursor)
    row.tip = tip
    local x = 0
    for i, col in ipairs(columns) do
        local fs = row.cols[i]
        if not fs then
            fs = Text(row, font or "GameFontHighlightMedium")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        fs:SetFontObject(font or "GameFontHighlightMedium")
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(col[2] - 6)
        fs:SetJustifyH(col[3] or "LEFT")
        fs:SetText(col[1] or "")
        fs:Show()
        x = x + col[2]
    end
    for i = #columns + 1, #row.cols do row.cols[i]:Hide() end
    row:Show()
    cursor = cursor - ROW
end

-- Table columns are as wide as their longest cell, measured here; the first column takes the room left over
local measure
local function TextWidth(text, font)
    measure:SetFontObject(font)
    measure:SetText(text)
    return measure:GetUnboundedStringWidth()
end

-- Too wide in total: the widest columns share what the narrow ones leave and cut their text (the tooltip has it all)
local function ColumnWidths(need)
    local n, total, widths = #need, 0, {}
    for i = 1, n do total = total + need[i] end
    if total <= DETAIL_W then
        for i = 1, n do widths[i] = need[i] end
        widths[1] = widths[1] + DETAIL_W - total
        return widths
    end
    local order, room = {}, DETAIL_W
    for i = 1, n do order[i] = i end
    table.sort(order, function(a, b) return need[a] < need[b] end)
    for k, i in ipairs(order) do
        widths[i] = math.floor(math.min(need[i], room / (n - k + 1)))
        room = room - widths[i]
    end
    return widths
end

-- header: column titles or nil; rows: { cells = { text, ... }, tip = { line, ... } }; justify: per column
local function AddTable(header, rows, justify)
    local need = {}
    local function Measure(cells, font)
        for i = 1, #cells do need[i] = math.max(need[i] or 0, math.ceil(TextWidth(cells[i], font)) + 13) end
    end
    if header then Measure(header, "GameFontDisable") end
    for _, r in ipairs(rows) do Measure(r.cells, "GameFontHighlightMedium") end
    measure:SetText("") -- the alpha alone does not hide it
    local widths = ColumnWidths(need)
    local function Columns(cells)
        local cols = {}
        for i = 1, #widths do cols[i] = { cells[i] or "", widths[i], justify and justify[i] } end
        return cols
    end
    if header then AddRow(Columns(header), nil, "GameFontDisable") end
    for _, r in ipairs(rows) do AddRow(Columns(r.cells), r.tip) end
end

local function AddSlot(itemID, spellID, label)
    used.slots = used.slots + 1
    local slot = pool.slots[used.slots]
    if not slot then
        slot = ItemSlot(content)
        slot.Text = Text(content, "GameFontHighlightMedium")
        slot.Text:SetPoint("LEFT", slot, "RIGHT", 10, 0)
        slot.Text:SetMaxLines(2)
        pool.slots[used.slots] = slot
    end
    FillSlot(slot, itemID, spellID)
    slot.Text:SetText(label or "")
    slot.Text:Show()
    return slot
end

local function Money(copper)
    return copper and copper > 0 and RS.Money(copper) or ""
end

local function ZoneCell(zones)
    if not zones or #zones == 0 then return GREY .. "unknown|r" end
    return zones[1] .. (#zones > 1 and (GREY .. " +" .. (#zones - 1) .. "|r") or "")
end

-- Every creature that drops an item: QuestieDB's list joined with measured rates, best rate first, then
-- this zone's creatures, then by name. Nothing is cut; the pane scrolls.
local function AddDrops(itemID, qs)
    local byNpc, list = {}, {}
    for _, e in ipairs(qs and qs.drops or {}) do
        local entry = { npc = e.npc, name = e.name, level = e.level, rank = e.rank, zones = e.zones }
        byNpc[e.npc] = entry
        list[#list + 1] = entry
    end
    for _, r in ipairs(RS:GetDropRates(itemID) or {}) do
        local entry = byNpc[r.npc]
        if not entry then
            entry = { npc = r.npc, name = r.name, zones = {} }
            byNpc[r.npc] = entry
            list[#list + 1] = entry
        end
        entry.chance, entry.kills, entry.own = r.chance, r.kills, r.own
    end
    if #list == 0 then return false end
    -- QuestieDB has no spawns for many Forever creatures; the built-in places fill in
    for _, e in ipairs(list) do
        if #e.zones == 0 then e.zones = RS:GetPlaces(e.npc) end
    end
    local here = GetRealZoneText()
    table.sort(list, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        local ah, bh = a.zones[1] == here, b.zones[1] == here
        if ah ~= bh then return ah end
        return a.name < b.name
    end)
    AddHeading(("Recipe dropped by %d creature%s"):format(#list, #list == 1 and "" or "s"))
    local rows = {}
    for _, e in ipairs(list) do
        local name = e.rank and (e.name .. GOLD .. " " .. e.rank .. "|r") or e.name
        local chance = e.chance and (("%s%.2f%%|r %s(%d)|r"):format(GOLD, e.chance, GREY, e.kills)) or (GREY .. "no data|r")
        local tip = { e.name }
        if e.rank then tip[#tip + 1] = e.rank end
        if e.level then tip[#tip + 1] = "Level " .. e.level end
        tip[#tip + 1] = #e.zones > 0 and ("Zones: " .. table.concat(e.zones, ", ")) or "Zone not recorded"
        tip[#tip + 1] = e.chance and (("%.2f%% over %d corpses looted by WoW Forever players"):format(e.chance, e.kills))
            or "No measured drop rate yet"
        if e.own and e.own > 0 then tip[#tip + 1] = ("%d of those corpses are your own"):format(e.own) end
        rows[#rows + 1] = { cells = { name, e.level and tostring(e.level) or "", ZoneCell(e.zones), chance }, tip = tip }
    end
    AddTable({ "Creature", "Level", "Zone", "Chance" }, rows, { nil, nil, nil, "RIGHT" })
    return true
end

-- Vendors of an item, this faction only: what players saw (with price) joined with QuestieDB's list
local function AddVendors(itemID, qs, heading)
    local byNpc, list = {}, {}
    for _, v in ipairs(RS:GetVendors(itemID) or {}) do
        local price = v.copper and v.copper > 0 and (Money(v.copper) .. (v.stack and v.stack > 1 and (GREY .. " /" .. v.stack .. "|r") or "")) or ""
        local entry = { name = v.name, zones = v.zone and { v.zone } or {}, price = price }
        byNpc[v.npc] = entry
        list[#list + 1] = entry
    end
    for _, e in ipairs(qs and qs.vendors or {}) do
        local entry = byNpc[e.npc]
        if entry then
            if #entry.zones == 0 then entry.zones = e.zones end
        else
            list[#list + 1] = { name = e.name, zones = e.zones, price = "" }
        end
    end
    if #list == 0 then return false end
    table.sort(list, function(a, b) return a.name < b.name end)
    AddHeading(heading or ("Recipe sold by %d vendor%s"):format(#list, #list == 1 and "" or "s"))
    local rows = {}
    for _, v in ipairs(list) do
        rows[#rows + 1] = { cells = { v.name, ZoneCell(v.zones), v.price },
            tip = { v.name, #v.zones > 0 and ("Zones: " .. table.concat(v.zones, ", ")) or "Zone not recorded" } }
    end
    AddTable(nil, rows, { nil, nil, "RIGHT" })
    return true
end

-- Quests that teach a recipe or reward its recipe item: name, who gives it and where
local function AddQuests(recipeID, qs)
    local list, seen = {}, {}
    for _, q in ipairs(RS:GetRecipeQuests(recipeID) or {}) do
        list[#list + 1] = q
        seen[q.name] = true
    end
    for _, q in ipairs(qs and qs.quests or {}) do
        if not seen[q.name] then list[#list + 1] = q end
    end
    if #list == 0 then return false end
    AddHeading(#list == 1 and "Quest" or ("%d quests"):format(#list))
    local rows = {}
    for _, q in ipairs(list) do
        local name = q.name .. (q.level and (GREY .. " (" .. q.level .. ")|r") or "")
        rows[#rows + 1] = { cells = { name, q.giver or (GREY .. "unknown|r"), q.zone or (GREY .. "unknown|r") },
            tip = { q.name, q.giver and ("Given by " .. q.giver) or "Giver not recorded", q.zone and ("In " .. q.zone) or nil,
                    q.level and ("Level " .. q.level) or nil } }
    end
    AddTable({ "Quest", "Given by", "Zone" }, rows)
    return true
end

local function AddTrainers(recipeID)
    local list = RS:GetTrainers(recipeID)
    if not list then return false end
    table.sort(list, function(a, b) return (a.zone or "~") < (b.zone or "~") end)
    AddHeading(("Taught by %d trainer%s"):format(#list, #list == 1 and "" or "s"))
    local rows = {}
    for _, t in ipairs(list) do
        rows[#rows + 1] = { cells = { t.name, t.zone or (GREY .. "unknown|r"), Money(t.copper) }, tip = { t.name, t.zone or "Zone not recorded" } }
    end
    AddTable(nil, rows, { nil, nil, "RIGHT" })
    return true
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

local function AddLearn(recipeID, rec)
    AddHeading("How to learn it:")
    local info = RS:GetLearnInfo(recipeID)
    if not info then
        AddText(GREY .. "Not recorded in the built-in data.|r")
        return
    end
    local how = info.how
    if info.teach > 0 then
        local name = RS:ItemName(info.teach) or "Recipe item"
        local tq = QualityColor(info.teach)
        if tq then name = tq.hex .. name .. "|r" end
        local slot = AddSlot(info.teach, nil, name .. (info.bound and (GREY .. "  (binds when picked up)|r") or ""))
        slot:SetPoint("TOPLEFT", 0, cursor)
        slot.Text:SetWidth(DETAIL_W - SLOT - 20)
        cursor = cursor - SLOT - 8
    end
    if info.skill > 0 then AddText(("Requires %s (%d)"):format(rec.p or "?", info.skill)) end
    for i = 1, #info.rep, 2 do
        local fdata = C_Reputation.GetFactionDataByID(info.rep[i])
        local standing = _G["FACTION_STANDING_LABEL" .. info.rep[i + 1]] or info.rep[i + 1]
        AddText(("Requires %s with %s"):format(standing, fdata and fdata.name or ("faction " .. info.rep[i])))
    end
    if info.favor > 0 then AddText(("Costs %d Merchant's Favor"):format(info.favor)) end
    if info.side > 0 then AddText(FACTION_NAME[info.side] .. " only") end
    if how:find("a") then AddText("Learned automatically with the profession") end

    local qs = info.teach > 0 and RS:GetQuestieSources(info.teach) or nil
    local shown = false
    if AddTrainers(recipeID) then
        shown = true
    elseif how:find("t") then
        AddText("Trainer" .. (info.cost > 0 and ("  " .. Money(info.cost)) or ""))
        shown = true
    end
    if info.teach > 0 and AddVendors(info.teach, qs) then
        shown = true
    elseif how:find("v") then
        local zones = AreaList(info.vendors, 2)
        if zones ~= "" then
            AddText("Vendor: " .. zones)
        else
            AddText("Sold only to the opposite faction")
        end
        shown = true
    end
    if AddQuests(recipeID, qs) then
        shown = true
    elseif how:find("q") then
        local zones = AreaList(info.quests, 3, true)
        AddText(zones ~= "" and ("Quest in " .. zones) or "Quest for the opposite faction only")
        shown = true
    end
    if info.teach > 0 and AddDrops(info.teach, qs) then
        shown = true
    elseif how:find("d") then
        AddText("Drops from creatures (none recorded yet)")
        shown = true
    end
    if qs and #qs.objects > 0 then
        AddHeading("Found in")
        local rows = {}
        for _, o in ipairs(qs.objects) do
            rows[#rows + 1] = { cells = { o.name, ZoneCell(o.zones) }, tip = { o.name, "Zones: " .. table.concat(o.zones, ", ") } }
        end
        AddTable(nil, rows)
        shown = true
    elseif how:find("w") then
        AddText("Found in a world object")
        shown = true
    end
    if how:find("c") then
        AddText("Crafted by another profession")
        shown = true
    end
    if not shown and not how:find("a") then
        AddText(GREY .. (info.teach > 0 and "Where the recipe item comes from isn't recorded yet"
            or "No recipe item teaches it, so most likely a trainer; none recorded yet") .. "|r")
    end
end

local function BuildDetail(panel)
    detail = {}
    detail.Background = panel:CreateTexture(nil, "BACKGROUND")
    detail.Background:SetAllPoints()
    local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
    border:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", PAD, -20)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(DETAIL_W, 1)
    measure = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    measure:SetPoint("TOPLEFT")
    measure:SetAlpha(0)
    scroll:SetScrollChild(content)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    detail.scroll = scroll

    detail.Output = ItemSlot(content)
    detail.Output:SetPoint("TOPLEFT", 0, -6)
    detail.Name = Text(content, "GameFontHighlightLarge2")
    detail.Name:SetPoint("TOPLEFT", detail.Output, "TOPRIGHT", 12, -2)
    detail.Name:SetWidth(DETAIL_W - SLOT - 12)
    detail.Name:SetWordWrap(false)
    detail.Sub = Text(content, "GameFontHighlightMedium")
    detail.Sub:SetPoint("TOPLEFT", detail.Name, "BOTTOMLEFT", 0, -5)
    detail.Sub:SetWidth(DETAIL_W - SLOT - 12)
end

local function ResetDetail()
    for kind, list in pairs(pool) do
        for _, w in ipairs(list) do
            w:Hide()
            if w.Text then w.Text:Hide() end
        end
        used[kind] = 0
    end
    detail.Output:Hide()
    detail.Name:SetText("")
    detail.Sub:SetText("")
end

function ShowDetail()
    ResetDetail()
    local rec = selectedRecipe and RS.recipes[selectedRecipe]
    local atlas = rec and rec.p and ("Professions-Recipe-Background-" .. rec.p:gsub("%s", ""))
    if not (atlas and C_Texture.GetAtlasInfo(atlas)) then atlas = "Professions-Recipe-Background" end
    detail.Background:SetAtlas(atlas)
    detail.scroll:SetVerticalScroll(0)
    cursor = -8
    if not rec then
        AddText(
            "Alt+Click any item, or search on the left.\n\n" ..
            "|cff40ff40Green|r  you know the recipe\n" ..
            "|cffffd100Yellow|r  one of your alts knows it\n" ..
            "|cff9d9d9dGrey|r  none of your characters know it yet\n\n" ..
            "Recipes only the opposite faction can learn are hidden.\n" ..
            "Opening a profession window marks what each character knows.")
        content:SetHeight(-cursor)
        return
    end

    FillSlot(detail.Output, rec.o, rec.o == nil and selectedRecipe or nil)
    local color = QualityColor(rec.o)
    detail.Name:SetText((rec.n or "?") .. (rec.q and rec.q > 1 and (" x" .. rec.q) or ""))
    if color then detail.Name:SetTextColor(color.r, color.g, color.b) else detail.Name:SetTextColor(1, 1, 1) end
    local who, alt = RS:WhoKnows(selectedRecipe)
    detail.Sub:SetText((rec.p or "?") .. "   " .. (who == "me" and "|cff40ff40You know this|r"
        or who == "alt" and (GOLD .. "Known by " .. alt .. "|r") or (GREY .. "None of your characters know this|r")))
    cursor = -6 - SLOT - 14

    AddHeading("Reagents:")
    for i, r in ipairs(rec.r) do
        local id, qty = r[1], r[2]
        local name = RS:ItemName(id) or ("item " .. id)
        local slot = AddSlot(id, nil, qty .. " " .. (id == currentItem and (GOLD .. name .. "|r") or name))
        local col = (i - 1) % 2
        slot:SetPoint("TOPLEFT", col * REAGENT_COL, cursor)
        slot.Text:SetWidth(REAGENT_COL - SLOT - 20)
        if col == 1 or i == #rec.r then cursor = cursor - REAGENT_STEP end
    end

    AddLearn(selectedRecipe, rec)

    -- the looked-up reagent: its vendors, then what this account has seen
    if currentItem then
        local name = RS:ItemName(currentItem) or "it"
        AddVendors(currentItem, RS:GetQuestieSources(currentItem), "Where to buy " .. name)
        local made = {}
        for _, id in ipairs(RS.madeBy[currentItem] or {}) do
            local r = RS.recipes[id]
            if r and RS:IsObtainable(id) then
                made[#made + 1] = { cells = { r.n or "?", r.p or "?" }, tip = { r.n or "?", (r.p or "?") .. " recipe" } }
            end
        end
        if #made > 0 then
            AddHeading("Made with")
            AddTable(nil, made, { nil, "RIGHT" })
        end
        local seen = {}
        for _, l in ipairs(RS:SourceLines(currentItem, 50)) do
            seen[#seen + 1] = { cells = { l[2], GREY .. l[1] .. "|r" }, tip = { l[2] } }
        end
        if #seen > 0 then
            AddHeading("Where you found " .. name)
            AddTable(nil, seen, { nil, "RIGHT" })
        end
    end
    content:SetHeight(-cursor + 12)
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
                    list[#list + 1] = {
                        recipeID = recipeID, itemID = rec.o, spellID = rec.o == nil and recipeID or nil,
                        left = text,
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
            or (RS.usedIn[itemID] and "Only used in recipes the opposite faction learns" or "Not used in any recipe"), itemID)
    if #list == 0 then
        return nil, RS.usedIn[itemID] and "Only used in recipes the opposite faction learns." or "No recipe uses this item."
    end
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
    if not fromTyping then
        -- show the item's name rather than item:123 or a raw link
        local itemID = RS.ItemIDFromText(currentQuery)
        searchBox:SetText(itemID and RS:ItemName(itemID) or currentQuery)
    end
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
