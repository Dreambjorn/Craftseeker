-- Reagent Scout: recipe index and lookups
local _, RS = ...

RS.recipes = {} -- [recipeID] = decoded record: built-in data, overlaid by what profession windows reported
RS.usedIn = {}  -- [reagentItemID] = { recipeID, ... }
RS.madeBy = {}  -- [outputItemID] = { recipeID, ... }

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

function RS:IndexRecipe(recipeID, rec)
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

function RS:RebuildIndex()
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
end

function RS:SetRecipe(recipeID, rec)
    self.data.recipes[recipeID] = rec
    self.recipes[recipeID] = rec
    self:IndexRecipe(recipeID, rec)
end

function RS:CountRecipes()
    local n = 0
    for _ in pairs(self.recipes) do n = n + 1 end
    return n
end

-- How a recipe is learned, from the built-in data; nil when unknown
function RS:GetLearnInfo(recipeID)
    local s = self.BUILTIN_SOURCES and self.BUILTIN_SOURCES[recipeID]
    if not s then return nil end
    return {
        skill = s[1], how = s[2], cost = s[3], teach = s[4], favor = s[5], bound = s[6] == 1,
        side = s[7], vendors = s[8], quests = s[9], rep = s[10],
    }
end

-- Players' measured WoW Forever drop rates for a recipe item: { { npc, name, chance %, kills }, ... }, best first
function RS:GetDropRates(itemID)
    local r = self.BUILTIN_RATES and self.BUILTIN_RATES[itemID]
    if not r then return nil end
    local out = {}
    for i = 1, #r, 4 do
        out[#out + 1] = { npc = r[i], name = r[i + 1], chance = r[i + 2] / 100, kills = r[i + 3] }
    end
    return out
end

function RS.PlayerFaction()
    return FACTION_CODE[UnitFactionGroup("player")] or 0
end

-- True when the entry (faction code 0 = both) is open to this character
local function ForMe(faction, mine)
    return faction == 0 or faction == mine
end

-- False for recipes only the other faction can learn
function RS:IsObtainable(recipeID)
    local info = self:GetLearnInfo(recipeID)
    if not info then return true end
    local mine = self.PlayerFaction()
    if not ForMe(info.side, mine) then return false end
    -- vendors and quests are the only faction-bound ways to learn a recipe
    if info.how:find("[tdwca]") or info.how == "" then return true end
    for i = 2, #info.vendors, 2 do
        if ForMe(info.vendors[i], mine) then return true end
    end
    for i = 2, #info.quests, 3 do
        if ForMe(info.quests[i], mine) then return true end
    end
    return false
end
RS.ForMe = ForMe

function RS:ItemName(itemID)
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return C_Item.GetItemNameByID(itemID) or (baked and baked[1])
end

-- Built-in quality first: the client's answer arrives late for uncached items
function RS:ItemQuality(itemID)
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return (baked and baked[2]) or C_Item.GetItemQualityByID(itemID)
end

-- Who knows a recipe? returns "me", "alt" (with name), or nil
function RS:WhoKnows(recipeID)
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

-- Recipe IDs that use an item and this character can get: known first, then alts, then by profession and name
function RS:GetUses(itemID)
    local list = self.usedIn[itemID]
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

function RS.ReagentQty(rec, itemID)
    for _, r in ipairs(rec.r or {}) do
        if r[1] == itemID then return r[2], r[3] end
    end
end

function RS.ItemIDFromText(text)
    if not text or text == "" then return nil end
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    if text:match("^%d+$") then return tonumber(text) end
    return nil
end

-- Reagent itemIDs whose name contains the search text and that this character can use
function RS:SearchReagentsByName(text)
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
