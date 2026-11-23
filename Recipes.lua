-- Craftseeker: recipe index and lookups
local _, CS = ...

CS.recipes = {} -- [recipeID] = decoded record: built-in data, overlaid by what profession windows reported
CS.usedIn = {}  -- [reagentItemID] = { recipeID, ... }
CS.madeBy = {}  -- [outputItemID] = { recipeID, ... }

local FACTION_CODE = { Alliance = 1, Horde = 2 }

local function AddIndex(index, key, recipeID)
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    for i = 1, #list do
        if list[i] == recipeID then return end
    end
    list[#list + 1] = recipeID
end

function CS:IndexRecipe(recipeID, rec)
    for _, r in ipairs(rec.r or {}) do
        AddIndex(self.usedIn, r[1], recipeID)
    end
    if rec.o then
        AddIndex(self.madeBy, rec.o, recipeID)
    end
end

local function Decode(d)
    local r = {}
    local list = d[5]
    for i = 1, #list, 2 do r[#r + 1] = { list[i], list[i + 1] } end
    return { n = d[1], p = d[2], o = d[3], q = d[4], r = r }
end

function CS:RebuildIndex()
    wipe(self.usedIn)
    wipe(self.madeBy)
    wipe(self.recipes)
    local verified = self.data.verified
    for recipeID, d in pairs(self.BUILTIN or {}) do
        -- a scanned window lists every recipe its profession has here
        local seen = verified[d[2]]
        if not seen or seen[recipeID] then
            self.recipes[recipeID] = Decode(d)
        end
    end
    for recipeID, rec in pairs(self.data.recipes) do
        self.recipes[recipeID] = rec
    end
    for recipeID, rec in pairs(self.recipes) do
        self:IndexRecipe(recipeID, rec)
    end
    self.recipeItems = {}
    for _, s in pairs(self.BUILTIN_SOURCES or {}) do
        if s[4] > 0 then self.recipeItems[s[4]] = true end
    end
end

function CS:SetRecipe(recipeID, rec)
    self.data.recipes[recipeID] = rec
    self.recipes[recipeID] = rec
    self:IndexRecipe(recipeID, rec)
end

function CS:CountRecipes()
    local n = 0
    for _ in pairs(self.recipes) do n = n + 1 end
    return n
end

-- How a recipe is learned, from the built-in data; nil when unknown
function CS:GetLearnInfo(recipeID)
    local s = self.BUILTIN_SOURCES and self.BUILTIN_SOURCES[recipeID]
    if not s then return nil end
    return {
        skill = s[1], how = s[2], cost = s[3], teach = s[4], favor = s[5], bound = s[6] == 1,
        side = s[7], vendors = s[8], quests = s[9], rep = s[10],
    }
end

-- Players' measured WoW Forever drop rates for a recipe item: { { npc, name, chance %, kills }, ... }, best first
-- Drop rates for an item: the built-in WoW Forever counts plus this account's own loot counts.
-- { { npc, name, chance %, kills }, ... }, best first; nil when nobody has seen it drop
function CS:GetDropRates(itemID)
    local byNpc, out = {}, {}
    local r = self.BUILTIN_RATES and self.BUILTIN_RATES[itemID]
    for i = 1, r and #r or 0, 4 do
        local entry = { npc = r[i], name = r[i + 1], drops = r[i + 2] / 10000 * r[i + 3], kills = r[i + 3] }
        byNpc[r[i]] = entry
        out[#out + 1] = entry
    end
    -- own and shared counts: every opened corpse of a creature counts, also those without the item
    local function Add(counts, own)
        for npc, c in pairs(counts) do
            local drops = c.items and c.items[itemID] or 0
            local entry = byNpc[npc]
            if drops > 0 and not entry then
                entry = { npc = npc, name = c.name or "", drops = 0, kills = 0 }
                byNpc[npc] = entry
                out[#out + 1] = entry
            end
            if entry then
                entry.drops, entry.kills = entry.drops + drops, entry.kills + (c.opened or 0)
                if own then entry.own = (entry.own or 0) + (c.opened or 0) end
            end
        end
    end
    Add(self.data.counts, true)
    for _, peer in pairs(self.data.shared) do Add(peer.counts or {}, false) end
    if #out == 0 then return nil end
    for _, e in ipairs(out) do
        e.chance = e.kills > 0 and e.drops / e.kills * 100 or 0
        if e.name == "" then e.name = self:NpcName(e.npc) or ("NPC " .. e.npc) end
    end
    table.sort(out, function(a, b) return a.chance > b.chance end)
    return out
end

function CS.PlayerFaction()
    return FACTION_CODE[UnitFactionGroup("player")] or 0
end

-- True when the entry (faction code 0 = both or unknown) is open to this character
local function ForMe(faction, mine)
    return faction == 0 or faction == mine
end
CS.ForMe = ForMe

local function MapName(uiMap)
    local info = uiMap and uiMap > 0 and C_Map.GetMapInfo(uiMap)
    return info and info.name or nil
end

-- Trainers or vendors players saw, this character's faction only: { npc, name, zone, copper[, stack] }
local function SeenNpcs(list, width)
    if not list then return nil end
    local mine, out = CS.PlayerFaction(), {}
    for i = 1, #list, width do
        if ForMe(list[i + 2], mine) then
            out[#out + 1] = { npc = list[i], name = list[i + 1], zone = MapName(list[i + 3]),
                copper = list[i + 4], stack = width == 6 and list[i + 5] or nil }
        end
    end
    return #out > 0 and out or nil
end

-- Where a creature is, from the built-in data: zone names, or an instance name
function CS:GetPlaces(npcID)
    local p = self.BUILTIN_PLACES and self.BUILTIN_PLACES[npcID]
    if type(p) == "string" then return { p } end
    local out = {}
    for _, uiMap in ipairs(p or {}) do out[#out + 1] = MapName(uiMap) end
    return out
end

-- Quests that teach a recipe, this character's faction only: { quest, name, giver, zone, level }
function CS:GetRecipeQuests(recipeID)
    local q = self.BUILTIN_QUESTS and self.BUILTIN_QUESTS[recipeID]
    if not q then return nil end
    local mine, out = self.PlayerFaction(), {}
    for i = 1, #q, 6 do
        if ForMe(q[i + 4], mine) then
            out[#out + 1] = { quest = q[i], name = q[i + 1] ~= "" and q[i + 1] or ("Quest " .. q[i]),
                giver = q[i + 2] ~= "" and q[i + 2] or nil, zone = MapName(q[i + 3]), level = q[i + 5] > 0 and q[i + 5] or nil }
        end
    end
    return #out > 0 and out or nil
end

function CS:GetTrainers(recipeID)
    return SeenNpcs(self.BUILTIN_TRAINERS and self.BUILTIN_TRAINERS[recipeID], 5)
end

function CS:GetVendors(itemID)
    return SeenNpcs(self.BUILTIN_VENDORS and self.BUILTIN_VENDORS[itemID], 6)
end

-- False for recipes only the opposite faction can learn; the factions can't trade with each other.
function CS:IsObtainable(recipeID)
    local info = self:GetLearnInfo(recipeID)
    if not info then return true end
    local mine = self.PlayerFaction()
    if not ForMe(info.side, mine) then return false end
    -- vendors and quests are the only faction-bound ways to learn a recipe
    if info.how:find("[tdwca]") or info.how == "" then return true end
    local seen = info.teach > 0 and self.BUILTIN_VENDORS and self.BUILTIN_VENDORS[info.teach]
    for i = 3, seen and #seen or 0, 6 do
        if ForMe(seen[i], mine) then return true end
    end
    for i = 2, #info.vendors, 2 do
        if ForMe(info.vendors[i], mine) then return true end
    end
    for i = 2, #info.quests, 3 do
        if ForMe(info.quests[i], mine) then return true end
    end
    return false
end

function CS:ItemName(itemID)
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return C_Item.GetItemNameByID(itemID) or (baked and baked[1])
end

-- Built-in quality first: the client's answer arrives late for uncached items
function CS:ItemQuality(itemID)
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return (baked and baked[2]) or C_Item.GetItemQualityByID(itemID)
end

-- Who knows a recipe? returns "me", "alt" (with name), or nil
function CS:WhoKnows(recipeID)
    local me = self.CharKey()
    local known = self.data.known
    if rawget(known, me) and known[me][recipeID] then return "me" end
    for char, list in pairs(known) do
        if char ~= me and list[recipeID] then
            return "alt", (char:match("^[^-]+") or char)
        end
    end
    return nil
end

-- The recipes of a list this character can get: known first, then alts, then by profession and name
local function Obtainable(self, list)
    if not list then return nil end
    local out, rankOf = {}, {}
    local rank = { me = 0, alt = 1 }
    for i = 1, #list do
        local id = list[i]
        local who = self:WhoKnows(id)
        if who == "me" or self:IsObtainable(id) then
            out[#out + 1] = id
            rankOf[id] = rank[who or ""] or 2
        end
    end
    if #out == 0 then return nil end
    local recipes = self.recipes
    table.sort(out, function(a, b)
        local ra, rb = rankOf[a], rankOf[b]
        if ra ~= rb then return ra < rb end
        local A, B = recipes[a], recipes[b]
        if A.p ~= B.p then return (A.p or "") < (B.p or "") end
        return (A.n or "") < (B.n or "")
    end)
    return out
end

function CS:GetUses(itemID)
    return Obtainable(self, self.usedIn[itemID])
end

function CS:GetMakers(itemID)
    return Obtainable(self, self.madeBy[itemID])
end

function CS.ReagentQty(rec, itemID)
    for _, r in ipairs(rec.r or {}) do
        if r[1] == itemID then return r[2], r[3] end
    end
end

function CS.ItemIDFromText(text)
    if not text or text == "" then return nil end
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    if text:match("^%d+$") then return tonumber(text) end
    return nil
end

-- Reagent itemIDs whose name contains the search text and that this character can use
function CS:SearchReagentsByName(text)
    text = text:lower()
    local hits, names = {}, {}
    for itemID in pairs(self.usedIn) do
        local name = self:ItemName(itemID)
        if not name then
            C_Item.RequestLoadItemDataByID(itemID)
        elseif name:lower():find(text, 1, true) and self:GetUses(itemID) then
            hits[#hits + 1] = itemID
            names[itemID] = name
        end
    end
    table.sort(hits, function(a, b) return names[a] < names[b] end)
    return hits
end
