-- Craftseeker: browser window (/cs, or Alt+Click an item), laid out like the profession window
local _, CS = ...
local Browser = CS:NewModule("Browser", "AceEvent-3.0", "AceBucket-3.0")

local HEADER_H, ROW_H, SPACER_H = 25, 26, 12 -- row pitch and section gap as Forever's profession window shows them
local DIVIDER_H = 30
local LIST_W = 274
local SLOT = 44 -- one size for output, reagents and recipe item, like the profession window
local REAGENT_STEP, REAGENT_COL = 54, 250
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_Hearthstone"
local GREY, GOLD, RED = "|cff9d9d9d", "|cffffd100", "|cffff4040"
local FACTION_NAME = { "Alliance", "Horde" }

local f, searchBox, title, summary, scrollBox, listEmpty
local detail -- right-hand panel widgets
local currentQuery, currentItem, selectedRecipe
local collapsed = {} -- [section title] = true, kept for the session
local expanded = {}  -- [table] = true: shown in full, until another recipe is picked
local madeView       -- the list shows the recipes that make currentItem, not those that use it
local picking        -- search results with recipes in them: the first one is shown on the right
local AddSkill
local TABLE_ROWS = 10
local Render, ShowDetail, DrawDetail
local FILTERS = { { "mine", "My professions only" }, { "skillUp", "Has skill up" }, { "unknown", "Not known yet" },
    { "materials", "Have materials" } }
local FILTERED = "No recipe matches the filters."
local SKILL_ORDER = { orange = 1, yellow = 2, green = 3, grey = 4, none = 5, learn = 6 }
local FAVORITES = "Favorites" -- the first section, like the profession window's

local function ShowItemTooltip(self)
    if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    elseif self.spellID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    else
        return
    end
    if self.recipeID then
        -- a blue recipe name: which alts know it; a faction emblem: only the opposite faction learns it
        local alts = CS:AltsKnowing(self.recipeID)
        if #alts > 0 then GameTooltip:AddLine("Known by " .. table.concat(alts, ", "), 0.4, 0.73, 1) end
        if CS:WhoKnows(self.recipeID) ~= "me" and not CS:IsObtainable(self.recipeID) then
            GameTooltip:AddLine("Only the opposite faction can learn this", 1, 0.25, 0.25)
        end
        if not CS:IsProven(self.recipeID) then
            GameTooltip:AddLine("Not seen on WoW: Forever yet; it may not be in the game", 0.6, 0.6, 0.6, true)
        end
    elseif self.itemID then
        local have, _, bank = CS:ItemCounts(self.itemID)
        if bank > 0 then
            local bags = have - bank
            GameTooltip:AddLine(bags > 0 and ("%d in your bags, %d in your bank"):format(bags, bank)
                or ("%d in your bank"):format(bank), 0.8, 0.8, 0.8)
        end
        if CS:GetMakers(self.itemID) then GameTooltip_AddInstructionLine(GameTooltip, "Right-click to see how it's made") end
    end
    GameTooltip:Show()
end

-- Right-click: the recipes that make the item
local function LinkOrLookup(self, button)
    if IsShiftKeyDown() and self.itemID then
        local _, link = C_Item.GetItemInfo(self.itemID)
        if link then ChatFrameUtil.InsertLink(link) end
    elseif button == "RightButton" then
        local id = self.lookup or self.itemID
        if id then Browser:Show("made:" .. id) end
    elseif self.lookup then
        Browser:Show("item:" .. self.lookup)
    end
end

local function QualityColor(itemID)
    local quality = itemID and CS:ItemQuality(itemID)
    return quality and ITEM_QUALITY_COLORS[quality]
end

-- List ---------------------------------------------------------------------

-- Right-click on a recipe: favourite, track, or the recipes that make its item, like the profession window's menu
local function RecipeMenu(row)
    local recipeID, made = row.recipeID, row.lookup or row.itemID
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateButton(CS:IsFavorite(recipeID) and "Remove from favorites" or "Add to favorites", function()
            CS:SetFavorite(recipeID, not CS:IsFavorite(recipeID))
            Render(true)
        end)
        if CS:CanTrack(recipeID) then
            root:CreateButton(CS:IsTracked(recipeID) and "Untrack recipe" or "Track recipe", function()
                CS:SetTracked(recipeID, not CS:IsTracked(recipeID))
                Render(true)
            end)
        end
        if made then
            root:CreateButton("Recipes that make it", function() Browser:Show("made:" .. made) end)
        end
    end)
end

local function OnRowClick(self, button)
    if self.recipeID and button == "RightButton" and not IsShiftKeyDown() then
        RecipeMenu(self)
    elseif self.recipeID and not IsShiftKeyDown() and button ~= "RightButton" then
        selectedRecipe = self.recipeID
        scrollBox:ForEachFrame(function(frame)
            if frame.Selected then frame.Selected:SetShown(frame.recipeID ~= nil and frame.recipeID == selectedRecipe) end
        end)
        ShowDetail()
    else
        LinkOrLookup(self, button)
    end
end

-- The gold divider line of the profession window's recipe list
local function GoldLine(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(2)
    local r, g, b = NORMAL_FONT_COLOR:GetRGB()
    local base = line:CreateTexture(nil, "ARTWORK")
    base:SetAtlas("Options_HorizontalDivider")
    base:SetAllPoints()
    base:SetVertexColor(r, g, b)
    local glow = line:CreateTexture(nil, "ARTWORK")
    glow:SetAtlas("Options_HorizontalDivider")
    glow:SetAllPoints()
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(r, g, b, 0.5)
    return line
end

-- A category inside a profession, drawn like the profession window's divider; a click folds it like a header
local function InitDivider(frame, data)
    if not frame.Label then
        frame.Label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal_NoShadow")
        frame.Label:SetPoint("BOTTOMLEFT", 10, 10)
        frame.Line = GoldLine(frame)
        frame.Line:SetPoint("BOTTOMLEFT", 5, 5)
        frame.Line:SetPoint("BOTTOMRIGHT", -5, 5)
        frame.Toggle = frame:CreateTexture(nil, "OVERLAY")
        frame.Toggle:SetPoint("RIGHT", frame.Line, "RIGHT", -3, 9)
        frame:SetScript("OnClick", function(self)
            collapsed[self.key] = not collapsed[self.key] or nil
            Render(true)
        end)
        frame:SetScript("OnEnter", function(self) self.Label:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB()) end)
        frame:SetScript("OnLeave", function(self) self.Label:SetTextColor(NORMAL_FONT_COLOR:GetRGB()) end)
    end
    frame.key = data.key
    frame.Label:SetText(data.text)
    frame.Label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    frame.Toggle:SetAtlas(collapsed[data.key] and "common-button-list-plus" or "common-button-list-minus", true)
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
        row.Icon:SetSize(16, 16)
        row.SkillUp = row:CreateTexture(nil, "OVERLAY")
        row.SkillUp:SetSize(13, 15)
        row.SkillUp:SetPoint("LEFT", 4, 0)
        row.Right = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        row.Right:SetPoint("RIGHT", -8, 0)
        row.Right:SetJustifyH("RIGHT")
        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight_NoShadow")
        row.Label:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetWordWrap(false)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnEnter", ShowItemTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", OnRowClick)
    end
    row.itemID, row.lookup, row.recipeID, row.spellID = data.itemID, data.lookup, data.recipeID, data.spellID
    row.Label:SetText(data.left or "")
    row.Right:SetText(data.right or "")
    row.Label:ClearPoint("LEFT")
    -- every row keeps the skill-up arrow's column, so icons and names line up across sections
    row.Icon:ClearAllPoints()
    row.Icon:SetPoint("LEFT", 21, 0)
    if data.skillUp then row.SkillUp:SetAtlas(data.skillUp) end
    row.SkillUp:SetShown(data.skillUp ~= nil)
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

local PAD, DETAIL_W, ROW = 28, 484, 21
local pool = { text = {}, rows = {}, slots = {}, lines = {} } -- widgets reused across selections
local used = { text = 0, rows = 0, slots = 0, lines = 0 }
local content, cursor

local function ItemSlot(parent)
    local b = CreateFrame("ItemButton", nil, parent)
    b:SetSize(SLOT, SLOT)
    b:SetScript("OnEnter", ShowItemTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", LinkOrLookup)
    return b
end

local function FillSlot(slot, itemID, spellID)
    slot.itemID, slot.spellID, slot.lookup = itemID, spellID, itemID
    if itemID then
        slot:SetItemButtonTexture(C_Item.GetItemIconByID(itemID))
        slot:SetItemButtonQuality(CS:ItemQuality(itemID), itemID)
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
    local fs = NextText(font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 0, cursor)
    fs:SetText(text)
    cursor = cursor - fs:GetStringHeight() - (gap or 7)
    return fs
end

-- A source table's heading, led by the game cursor that goes with it (buy, attack, mine...) so kinds tell apart
local function AddHeading(text, cursorIcon)
    cursor = cursor - 14
    AddText((cursorIcon and ("|A:cursor_%s_32:18:18|a "):format(cursorIcon) or "") .. text, "GameFontNormal", 7)
end

-- A main section: its title over the gold divider of the profession window's recipe list
local function AddSection(text)
    cursor = cursor - 16
    AddText(text, "GameFontNormalMed2", 5)
    used.lines = used.lines + 1
    local line = pool.lines[used.lines]
    if not line then
        line = GoldLine(content)
        line:SetWidth(DETAIL_W)
        pool.lines[used.lines] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 0, cursor)
    line:Show()
    cursor = cursor - 2 - 6
end

local function RowTooltip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tip[1], 1, 1, 1)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

-- Only our last TomTom waypoint is replaced; the player's own stay
local tomtomWaypoint

local function SetTomTomPin(uiMap, x, y, name)
    if not (TomTom and TomTom.AddWaypoint) then return false end
    if tomtomWaypoint and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomWaypoint) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, uiMap, x, y,
        { title = name, from = "Craftseeker", crazy = true, silent = true })
    tomtomWaypoint = ok and uid or nil
    return tomtomWaypoint ~= nil
end

-- A waypoint on the map for a source row's NPC or object, and in TomTom when it is installed
local function SetPin(pin, name)
    local uiMap, x, y = pin[1], pin[2], pin[3]
    local info = C_Map.GetMapInfo(uiMap)
    local tomtom = info and SetTomTomPin(uiMap, x, y, name)
    if not (info and C_Map.CanSetUserWaypointOnMap(uiMap)) then
        if not tomtom then
            CS:Print((name or "That place") .. " can't be pinned on the map.")
            return
        end
    else
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMap, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    CS:Print(("%s set: %s, %s (%.1f, %.1f)"):format(tomtom and "map and TomTom pin" or "map pin",
        name or "?", info.name, x * 100, y * 100))
end

-- One table row: columns are { text, width, justify }; tip is shown on hover
local function AddRow(columns, tip, font, onClick)
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
        row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        pool.rows[used.rows] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, cursor)
    row.tip, row.onClick = tip, onClick
    local x = 0
    for i, col in ipairs(columns) do
        local fs = row.cols[i]
        if not fs then
            fs = Text(row, font or "GameFontHighlight")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        fs:SetFontObject(font or "GameFontHighlight")
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
    -- too wide: the name column gives way first (names cut short), then every column shares what is left
    local overflow = total - DETAIL_W
    local first = math.max(need[1] - overflow, math.min(need[1], 140))
    if total - need[1] + first <= DETAIL_W then
        for i = 1, n do widths[i] = need[i] end
        widths[1] = DETAIL_W - (total - need[1])
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

-- Tables of one group share column widths, so vendor, trainer, creature and object columns line up down the pane:
-- name, level, zone, chance or price, count
local SOURCE_COLUMNS = { nil, nil, nil, "RIGHT", "RIGHT" }
local groupNeed, groupDrawn, needGrew = {}, {}, false

-- header: column titles or nil; rows: { cells = { text, ... }, tip = { line, ... }, pin }; justify: per column.
-- Long tables show their first rows and grow TABLE_MORE at a time, so a reagent dropped by hundreds of creatures
-- never builds hundreds of row frames at once; key names the table for its buttons. total, when given, counts rows
-- the caller left unbuilt past TableLimit(key).
local TABLE_MORE = 50
local function TableLimit(key)
    return expanded[key] or TABLE_ROWS
end

local function AddTable(header, rows, justify, key, group, total)
    total = total or #rows
    local shown = math.min(#rows, TableLimit(key))
    local need = {}
    local function Measure(cells, font)
        for i = 1, #cells do need[i] = math.max(need[i] or 0, math.ceil(TextWidth(cells[i], font)) + 13) end
    end
    if header then Measure(header, "GameFontDisable") end
    for i = 1, shown do Measure(rows[i].cells, "GameFontHighlight") end
    measure:SetText("") -- the alpha alone does not hide it
    if group then
        local g = groupNeed[group] or {}
        groupNeed[group] = g
        for i = 1, #need do
            if need[i] > (g[i] or 0) then
                g[i] = need[i]
                if groupDrawn[group] then needGrew = true end
            end
            need[i] = g[i]
        end
        groupDrawn[group] = true
    end
    local widths = ColumnWidths(need)
    local function Columns(cells)
        local cols = {}
        for i = 1, #widths do cols[i] = { cells[i] or "", widths[i], justify and justify[i] } end
        return cols
    end
    if header then AddRow(Columns(header), nil, "GameFontDisable") end
    for i = 1, shown do
        local r = rows[i]
        local click
        if r.pin then
            r.tip[#r.tip + 1] = GOLD .. "Click to set a map pin|r"
            click = function() SetPin(r.pin, r.tip[1]) end
        end
        AddRow(Columns(r.cells), r.tip, nil, click)
    end
    local left = total - shown
    if left > 0 then
        local more = math.min(left, TABLE_MORE)
        AddRow({ { GOLD .. ("Show %d more|r%s"):format(more, GREY .. ", " .. total .. " total|r"), DETAIL_W } }, nil, nil,
            function()
                expanded[key] = shown + more
                ShowDetail(true)
            end)
    end
    if shown > TABLE_ROWS then
        AddRow({ { GOLD .. "Show fewer|r", DETAIL_W } }, nil, nil, function()
            expanded[key] = nil
            ShowDetail(true)
        end)
    end
    if total > TABLE_ROWS then cursor = cursor - 10 end -- keeps the buttons apart from the next heading
end

local function AddSlot(itemID, spellID, label)
    used.slots = used.slots + 1
    local slot = pool.slots[used.slots]
    if not slot then
        slot = ItemSlot(content)
        slot.Text = Text(content, "GameFontHighlight")
        slot.Text:SetPoint("LEFT", slot, "RIGHT", 10, 0)
        slot.Text:SetMaxLines(2)
        pool.slots[used.slots] = slot
    end
    FillSlot(slot, itemID, spellID)
    slot.Text:SetMaxLines(2)
    slot.Text:SetText(label or "")
    slot.Text:Show()
    return slot
end

local function Money(copper)
    return copper and copper > 0 and CS.Money(copper) or ""
end

-- Blanks the game data left (zones, level, map pin) filled from what we and other Craftseeker users saw
local function FillSeen(entry, npc)
    local complete = #(entry.zones or {}) > 0 and entry.pin and (entry.level and entry.rank or not entry.npc)
    if not npc or complete then return end
    local seen = CS:SeenNpc(npc)
    if #(entry.zones or {}) == 0 then entry.zones = seen.zones end
    if entry.npc and not entry.level then entry.level = seen.level end
    if entry.npc and not entry.rank then entry.rank = seen.rank end
    entry.pin = entry.pin or seen.pin
end

-- The world map's dungeon and raid icons in front of an instance's name
local INSTANCE_ICON = { "|A:Dungeon:14:14|a ", "|A:Raid:14:14|a " }

local function ZoneCell(zones)
    if not zones or #zones == 0 then return GREY .. "unknown|r" end
    local icon = INSTANCE_ICON[CS.BUILTIN_INSTANCES and CS.BUILTIN_INSTANCES[zones[1]] or 0] or ""
    return icon .. zones[1] .. (#zones > 1 and (GREY .. " +" .. (#zones - 1) .. "|r") or "")
end

-- Chests and other objects an item comes from, and bag items that hold it when opened (clams, lockboxes), with how
-- often each gave it where players counted; QuestieDB lacks spawns for many objects, and where players looted them
-- fills in. Counted sources the lists lack are added, so whatever gave the item shows.
local function IsLooted(g)
    return g.kind == "c" or g.kind == "g" and g.p == "Chest"
end

local function AddObjects(itemID, qs, heading, key)
    local byKey, list = {}, {}
    local function Entry(kind, id)
        local e = byKey[kind .. id]
        if not e then
            e = { kind = kind, id = id }
            byKey[kind .. id] = e
            list[#list + 1] = e
        end
        return e
    end
    for _, o in ipairs(qs and qs.objects or {}) do
        local e = Entry("g", o.id)
        e.name, e.zones, e.pin = o.name, o.zones, o.pin
    end
    for _, c in ipairs(qs and qs.containers or {}) do Entry("c", c.id) end
    for _, g in ipairs(CS:GetGatherRates(itemID) or {}) do
        if IsLooted(g) then
            local e = Entry(g.kind, g.id)
            e.chance, e.k, e.own, e.n = g.chance, g.k, g.own, g.n
        end
    end
    if #list == 0 then return false end
    -- one chest name spans several object ids (one per zone or model); a row each read as duplicates, so they merge
    local byName, merged = {}, {}
    for _, e in ipairs(list) do
        if e.kind == "c" then
            e.name = CS:ItemName(e.id) or ("Item " .. e.id)
        else
            if not e.name then
                local qname, qzones, qpin = CS:ObjectInfo(e.id)
                e.name, e.zones, e.pin = qname or e.n or ("Object " .. e.id), qzones, qpin
            end
            e.zones = e.zones and #e.zones > 0 and e.zones or CS:SeenObjectZones(e.id)
            e.pin = e.pin or CS:SeenObjectPin(e.id)
        end
        local m = byName[e.kind .. e.name]
        if not m then
            m = { kind = e.kind, name = e.name, zones = {}, hasZone = {}, pin = e.pin, k = 0, drops = 0, own = 0 }
            byName[e.kind .. e.name] = m
            merged[#merged + 1] = m
        end
        for _, z in ipairs(e.zones or {}) do
            if not m.hasZone[z] then m.zones[#m.zones + 1], m.hasZone[z] = z, true end
        end
        m.pin = m.pin or e.pin
        if e.chance then
            m.k, m.drops, m.own = m.k + e.k, m.drops + e.chance / 100 * e.k, m.own + (e.own or 0)
        end
    end
    list = merged
    for _, e in ipairs(list) do
        if e.k > 0 then e.chance = math.min(e.drops / e.k, 1) * 100 end
    end
    table.sort(list, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        return a.name < b.name
    end)
    AddHeading(heading, "lootall")
    local rows = {}
    for i = 1, math.min(#list, TableLimit(key)) do
        local e, zones, tip = list[i], nil, nil
        if e.kind == "c" then
            tip = { e.name, "Can contain " .. (CS:ItemName(itemID) or "this item") }
        else
            zones = e.zones
            tip = { e.name, #zones > 0 and ("Zones: " .. table.concat(zones, ", ")) or "Zone not recorded" }
        end
        tip[#tip + 1] = e.chance and ("%.2f%% over %d times opened"):format(e.chance, e.k) or "No measured rate yet"
        if e.own and e.own > 0 then
            tip[#tip + 1] = ("%d of those are your own"):format(e.own)
        elseif e.chance then
            tip[#tip + 1] = "All counted by other players"
        end
        rows[#rows + 1] = { cells = { e.name, "", zones and ZoneCell(zones) or "",
            e.chance and ("%s%.2f%%|r"):format(GOLD, e.chance) or (GREY .. "no data|r"),
            e.chance and ("%s(%d)|r"):format(GREY, e.k) or "" }, tip = tip, pin = e.pin }
    end
    AddTable(nil, rows, SOURCE_COLUMNS, key, "sources", #list)
    return true
end

-- Skinning, mining and herb gathering corpses and nodes, with how often each gave the item; chests go with the objects
local function AddGathering(itemID)
    local list = {}
    for _, g in ipairs(CS:GetGatherRates(itemID) or {}) do
        if not IsLooted(g) then list[#list + 1] = g end
    end
    if #list == 0 then return false end
    local rows = {}
    for i = 1, math.min(#list, TableLimit("gathering")) do
        local g, label, zones, pin = list[i], nil, nil, nil
        if g.kind == "k" then
            label = CS:NpcName(g.id) or CS:SeenNpcName(g.id) or ("NPC " .. g.id)
            local entry = { zones = CS:GetPlaces(g.id), npc = g.id }
            if #entry.zones == 0 then entry.zones = CS:NpcZones(g.id) or {} end
            FillSeen(entry, g.id)
            zones, pin = entry.zones, entry.pin or CS:GetPin(g.id)
        else
            local qname, qzones, qpin = CS:ObjectInfo(g.id)
            label = qname or g.n or ("Object " .. g.id)
            zones = qzones and #qzones > 0 and qzones or CS:SeenObjectZones(g.id)
            pin = qpin or CS:SeenObjectPin(g.id)
        end
        local tip = { label .. (g.p and (" - " .. g.p) or ""),
            #zones > 0 and ("Zones: " .. table.concat(zones, ", ")) or "Zone not recorded",
            ("%.2f%% over %d times gathered"):format(g.chance, g.k) }
        tip[#tip + 1] = g.own > 0 and ("%d of those are your own"):format(g.own) or "All counted by other players"
        -- the profession sits in the level column, so names keep their room
        rows[#rows + 1] = { cells = { label, g.p and (GREY .. g.p .. "|r") or "", ZoneCell(zones), ("%s%.2f%%|r"):format(GOLD, g.chance),
            ("%s(%d)|r"):format(GREY, g.k) }, tip = tip, pin = pin }
    end
    AddHeading(("Gathered from %d source%s"):format(#list, #list == 1 and "" or "s"), "mine")
    AddTable({ "Source", "How", "Zone", "Chance", "" }, rows, SOURCE_COLUMNS, "gathering", "sources", #list)
    return true
end

-- Every creature that drops an item, best measured rate first, then this zone's, then by name; nothing is cut. heading
-- formats the count ("Recipe dropped by %d creature%s" when nil); key names the table
local function AddDrops(itemID, qs, heading, key)
    local byNpc, list = {}, {}
    for _, e in ipairs(qs and qs.drops or {}) do
        local entry = { npc = e.npc, name = e.name, level = e.level, rank = e.rank, zones = e.zones, pin = e.pin }
        byNpc[e.npc] = entry
        list[#list + 1] = entry
    end
    for _, r in ipairs(CS:GetDropRates(itemID) or {}) do
        local entry = byNpc[r.npc]
        if not entry then
            entry = { npc = r.npc, name = r.name, zones = {}, pin = CS:GetPin(r.npc) }
            byNpc[r.npc] = entry
            list[#list + 1] = entry
        end
        entry.chance, entry.kills, entry.own = r.chance, r.kills, r.own
    end
    if #list == 0 then return false end
    -- QuestieDB has no spawns for many Forever creatures; the built-in places, then its main zone, fill in
    for _, e in ipairs(list) do
        if #e.zones == 0 then e.zones = CS:GetPlaces(e.npc) end
        if #e.zones == 0 then e.zones = CS:NpcZones(e.npc) or {} end
    end
    local here = GetRealZoneText()
    table.sort(list, function(a, b)
        if (a.chance or -1) ~= (b.chance or -1) then return (a.chance or -1) > (b.chance or -1) end
        local ah, bh = a.zones[1] == here, b.zones[1] == here
        if ah ~= bh then return ah end
        return a.name < b.name
    end)
    AddHeading((heading or "Recipe dropped by %d creature%s"):format(#list, #list == 1 and "" or "s"), "attack")
    -- rows past the table's fold aren't built: a reagent can drop from hundreds of creatures, redrawn on every loot
    local rows = {}
    for i = 1, math.min(#list, TableLimit(key or "drops")) do
        local e = list[i]
        if not e.level then
            local level, rank = CS:NpcLevel(e.npc)
            e.level, e.rank = level, e.rank or rank
        end
        FillSeen(e, e.npc)
        local name = e.rank and (e.name .. GOLD .. " " .. e.rank .. "|r") or e.name
        -- rate and corpse count in their own right-aligned columns, so digits and % signs line up
        local chance = e.chance and ("%s%.2f%%|r"):format(GOLD, e.chance) or (GREY .. "no data|r")
        local corpses = e.chance and ("%s(%d)|r"):format(GREY, e.kills) or ""
        local tip = { e.name }
        if e.rank then tip[#tip + 1] = e.rank end
        if e.level then tip[#tip + 1] = "Level " .. e.level end
        tip[#tip + 1] = #e.zones > 0 and ("Zones: " .. table.concat(e.zones, ", ")) or "Zone not recorded"
        tip[#tip + 1] = e.chance and (("%.2f%% over %d corpses looted by other players"):format(e.chance, e.kills))
            or "No measured drop rate yet"
        if e.own and e.own > 0 then tip[#tip + 1] = ("%d of those corpses are your own"):format(e.own) end
        rows[#rows + 1] = { cells = { name, e.level and tostring(e.level) or "", ZoneCell(e.zones), chance, corpses }, tip = tip, pin = e.pin }
    end
    AddTable({ "Creature", "Level", "Zone", "Chance", "" }, rows, SOURCE_COLUMNS, key or "drops", "sources", #list)
    return true
end

-- Vendors of an item, this faction only: what players saw (with price) joined with QuestieDB's list; heading takes the count
local function AddVendors(itemID, qs, heading)
    local byNpc, list = {}, {}
    for _, v in ipairs(CS:GetVendors(itemID) or {}) do
        local price = v.copper and v.copper > 0 and (Money(v.copper) .. (v.stack and v.stack > 1 and (GREY .. " /" .. v.stack .. "|r") or "")) or ""
        local entry = { name = v.name, zones = v.zone and { v.zone } or {}, price = price, pin = v.pin }
        byNpc[v.npc] = entry
        list[#list + 1] = entry
    end
    for _, e in ipairs(qs and qs.vendors or {}) do
        local entry = byNpc[e.npc]
        if entry then
            if #entry.zones == 0 then entry.zones = e.zones end
            entry.pin = entry.pin or e.pin
        else
            entry = { name = e.name, zones = e.zones, price = "", pin = e.pin }
            byNpc[e.npc] = entry
            list[#list + 1] = entry
        end
    end
    -- prices seen at the vendor fill blanks; a vendor only we visited joins the list (other users' may be the other faction)
    local seen, own = CS:SeenPrices(itemID)
    for npc, p in pairs(seen) do
        local entry = byNpc[npc]
        -- a vendor only players have seen joins the list: ours, or another user's of our faction (or neutral)
        local faction = not own[npc] and CS:SeenNpc(npc).faction
        if not entry and (own[npc] or faction == 3 or faction == (CS.PlayerFaction() == 2 and 2 or 1)) then
            entry = { name = p[3] or CS:NpcName(npc) or ("NPC " .. npc), zones = CS:GetPlaces(npc), price = "",
                pin = CS:GetPin(npc) }
            byNpc[npc] = entry
            list[#list + 1] = entry
        end
        if entry and entry.price == "" then
            entry.price = Money(p[1]) .. (p[2] > 1 and (GREY .. " /" .. p[2] .. "|r") or "")
        end
    end
    if #list == 0 then return false end
    for npc, entry in pairs(byNpc) do
        if #entry.zones == 0 then entry.zones = CS:NpcZones(npc) or {} end
        FillSeen(entry, npc)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    AddHeading((heading or "Recipe sold by %d vendor%s"):format(#list, #list == 1 and "" or "s"), "buy")
    local rows = {}
    for _, v in ipairs(list) do
        rows[#rows + 1] = { cells = { v.name, "", ZoneCell(v.zones), v.price, "" },
            tip = { v.name, #v.zones > 0 and ("Zones: " .. table.concat(v.zones, ", ")) or "Zone not recorded" }, pin = v.pin }
    end
    AddTable(nil, rows, SOURCE_COLUMNS, heading and "buy" or "vendors", "sources")
    return true
end

-- Quests that teach a recipe or reward its recipe item: name, who gives it and where
local function AddQuests(recipeID, qs, teach)
    local list, seen = {}, {}
    for _, q in ipairs(CS:GetRecipeQuests(recipeID) or {}) do
        list[#list + 1] = q
        seen[q.name] = true
    end
    -- then the item sources' quests and the ones players saw offering the recipe item
    for _, q in ipairs(qs and qs.quests or {}) do
        if not seen[q.name] then
            list[#list + 1] = q
            seen[q.name] = true
        end
    end
    for _, q in ipairs(teach and teach > 0 and CS:SeenQuests(teach) or {}) do
        if not seen[q.name] then
            list[#list + 1] = q
            seen[q.name] = true
        end
    end
    if #list == 0 then return false end
    AddHeading(#list == 1 and "Quest" or ("%d quests"):format(#list), "quest")
    local rows = {}
    for _, q in ipairs(list) do
        -- the opposite faction's quests (listed with the setting on) are greyed
        local name = (q.opposite and GREY or "") .. q.name .. (q.opposite and "|r" or "")
            .. (q.level and (GREY .. " (" .. q.level .. ")|r") or "")
        local tip = { q.name, q.giver and ("Given by " .. q.giver) or "Giver not recorded" }
        if q.zone then tip[#tip + 1] = "In " .. q.zone end
        if q.level then tip[#tip + 1] = "Level " .. q.level end
        if q.opposite then tip[#tip + 1] = "Only the opposite faction gets this quest" end
        rows[#rows + 1] = { cells = { name, q.giver or (GREY .. "unknown|r"), q.zone or (GREY .. "unknown|r") },
            tip = tip, pin = q.pin }
    end
    AddTable({ "Quest", "Given by", "Zone" }, rows, nil, "quests")
    return true
end

local function AddTrainers(recipeID)
    local list = CS:GetTrainers(recipeID)
    if not list then return false end
    table.sort(list, function(a, b) return (a.zone or "~") < (b.zone or "~") end)
    AddHeading(("Taught by %d trainer%s"):format(#list, #list == 1 and "" or "s"), "trainer")
    local rows = {}
    for _, t in ipairs(list) do
        local seen = { zones = t.zone and { t.zone } or {}, pin = t.pin }
        FillSeen(seen, t.npc)
        t.zone, t.pin = seen.zones[1], seen.pin
        rows[#rows + 1] = { cells = { t.name, "", t.zone or (GREY .. "unknown|r"), Money(t.copper), "" },
            tip = { t.name, t.zone or "Zone not recorded" }, pin = t.pin }
    end
    AddTable(nil, rows, SOURCE_COLUMNS, "trainers", "sources")
    return true
end

-- Zone names from a flat area, faction[, level] list, keeping this character's faction only
local function AreaList(list, perEntry, withLevel)
    local mine = CS.PlayerFaction()
    local out, seen = {}, {}
    for i = 1, #list, perEntry do
        if CS.ForMe(list[i + 1], mine) then
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

-- One character's standing with a recipe: knows it, can learn it, or how much skill is missing
local function SkillStatus(recipeID, rec, char)
    local known = rawget(CS.data.known, char)
    if known and known[recipeID] then return "knows it" end
    local diff, rank = CS:Difficulty(recipeID, char)
    if not rank then return nil end
    local learn = CS:SkillRange(recipeID)
    if diff == "learn" then
        return ("%sneeds %d more skill|r (%s %d)"):format(RED, learn - rank, rec.p, rank)
    end
    return ("%scan learn it now|r (%s %d)"):format(CS.DIFFICULTY_COLOR[diff or ""] or "", rec.p, rank)
end

-- The skill colours, then where this character and each alt with the profession stand
function AddSkill(recipeID, rec)
    local learn, yellow, green, grey = CS:SkillRange(recipeID)
    local c = CS.DIFFICULTY_COLOR
    if yellow then
        AddText(("Skill  %s%d|r  %s%d|r  %s%d|r  %s%d|r"):format(c.orange, learn, c.yellow, yellow, c.green, green, c.grey, grey))
    end
    local me = CS.CharKey()
    local mine = SkillStatus(recipeID, rec, me)
    AddText("You: " .. (mine or (GREY .. "you don't have " .. (rec.p or "this profession") .. "|r")))
    local alts = {}
    for char in pairs(CS.data.skills) do
        local status = char ~= me and SkillStatus(recipeID, rec, char)
        if status then alts[#alts + 1] = (char:match("^[^-]+") or char) .. ": " .. status end
    end
    table.sort(alts)
    for _, line in ipairs(alts) do AddText(line) end
end

-- A class spell that uses reagents: who learns it and at what level
local function AddClassSpell(recipeID, rec, level)
    AddSection("How to learn it")
    AddText(("%s spell, taught by %s trainers from level %d"):format(rec.p, rec.p, level))
    local myClass = UnitClass("player")
    if myClass == rec.p then
        local mine = UnitLevel("player")
        AddText(mine >= level and "You: can learn it" or ("You: %sat level %d|r (you are %d)"):format(RED, level, mine))
    end
end

local function AddLearn(recipeID, rec)
    local classLevel = CS.BUILTIN_CLASS and CS.BUILTIN_CLASS[recipeID]
    if classLevel then return AddClassSpell(recipeID, rec, classLevel) end
    AddSection("How to learn it")
    local info = CS:GetLearnInfo(recipeID)
    if not info then
        AddText(GREY .. "Not recorded in the built-in data.|r")
        return
    end
    local how = info.how
    if info.teach > 0 then
        local name = CS:ItemName(info.teach) or "Recipe item"
        local tq = QualityColor(info.teach)
        if tq then name = tq.hex .. name .. "|r" end
        local slot = AddSlot(info.teach, nil, name .. (info.bound and (GREY .. "  (binds when picked up)|r") or ""))
        slot:SetPoint("TOPLEFT", 0, cursor)
        slot.Text:SetWidth(DETAIL_W - SLOT - 20)
        cursor = cursor - SLOT - 8
    end
    if info.skill > 0 then AddText(("Requires %s (%d)"):format(rec.p or "?", info.skill)) end
    AddSkill(recipeID, rec)
    for i = 1, #info.rep, 2 do
        local fdata = C_Reputation.GetFactionDataByID(info.rep[i])
        local standing = _G["FACTION_STANDING_LABEL" .. info.rep[i + 1]] or info.rep[i + 1]
        AddText(("Requires %s with %s"):format(standing, fdata and fdata.name or ("faction " .. info.rep[i])))
    end
    if info.favor > 0 then AddText(("Costs %d Merchant's Favor"):format(info.favor)) end
    if info.side > 0 then AddText(FACTION_NAME[info.side] .. " only") end
    -- poisons are the rogue's class skill: one comes with the skill, the rest from rogue trainers
    local poisons = rec.p == "Poisons"
    if how:find("a") then
        AddText(poisons and "Learned with the Poisons skill" or "Learned automatically with the profession")
    end

    local qs = info.teach > 0 and CS:GetItemSources(info.teach) or nil
    local shown = false
    if AddTrainers(recipeID) then
        shown = true
    elseif how:find("t") then
        AddText((poisons and "Taught by Rogue trainers" or "Trainer") .. (info.cost > 0 and ("  " .. Money(info.cost)) or ""))
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
    if AddQuests(recipeID, qs, info.teach) then
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
    if AddObjects(info.teach, qs, "Found in", "objects") then
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
    measure = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    measure:SetPoint("TOPLEFT")
    measure:SetAlpha(0)
    scroll:SetScrollChild(content)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    detail.scroll = scroll

    detail.Output = ItemSlot(content)
    detail.Output:SetPoint("TOPLEFT", 0, -6)
    detail.Name = Text(content, "GameFontHighlightMed2")
    detail.Name:SetPoint("TOPLEFT", detail.Output, "TOPRIGHT", 12, -2)
    detail.Name:SetWidth(DETAIL_W - SLOT - 12)
    detail.Name:SetWordWrap(false)
    detail.Sub = Text(content, "GameFontHighlight")
    detail.Sub:SetPoint("TOPLEFT", detail.Name, "BOTTOMLEFT", 0, -5)
    detail.Sub:SetWidth(DETAIL_W - SLOT - 12)
    detail.Name:SetWidth(DETAIL_W - SLOT - 12 - 120)

    -- the profession window's favourite star and "Track" checkbox
    local star = CreateFrame("Button", nil, content)
    star:SetSize(20, 18)
    star:SetPoint("TOPRIGHT", 0, -6)
    star.Icon = star:CreateTexture(nil, "ARTWORK")
    star.Icon:SetAllPoints()
    star:SetHighlightAtlas("auctionhouse-icon-favorite-off", "ADD")
    star:SetScript("OnClick", function()
        CS:SetFavorite(selectedRecipe, not CS:IsFavorite(selectedRecipe))
        Render(true)
    end)
    star:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_AddHighlightLine(GameTooltip, CS:IsFavorite(selectedRecipe) and "Remove from favorites" or "Add to favorites")
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", GameTooltip_Hide)
    detail.Favorite = star

    local track = CreateFrame("CheckButton", nil, content, "CheckboxWithLabelTemplate")
    track:SetSize(26, 26)
    track.Text:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode("Track"))
    -- one line with the star: the box, its label, then the star at the right edge
    track:SetPoint("RIGHT", star, "LEFT", -(track.Text:GetStringWidth() + 14), 0)
    track:SetScript("OnClick", function(self)
        CS:SetTracked(selectedRecipe, self:GetChecked())
        Render(true)
    end)
    detail.Track = track
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
    detail.Favorite:Hide()
    detail.Track:Hide()
end

-- keep: a redraw of the same recipe (show-more, new bag counts, a list refresh) stays where the reader is
local shownRecipe
function ShowDetail(keep)
    if not keep or selectedRecipe ~= shownRecipe then wipe(groupNeed) end
    wipe(groupDrawn)
    needGrew = false
    DrawDetail(keep)
    -- a later table of a group came out wider than an earlier one: draw once more with the group's widths
    if needGrew then
        wipe(groupDrawn)
        needGrew = false
        DrawDetail(true)
    end
end

function DrawDetail(keep)
    keep = keep and selectedRecipe == shownRecipe
    shownRecipe = selectedRecipe
    if not keep then wipe(expanded) end
    ResetDetail()
    local rec = selectedRecipe and CS.recipes[selectedRecipe]
    local atlas = rec and rec.p and ("Professions-Recipe-Background-" .. rec.p:gsub("%s", ""))
    if not (atlas and C_Texture.GetAtlasInfo(atlas)) then atlas = "Professions-Recipe-Background" end
    detail.Background:SetAtlas(atlas)
    if not keep then detail.scroll:SetVerticalScroll(0) end
    cursor = 8 -- the first section's gap brings it to the top
    if not rec then
        AddSection("How to use")
        AddText("Alt+Click an item in your bags, or type in the search box.")
        AddText("Click an item to see what it's used in.")
        AddText("Right-click an item to see how it's made.")
        AddText("Right-click a recipe to favorite or track it.")
        AddText("Click a vendor, trainer or creature to pin it on your map.")
        AddSection("Legend")
        AddText("|A:Professions-Icon-Skill-High:15:13|a  Guaranteed skill-up")
        AddText("|A:Professions-Icon-Skill-Medium:15:13|a  Likely skill-up")
        AddText("|A:Professions-Icon-Skill-Low:15:13|a  Small chance of a skill-up")
        AddText("|A:common-icon-checkmark:14:14|a  You know this recipe")
        AddText(RED .. "Red name|r  Your skill is too low")
        AddText("|cff66bbffBlue name|r  One of your alts knows it, hover to see which")
        if CS.data.settings.opposite then
            AddText((CS.PlayerFaction() == 2 and "|A:AllianceSymbol:16:16|a" or "|A:HordeSymbol:16:16|a") .. "  Only the opposite faction can learn it")
        end
        content:SetHeight(-cursor)
        return
    end

    FillSlot(detail.Output, rec.o, rec.o == nil and selectedRecipe or nil)
    detail.Favorite.Icon:SetAtlas(CS:IsFavorite(selectedRecipe) and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
    detail.Favorite:Show()
    detail.Track:SetShown(CS:CanTrack(selectedRecipe))
    detail.Track:SetChecked(CS:IsTracked(selectedRecipe))
    local color = QualityColor(rec.o)
    detail.Name:SetText((rec.n or "?") .. (rec.q and rec.q > 1 and (" x" .. rec.q) or ""))
    if color then detail.Name:SetTextColor(color.r, color.g, color.b) else detail.Name:SetTextColor(1, 1, 1) end
    local who, alt = CS:WhoKnows(selectedRecipe)
    detail.Sub:SetText((rec.p or "?") .. "   " .. (CS.BUILTIN_CLASS and CS.BUILTIN_CLASS[selectedRecipe] and "class spell"
        or who == "me" and "|cff40ff40You know this|r"
        or who == "alt" and (GOLD .. "Known by " .. alt .. "|r")
        or not CS:IsProven(selectedRecipe) and (GREY .. "Not seen on WoW: Forever yet|r")
        or (GREY .. "None of your characters know this|r")))
    cursor = -6 - SLOT

    AddSection("Reagents")
    for i, r in ipairs(rec.r) do
        local id, qty = r[1], r[2]
        local name = CS:ItemName(id) or ("item " .. id)
        local have, alts, bank = CS:ItemCounts(id)
        local label = (have < qty and RED or "") .. have .. "/" .. qty .. (have < qty and "|r" or "") .. " "
            .. (id == currentItem and (GOLD .. name .. "|r") or name)
        -- only when the bags alone fall short: then a bank trip comes before the craft
        if bank > 0 and have - bank < qty then label = label .. "\n" .. GREY .. bank .. " in your bank|r" end
        if #alts > 0 then
            local parts = {}
            for k = 1, math.min(3, #alts) do parts[k] = alts[k][1] .. " " .. alts[k][2] end
            label = label .. "\n" .. GREY .. "Alts: " .. table.concat(parts, ", ") .. (#alts > 3 and ", ..." or "") .. "|r"
        end
        local slot = AddSlot(id, nil, label)
        slot.Text:SetMaxLines(3)
        local col = (i - 1) % 2
        slot:SetPoint("TOPLEFT", col * REAGENT_COL, cursor)
        slot.Text:SetWidth(REAGENT_COL - SLOT - 20)
        if col == 1 or i == #rec.r then cursor = cursor - REAGENT_STEP end
    end

    AddLearn(selectedRecipe, rec)

    -- the looked-up reagent: vendors with prices, creatures with drop rates, objects, then what this account has seen
    if currentItem and not madeView then
        local name = CS:ItemName(currentItem) or "it"
        local qs = CS:GetItemSources(currentItem)
        AddSection("Where to get " .. name)
        local any = false
        local makers = CS:GetMakers(currentItem)
        if makers then
            local id = currentItem
            cursor = cursor - 6
            AddRow({ { "|A:cursor_repair_32:18:18|a " .. GOLD .. ("Made by %d recipe%s|r"):format(#makers, #makers == 1 and "" or "s"), DETAIL_W } },
                { "Click to see the recipes that make it" }, nil, function() Browser:Show("made:" .. id) end)
            any = true
        end
        any = AddVendors(currentItem, qs, "Sold by %d vendor%s") or any
        any = AddDrops(currentItem, qs, "Drops from %d creature%s", "reagentDrops") or any
        any = AddGathering(currentItem) or any
        any = AddObjects(currentItem, qs, "Looted from", "reagentObjects") or any
        local seen = {}
        for _, l in ipairs(CS:SourceLines(currentItem, 50)) do
            seen[#seen + 1] = { cells = { l[2], GREY .. l[1] .. "|r" }, tip = { l[2] } }
        end
        if #seen > 0 then
            AddHeading("Where you found it", "inspect")
            AddTable(nil, seen, { nil, "RIGHT" }, "seen")
        elseif not any then
            AddText(GREY .. "No source recorded yet.|r")
        end
    end
    content:SetHeight(-cursor + 12)
end

-- Frame --------------------------------------------------------------------

local function Build()
    f = CreateFrame("Frame", "CraftseekerBrowser", UIParent, "PortraitFrameTemplate")
    f:SetSize(830, 620)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetTitle("Craftseeker")
    f:SetPortraitToAsset(DEFAULT_ICON)
    f:Hide()
    tinsert(UISpecialFrames, "CraftseekerBrowser")

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

    -- the profession window's Filter menu; its red reset button shows while any filter is on
    local filterButton = CreateFrame("DropdownButton", nil, list, "WowStyle1FilterDropdownTemplate")
    filterButton:SetPoint("TOPRIGHT", -8, -9)
    -- Sources and Slots work like the profession window's: everything ticked, untick to hide
    local function Submenu(root, title, key, entries)
        local sub = root:CreateButton(title)
        sub:CreateButton("Check all", function()
            CS.data.settings.filters[key] = nil
            Render(true)
            return MenuResponse.Refresh
        end)
        sub:CreateButton("Uncheck all", function()
            local hidden = {}
            for _, e in ipairs(entries) do hidden[e[1]] = true end
            CS.data.settings.filters[key] = hidden
            Render(true)
            return MenuResponse.Refresh
        end)
        for _, e in ipairs(entries) do
            sub:CreateCheckbox(e[2], function()
                local hidden = CS.data.settings.filters[key]
                return not (hidden and hidden[e[1]])
            end, function()
                local hidden = CS.data.settings.filters[key] or {}
                hidden[e[1]] = not hidden[e[1]] or nil
                CS.data.settings.filters[key] = next(hidden) and hidden or nil
                Render(true)
            end)
        end
    end
    local slots = {}
    for i, s in ipairs(CS.SLOT_FILTERS) do slots[i] = { s, s } end
    filterButton:SetupMenu(function(_, root)
        for _, entry in ipairs(FILTERS) do
            local key = entry[1]
            root:CreateCheckbox(entry[2], function() return CS.data.settings.filters[key] == true end, function()
                CS.data.settings.filters[key] = not CS.data.settings.filters[key] or nil
                Render(true)
            end)
        end
        root:CreateDivider()
        Submenu(root, "Sources", "sources", CS.SOURCE_FILTERS)
        Submenu(root, "Slots", "slots", slots)
    end)
    filterButton:SetDefaultCallback(function()
        wipe(CS.data.settings.filters)
        Render(true)
    end)
    filterButton:SetIsDefaultCallback(function() return not CS:AnyFilter() end)
    Browser.filterButton = filterButton

    searchBox = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", 13, -8)
    searchBox:SetPoint("RIGHT", filterButton, "LEFT", -4, 0)
    searchBox.Instructions:SetText("Item or recipe")
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Browser:Show(self:GetText())
    end)
    -- live search; a short delay keeps each keystroke from rebuilding the list
    local pending
    searchBox:HookScript("OnTextChanged", function(self, userInput)
        -- the clear button empties the box without user input: back to the start page and your reagents
        if not userInput then
            if self:GetText() == "" and currentQuery ~= "" then Browser:Show("", true) end
            return
        end
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
        elseif data.spacer then
            factory("Frame")
        elseif data.divider then
            -- its own frame type, so the pool never hands a divider to a spacer or a recipe row
            factory("CheckButton", InitDivider)
        else
            factory("Button", InitRow)
        end
    end)
    view:SetElementExtentCalculator(function(_, data)
        if data.header then return HEADER_H end
        return data.spacer and SPACER_H or data.divider and DIVIDER_H or ROW_H
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
local homeKeep -- the start page lists the selected recipe, so it stays on the right

local function RecipeRow(recipeID, reagentID)
    local rec = CS.recipes[recipeID]
    local _, text, right, skillUp = CS:RecipeLine(recipeID, reagentID)
    return {
        recipeID = recipeID, itemID = rec.o, spellID = rec.o == nil and recipeID or nil,
        icon = (rec.o and C_Item.GetItemIconByID(rec.o) or C_Spell.GetSpellTexture(recipeID)) or 134400,
        left = text, right = right, skillUp = skillUp,
    }
end

-- A start-page section of recipes, by name, that pass the filters
local function RecipeSection(list, title, ids)
    local kept = {}
    for _, id in ipairs(ids) do
        if CS:Shown(id) and CS:PassesFilters(id) then kept[#kept + 1] = id end
    end
    if #kept == 0 then return end
    table.sort(kept, function(a, b) return (CS.recipes[a].n or "") < (CS.recipes[b].n or "") end)
    list[#list + 1] = { header = true, key = title, text = title .. "  " .. GREY .. #kept .. "|r" }
    if collapsed[title] then return end
    for _, id in ipairs(kept) do
        if id == selectedRecipe then homeKeep = true end
        list[#list + 1] = RecipeRow(id)
    end
    list[#list + 1] = { spacer = true }
end

-- A start-page section of reagents, by name; with filters on, each counts only the recipes that pass them
local function ReagentSection(list, title, ids)
    local rows, filtered = {}, CS:AnyFilter()
    for _, itemID in ipairs(ids) do
        local uses = CS:GetUses(itemID)
        if uses and filtered then
            local kept = {}
            for _, id in ipairs(uses) do
                if CS:PassesFilters(id) then kept[#kept + 1] = id end
            end
            uses = #kept > 0 and kept or nil
        end
        if uses then
            rows[#rows + 1] = {
                itemID = itemID, lookup = itemID,
                icon = C_Item.GetItemIconByID(itemID),
                left = CS:ItemName(itemID) or ("item " .. itemID),
                right = #uses .. " recipe" .. (#uses == 1 and "" or "s"),
            }
        end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b) return a.left < b.left end)
    list[#list + 1] = { header = true, key = title, text = title .. "  " .. GREY .. #rows .. "|r" }
    if collapsed[title] then return end
    for _, row in ipairs(rows) do list[#list + 1] = row end
    list[#list + 1] = { spacer = true }
end

-- Favorites, tracked recipes, then the reagents this character carries; the bank's own section says where they are
local function WelcomeView()
    SetHeading(nil, "Look up an item or recipe", ("%d recipes across every profession"):format(CS:CountRecipes()))
    local list, favorites = {}, {}
    for id in pairs(CS.data.favorites) do favorites[#favorites + 1] = id end
    RecipeSection(list, "Favorites", favorites)
    RecipeSection(list, "Tracked", CS:TrackedRecipes())
    local mine = CS.data.items[CS.CharKey()] or {}
    local bags, bank = {}, {}
    for itemID in pairs(mine.bags or {}) do bags[#bags + 1] = itemID end
    for itemID in pairs(mine.bank or {}) do
        if not (mine.bags and mine.bags[itemID]) then bank[#bank + 1] = itemID end
    end
    ReagentSection(list, "Reagents in your bags", bags)
    ReagentSection(list, "Reagents in your bank", bank)
    if #list == 0 then
        return nil, CS:AnyFilter() and FILTERED or "Your favorites, tracked recipes and the reagents you carry show up here."
    end
    return list
end

local ProfessionSections
local function PickerView(hits, uses, recipes, query)
    SetHeading(nil, "Search", ("%d reagent%s and %d recipe%s match \"%s\""):format(#hits, #hits == 1 and "" or "s",
        #recipes, #recipes == 1 and "" or "s", query))
    if #hits + #recipes == 0 then return nil, "Nothing matches that." end
    local list = {}
    if #hits > 0 and #recipes > 0 then
        list[1] = { header = true, key = "Reagents", text = "Reagents  " .. GREY .. #hits .. "|r" }
    end
    for _, itemID in ipairs(collapsed.Reagents and #recipes > 0 and {} or hits) do
        local n = uses[itemID]
        list[#list + 1] = {
            itemID = itemID, lookup = itemID,
            icon = C_Item.GetItemIconByID(itemID),
            left = CS:ItemName(itemID) or ("item " .. itemID),
            right = n .. " recipe" .. (n == 1 and "" or "s"),
        }
    end
    if #list > 1 then list[#list + 1] = { spacer = true } end
    for _, row in ipairs(ProfessionSections(recipes)) do list[#list + 1] = row end
    if #list == 0 then return nil, FILTERED end
    return list
end

-- Recipes in one section per profession, in the order given; reagentID tags optional reagents
local viewRecipes = {} -- every recipe the view holds, filtered out or folded away too: bag changes redraw for these
function ProfessionSections(ids, reagentID)
    local list, first = {}, nil
    local byProf, profs = {}, {}
    for _, id in ipairs(ids or {}) do viewRecipes[id] = true end
    if ids and CS:AnyFilter() then
        local kept = {}
        for _, recipeID in ipairs(ids) do
            if CS:PassesFilters(recipeID) then kept[#kept + 1] = recipeID end
        end
        ids = kept
    end
    for _, recipeID in ipairs(ids or {}) do
        local p = CS:IsFavorite(recipeID) and FAVORITES or CS.recipes[recipeID].p or "?"
        if not byProf[p] then
            byProf[p] = {}
            profs[#profs + 1] = p
        end
        table.insert(byProf[p], recipeID)
    end
    -- the character's own professions first, then the rest, each alphabetical
    local me = CS.CharKey()
    table.sort(profs, function(a, b)
        if (a == FAVORITES) ~= (b == FAVORITES) then return a == FAVORITES end
        local ma, mb = CS:SkillOf(me, a) ~= nil, CS:SkillOf(me, b) ~= nil
        if ma ~= mb then return ma end
        return a < b
    end)
    for _, p in ipairs(profs) do
        local section = byProf[p]
        -- the profession window's categories in its order; a recipe without one goes under Miscellaneous
        local catOf, catOrder, cats = {}, {}, 0
        for _, id in ipairs(section) do
            local name, rank = CS:Category(id)
            if not name or name == p or p == FAVORITES then name, rank = "Miscellaneous", nil end
            catOf[id] = name
            if not catOrder[name] then cats = cats + 1 end
            catOrder[name] = math.min(catOrder[name] or math.huge, rank or math.huge)
        end
        -- craftable now first, then by skill-up chance like the profession window, red (skill too low) last, then name
        local makeable, order = {}, {}
        for _, id in ipairs(section) do
            makeable[id] = CS:HasMaterials(id)
            order[id] = SKILL_ORDER[CS:Difficulty(id) or ""] or SKILL_ORDER.none
        end
        table.sort(section, function(a, b)
            local ca, cb = catOf[a], catOf[b]
            if ca ~= cb then
                if catOrder[ca] ~= catOrder[cb] then return catOrder[ca] < catOrder[cb] end
                return ca < cb
            end
            if makeable[a] ~= makeable[b] then return makeable[a] end
            if order[a] ~= order[b] then return order[a] < order[b] end
            return (CS.recipes[a].n or "") < (CS.recipes[b].n or "")
        end)
        list[#list + 1] = { header = true, key = p, text = p .. "  " .. GREY .. #section .. "|r" }
        local perCat = {}
        for _, id in ipairs(section) do perCat[catOf[id]] = (perCat[catOf[id]] or 0) + 1 end
        local shownCat
        for _, recipeID in ipairs(section) do
            first = first or recipeID
            local cat = catOf[recipeID]
            local catKey = p .. ": " .. cat
            if not collapsed[p] then
                if cats > 1 and cat ~= shownCat then
                    shownCat = cat
                    list[#list + 1] = { divider = true, key = catKey, text = cat .. "  " .. GREY .. perCat[cat] .. "|r" }
                end
                if cats < 2 or not collapsed[catKey] then list[#list + 1] = RecipeRow(recipeID, reagentID) end
            end
        end
        if not collapsed[p] then list[#list + 1] = { spacer = true } end
    end
    -- keep the selected recipe when it is still listed
    local keep = false
    for _, id in ipairs(ids or {}) do if id == selectedRecipe then keep = true end end
    if not keep then selectedRecipe = first end
    return list, #profs
end

local function ItemView(itemID)
    if not C_Item.GetItemNameByID(itemID) then C_Item.RequestLoadItemDataByID(itemID) end
    currentItem = itemID
    local uses = CS:GetUses(itemID)
    local list = ProfessionSections(uses, itemID)
    local n, nProfs, seen = uses and #uses or 0, 0, {}
    -- the heading counts every recipe, filtered out or not
    for _, id in ipairs(uses or {}) do
        local p = CS.recipes[id].p or "?"
        if not seen[p] then seen[p], nProfs = true, nProfs + 1 end
    end
    SetHeading(C_Item.GetItemIconByID(itemID), CS:ItemName(itemID) or ("item " .. itemID),
        n > 0 and ("Used in %d recipe%s across %d profession%s"):format(n, n == 1 and "" or "s", nProfs, nProfs == 1 and "" or "s")
            or (CS.usedIn[itemID] and "Only used in recipes the opposite faction learns" or "Not used in any recipe"), itemID)
    if #list == 0 then
        if n > 0 then return nil, FILTERED end
        return nil, CS.usedIn[itemID] and "Only used in recipes the opposite faction learns." or "No recipe uses this item."
    end
    return list
end

-- Right-click on an item: the recipes that make it
local function MadeView(itemID)
    if not C_Item.GetItemNameByID(itemID) then C_Item.RequestLoadItemDataByID(itemID) end
    currentItem, madeView = itemID, true
    local makers = CS:GetMakers(itemID)
    local list = ProfessionSections(makers)
    local n = makers and #makers or 0
    SetHeading(C_Item.GetItemIconByID(itemID), CS:ItemName(itemID) or ("item " .. itemID),
        n > 0 and ("Made by %d recipe%s"):format(n, n == 1 and "" or "s")
            or (CS.madeBy[itemID] and "Only made by the opposite faction" or "No recipe makes this"), itemID)
    if #list == 0 then
        if n > 0 then return nil, FILTERED end
        return nil, CS.madeBy[itemID] and "Only the opposite faction can make this." or "No recipe makes this item."
    end
    return list
end

local function BuildView(query)
    currentItem, madeView, picking, homeKeep = nil, false, false, false
    wipe(viewRecipes)
    if query == "" then return WelcomeView() end
    local made = tonumber(query:match("^made:(%d+)$"))
    if made then return MadeView(made) end
    local itemID = CS.ItemIDFromText(query)
    -- a crafted item that no recipe uses opens on the recipes that make it
    if itemID and not CS:GetUses(itemID) and CS:GetMakers(itemID) then return MadeView(itemID) end
    if itemID then return ItemView(itemID) end
    local hits, uses = CS:SearchReagentsByName(query)
    local recipes = CS:SearchRecipesByName(query)
    if #hits == 1 and #recipes == 0 then return ItemView(hits[1]) end
    picking = #recipes > 0
    return PickerView(hits, uses, recipes, query)
end

function Render(keepScroll)
    local list, message = BuildView(currentQuery)
    if not currentItem and not picking and not (keepScroll and homeKeep) then selectedRecipe = nil end
    scrollBox:SetDataProvider(CreateDataProvider(list or {}),
        keepScroll and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition)
    listEmpty:SetText(message or "")
    ShowDetail(keepScroll)
end

-- fromTyping: the search box already holds the text, so don't overwrite it mid-edit
function Browser:Show(query, fromTyping)
    if not f then Build() end
    f:Show()
    currentQuery = strtrim(query or "")
    if not fromTyping then
        -- show the item's name rather than item:123 or a raw link
        local itemID = CS.ItemIDFromText(currentQuery) or tonumber(currentQuery:match("^made:(%d+)$"))
        searchBox:SetText(itemID and CS:ItemName(itemID) or currentQuery)
    end
    Render(false)
end

function Browser:Toggle()
    if f and f:IsShown() then f:Hide() else self:Show("") end
end

-- Names and icons of uncached items arrive in bursts; only those the window showed without a name redraw it
function Browser:ItemInfoReceived(arrived)
    local missing, redraw = CS.missingNames, false
    for itemID in pairs(arrived or {}) do
        if missing[itemID] then
            missing[itemID] = nil
            redraw = true
        end
    end
    if redraw and f and f:IsShown() and currentQuery ~= "" then Render(true) end
end

-- Skill ranks or tracked recipes: redraw where the reader is
function Browser:ItemsChanged()
    if f and f:IsShown() then Render(true) end
end

-- Drop and gathering counts show only in the detail pane, so the list stays as it is
function Browser:CountsChanged()
    if f and f:IsShown() then ShowDetail(true) end
end

-- Reagent counts changed ({ [itemID] = true }, nil for everything): the list when a recipe it holds uses one, since it
-- sorts craftable recipes first and the materials filter reads the bags; else the pane when its recipe does
function Browser:BagsChanged(_, changed)
    if not (f and f:IsShown()) then return end
    if not changed or currentQuery == "" then return Render(true) end
    local list, pane = false, false
    for itemID in pairs(changed) do
        if itemID == currentItem then pane = true end
        for _, id in ipairs(CS.usedIn[itemID] or {}) do
            if viewRecipes[id] then list = true end
            if id == selectedRecipe then pane = true end
        end
    end
    if list then
        Render(true)
    elseif pane then
        ShowDetail(true)
    end
end

-- A profession was hidden or shown in the settings
function Browser:FilterChanged()
    if f and f:IsShown() then Render(true) end
end

-- One line under a crafting reagent's own tooltip; everything else stays in the window. Tooltips redraw while
-- hovered, so each count is kept for a few seconds.
local tipCounts = {}
local function ReagentLine(tooltip, data)
    if not CS.data.settings.tooltip or tooltip ~= GameTooltip or not data or CS.IsSecret(data.id) then return end
    local id = data.id
    if not id or not CS.usedIn[id] then return end
    -- only for items in the bags and the bank, where Alt+Click opens them
    local ok, inBags = pcall(function()
        local owner = tooltip:GetOwner()
        return owner and (owner.GetBankTabID ~= nil or (owner.GetBagID and owner:GetBagID() ~= nil)) or false
    end)
    if not (ok and inBags) then return end
    local hit = tipCounts[id]
    if not hit or GetTime() - hit.at > 10 then
        local uses = CS:GetUses(id)
        hit = { n = uses and #uses or 0, at = GetTime() }
        tipCounts[id] = hit
    end
    if hit.n == 0 then return end
    tooltip:AddLine(("%sUsed in %d recipe%s|r %s(Alt+Click)|r"):format("|cff66bbff", hit.n, hit.n == 1 and "" or "s",
        GREY), 1, 1, 1)
end

-- the window's own drawing, which the method profiling can't see
Render, ShowDetail, DrawDetail = CS.Profile("Browser Render", Render), CS.Profile("Browser ShowDetail", ShowDetail),
    CS.Profile("Browser DrawDetail", DrawDetail)

function Browser:OnEnable()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, CS.Profile("Browser ReagentLine", ReagentLine))
    end
    self:RegisterMessage("CRAFTSEEKER_ITEMS", "BagsChanged")
    self:RegisterBucketMessage("CRAFTSEEKER_FILTER", 0.2, "FilterChanged")
    self:RegisterEvent("TRACKED_RECIPE_UPDATE", "ItemsChanged")
    -- loot and shared counts come in bursts; one redraw every few seconds at most
    self:RegisterBucketMessage("CRAFTSEEKER_COUNTS", 3, "CountsChanged")
    self:RegisterBucketEvent("GET_ITEM_INFO_RECEIVED", 0.3, "ItemInfoReceived")
    -- Alt+Click any item (bags, bank, loot...) to look it up; Shift+Click drops it into a focused search box
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not link or CS.IsSecret(link) or not link:find("item:") then return end
        if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
            self:Show(link)
        elseif IsShiftKeyDown() and searchBox and searchBox:HasFocus() then
            searchBox:ClearFocus()
            self:Show(link)
        end
    end)
end
