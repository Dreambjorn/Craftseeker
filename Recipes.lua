-- Craftseeker: recipe index and lookups
local _, CS = ...

CS.recipes = {} -- [recipeID] = decoded record: built-in data, overlaid by what profession windows reported
CS.usedIn = {}  -- [reagentItemID] = { recipeID, ... }
CS.madeBy = {}  -- [outputItemID] = { recipeID, ... }

local FACTION_CODE = { Alliance = 1, Horde = 2 }
local lowerNames = {} -- [itemID] or ["r" .. recipeID] = lower-case name, for search

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
    -- a built-in record indexes from its flat list, so its reagent tables are only made when something reads them
    local flat = rawget(rec, "rl")
    if flat then
        for i = 1, #flat, 2 do AddIndex(self.usedIn, flat[i], recipeID) end
    else
        for _, r in ipairs(rec.r or {}) do AddIndex(self.usedIn, r[1], recipeID) end
    end
    if rec.o then
        AddIndex(self.madeBy, rec.o, recipeID)
    end
end

-- Built-in records decode their reagents ({ { itemID, qty }, ... }) on first use; most are never shown in a session
local LAZY = { __index = function(rec, key)
    if key ~= "r" then return nil end
    local r, list = {}, rawget(rec, "rl")
    for i = 1, #list, 2 do r[#r + 1] = { list[i], list[i + 1] } end
    rawset(rec, "r", r)
    return r
end }

local function Decode(d)
    return setmetatable({ n = d[1], p = d[2], o = d[3], q = d[4], rl = d[5] }, LAZY)
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

-- A window's recipe the built-in data already holds as is: no need to save a copy
function CS:SameAsBuiltin(recipeID, rec)
    local d = self.BUILTIN and self.BUILTIN[recipeID]
    if not d or d[1] ~= rec.n or d[2] ~= rec.p or d[3] ~= rec.o or d[4] ~= (rec.q or 1) or #d[5] ~= 2 * #(rec.r or {}) then
        return false
    end
    for i, r in ipairs(rec.r) do
        if r[3] or d[5][2 * i - 1] ~= r[1] or d[5][2 * i] ~= r[2] then return false end
    end
    return true
end

-- Window scans used to save every recipe; copies of built-in ones are dropped at login, the rest stay
function CS:DropBuiltinCopies()
    for id, rec in pairs(self.data.recipes) do
        if self:SameAsBuiltin(id, rec) then self.data.recipes[id] = nil end
    end
end

function CS:SetRecipe(recipeID, rec)
    lowerNames["r" .. recipeID] = nil
    self.data.recipes[recipeID] = rec
    self.recipes[recipeID] = rec
    self:IndexRecipe(recipeID, rec)
end

-- On Forever for sure: in the built-in data (every entry has proof), or a character has learned it
function CS:IsProven(recipeID)
    return (self.BUILTIN and self.BUILTIN[recipeID]) or self.data.proven[recipeID] or self:WhoKnows(recipeID) ~= nil
end

function CS:CountRecipes()
    local n = 0
    for id in pairs(self.recipes) do
        if self:IsProven(id) then n = n + 1 end
    end
    return n
end

-- How a recipe is learned, from the built-in data; nil when unknown. Decoded once: list filters ask per recipe.
local learnCache = {}
function CS:GetLearnInfo(recipeID)
    local info = learnCache[recipeID]
    if info ~= nil then return info or nil end
    local s = self.BUILTIN_SOURCES and self.BUILTIN_SOURCES[recipeID]
    info = s and {
        skill = s[1], how = s[2], cost = s[3], teach = s[4], favor = s[5], bound = s[6] == 1,
        side = s[7], vendors = s[8], quests = s[9], rep = s[10],
    } or false
    learnCache[recipeID] = info
    return info or nil
end

-- Counts other than the built-in ones, summed per creature, with the creatures each item dropped from; rebuilt only
-- after new counts arrive, so a lookup touches just the creatures that matter to the item. Our own loot is kept
-- apart: it changes every corpse, and rebuilding everyone else's counts each time cost 17 ms and 10 MB of garbage.
--   totals[npc] = { opened, own, name, items = { [itemID] = drops } }   Craftseeker and Forever Drops users
--   ownTotals, ownFrom: the same for this account's loot
--   dtTotals[npc] = { kills, lootable, opened, items = { [itemID] = drops } }   Drop Tables users
--   dropsFrom[itemID] = { [npc] = true }, from other players' counts
local totals, dtTotals, dropsFrom, builtFor
local ownTotals, ownFrom, ownBuiltFor

local AceEvent = LibStub("AceEvent-3.0")

-- own: only this account's loot changed
function CS:CountsChanged(own)
    self.countsVersion = (self.countsVersion or 0) + 1
    if not own then self.othersVersion = (self.othersVersion or 0) + 1 end
    AceEvent:SendMessage("CRAFTSEEKER_COUNTS")
end

local function Total(t, npc)
    local e = t[npc]
    if not e then
        e = { opened = 0, own = 0, items = {} }
        t[npc] = e
    end
    return e
end

local function AddCounts(into, from, counts, own)
    for npc, c in pairs(counts) do
        local e = Total(into, npc)
        e.opened = e.opened + (c.opened or 0)
        if own then e.own = e.own + (c.opened or 0) end
        e.name = e.name or c.name
        for item, drops in pairs(c.items or {}) do
            e.items[item] = (e.items[item] or 0) + drops
            from[item] = from[item] or {}
            from[item][npc] = true
        end
    end
end

function CS:BuildTotals()
    if ownBuiltFor ~= self.countsVersion or not ownTotals then
        ownBuiltFor = self.countsVersion
        ownTotals, ownFrom = {}, {}
        AddCounts(ownTotals, ownFrom, self.data.counts, true)
    end
    if builtFor == (self.othersVersion or 0) and totals then return end
    builtFor = self.othersVersion or 0
    totals, dtTotals, dropsFrom = {}, {}, {}
    for _, peer in pairs(self.data.shared) do AddCounts(totals, dropsFrom, peer.counts or {}, false) end
    -- Forever Drops records hold k corpses and i items; read in place, no copy per peer
    for _, peer in pairs(self.data.bridges.fd) do
        for npc, rec in pairs(peer.npcs) do
            local e = Total(totals, npc)
            e.opened = e.opened + (rec.k or 0)
            for item, drops in pairs(rec.i or {}) do
                e.items[item] = (e.items[item] or 0) + drops
                dropsFrom[item] = dropsFrom[item] or {}
                dropsFrom[item][npc] = true
            end
        end
    end
    for npc, origins in pairs(self.data.bridges.dt) do
        local t = { kills = 0, lootable = 0, opened = 0, items = {} }
        for _, o in pairs(origins) do
            for bucket, m in pairs(o.b) do
                t.kills, t.lootable, t.opened = t.kills + m[1], t.lootable + m[2], t.opened + m[3]
                for item, drops in pairs(o.i[bucket] or {}) do
                    t.items[item] = (t.items[item] or 0) + drops
                    dropsFrom[item] = dropsFrom[item] or {}
                    dropsFrom[item][npc] = true
                end
            end
        end
        dtTotals[npc] = t
    end
end

-- Drop rates for an item: the built-in counts, Drop Tables users' live counts when they have more kills, this
-- account's own loot, other Craftseeker users' and Forever Drops users' counts.
-- { { npc, name, chance %, kills }, ... }, best first; nil when nobody has seen it drop
function CS:GetDropRates(itemID)
    self:BuildTotals()
    local byNpc, out = {}, {}
    local function Entry(npc, name)
        local e = byNpc[npc]
        if not e then
            e = { npc = npc, name = name or "", drops = 0, kills = 0 }
            byNpc[npc] = e
            out[#out + 1] = e
        end
        return e
    end
    local r = self.BUILTIN_RATES and self.BUILTIN_RATES[itemID]
    for i = 1, r and #r or 0, 4 do
        local e = Entry(r[i], r[i + 1])
        e.drops, e.kills = r[i + 2] / 10000 * r[i + 3], r[i + 3]
    end
    -- built-in rates measured by Craftseeker users already hold their counts: live counts replace them, never add
    local measured = {}
    for _, npc in ipairs(self.BUILTIN_OWN_RATES and self.BUILTIN_OWN_RATES[itemID] or {}) do measured[npc] = true end
    for npc in pairs(dropsFrom[itemID] or {}) do Entry(npc, totals[npc] and totals[npc].name) end
    for npc in pairs(ownFrom[itemID] or {}) do Entry(npc, ownTotals[npc].name) end
    for _, e in ipairs(out) do
        -- Drop Tables' shared database is in the built-in counts, so its users' live counts replace them, never add
        local dt = dtTotals[e.npc]
        if dt and dt.opened > 0 and dt.kills > e.kills then
            e.drops, e.kills = (dt.items[itemID] or 0) / dt.opened * dt.lootable, dt.kills
        end
        -- every opened corpse counts, also those without the item
        local t, own = totals[e.npc], ownTotals[e.npc]
        if measured[e.npc] then
            local drops = (t and t.items[itemID] or 0) + (own and own.items[itemID] or 0)
            local kills = (t and t.opened or 0) + (own and own.opened or 0)
            if kills > e.kills then e.drops, e.kills = drops, kills end
        else
            if t then e.drops, e.kills = e.drops + (t.items[itemID] or 0), e.kills + t.opened end
            if own then e.drops, e.kills = e.drops + (own.items[itemID] or 0), e.kills + own.opened end
        end
        if own and own.own > 0 then e.own = own.own end
    end
    for i = #out, 1, -1 do
        if out[i].kills <= 0 then table.remove(out, i) end
    end
    if #out == 0 then return nil end
    for _, e in ipairs(out) do
        e.chance = e.drops / e.kills * 100
        if e.name == "" then e.name = self:NpcName(e.npc) or self:SeenNpcName(e.npc) or ("NPC " .. e.npc) end
    end
    table.sort(out, function(a, b) return a.chance > b.chance end)
    return out
end

-- Gathering counts (skinning, mining and herb gathering corpses; nodes and chests) from this account, other
-- Craftseeker users, Drop Tables users' skinning and Forever Drops users, summed per source and indexed by item.
-- Rebuilt only after new counts; a lookup touches just the sources of the item.
--   index[itemID] = { [key] = { kind = "k"/"g", id, p, n, k = times, drops, own } }; ours apart, like the drops
local othersGather, othersBuiltFor, ownGather, ownGatherFor
local measuredGather -- [itemID] = { [key] = built-in entry Craftseeker users measured }, kept apart from the live counts
local GATHER_PROF = { "Skinning", "Mining", "Herbalism", "Chest" }

local function AddGather(index, kind, id, e, own)
    if not e or not e.k or e.k <= 0 then return end
    local key = kind .. id
    for item, drops in pairs(e.i or {}) do
        local byKey = index[item]
        if not byKey then
            byKey = {}
            index[item] = byKey
        end
        local t = byKey[key]
        if not t then
            t = { kind = kind, id = id, k = 0, drops = 0, own = 0 }
            byKey[key] = t
        end
        t.k, t.drops = t.k + e.k, t.drops + drops
        t.p, t.n = t.p or e.p, t.n or e.n
        if own then t.own = t.own + e.k end
    end
end

local function BuildGather(self)
    if ownGatherFor ~= self.countsVersion or not ownGather then
        ownGatherFor, ownGather = self.countsVersion, {}
        for kind, book in pairs(self.data.gather) do
            for id, e in pairs(book) do AddGather(ownGather, kind, id, e, true) end
        end
    end
    if othersBuiltFor == (self.othersVersion or 0) and othersGather then return end
    othersBuiltFor, othersGather = self.othersVersion or 0, {}
    for _, peer in pairs(self.data.shared) do
        for kind, book in pairs(peer.gather or {}) do
            for id, e in pairs(book) do AddGather(othersGather, kind, id, e, false) end
        end
    end
    -- built-in counts (Drop Tables' skinning database, Polestar's nodes and chests); Drop Tables users' live skinning
    -- replaces a creature's built-in figure once it holds more skins, never adds: the database holds the same installs
    local live, liveItems, builtin = {}, {}, {}
    for npc, origins in pairs(self.data.bridges.dtSkins or {}) do
        liveItems[npc] = {}
        for _, e in pairs(origins) do
            live[npc] = (live[npc] or 0) + e.k
            for item in pairs(e.i or {}) do liveItems[npc][item] = true end
        end
    end
    local gathered = self.BUILTIN_GATHER or {}
    for _, list in pairs(gathered) do
        for i = 1, #list, 5 do
            if list[i] == 1 then builtin[list[i + 1]] = math.max(builtin[list[i + 1]] or 0, list[i + 4]) end
        end
    end
    local measured = {}
    for item, ids in pairs(self.BUILTIN_OWN_GATHER or {}) do
        measured[item] = {}
        for i = 1, #ids, 2 do measured[item][(ids[i] == 1 and "k" or "g") .. ids[i + 1]] = true end
    end
    measuredGather = {}
    for item, list in pairs(gathered) do
        for i = 1, #list, 5 do
            local kind, id, times = list[i], list[i + 1], list[i + 4]
            local key = (kind == 1 and "k" or "g") .. id
            local e = { p = GATHER_PROF[list[i + 2]], k = times, i = { [item] = list[i + 3] / 10000 * times } }
            -- live counts replace an item's built-in figure only when they hold that item; otherwise it stays
            local replaced = kind == 1 and (live[id] or 0) > builtin[id] and liveItems[id][item]
            if measured[item] and measured[item][key] then
                AddGather(measuredGather, kind == 1 and "k" or "g", id, e, false)
            elseif not replaced then
                AddGather(othersGather, kind == 1 and "k" or "g", id, e, false)
            end
        end
    end
    for npc, origins in pairs(self.data.bridges.dtSkins or {}) do
        if not builtin[npc] or live[npc] > builtin[npc] then
            for _, e in pairs(origins) do AddGather(othersGather, "k", npc, e, false) end
        end
    end
    for _, peer in pairs(self.data.bridges.fd) do
        for kind, book in pairs(peer.gather or {}) do
            for id, e in pairs(book) do AddGather(othersGather, kind, id, e, false) end
        end
    end
end

-- Where an item is gathered: { { kind, id, p = profession, n = name, k = times, drops, chance %, own }, ... }, best first
function CS:GetGatherRates(itemID)
    BuildGather(self)
    local merged = {}
    for _, index in ipairs({ othersGather, ownGather }) do
        for key, t in pairs(index[itemID] or {}) do
            local m = merged[key]
            if not m then
                m = { kind = t.kind, id = t.id, p = t.p, n = t.n, k = 0, drops = 0, own = 0 }
                merged[key] = m
            end
            m.k, m.drops, m.own = m.k + t.k, m.drops + t.drops, m.own + t.own
            m.p, m.n = m.p or t.p, m.n or t.n
        end
    end
    -- built-in figures Craftseeker users measured already hold their windows: the bigger of them and the live counts
    for key, b in pairs(measuredGather[itemID] or {}) do
        local m = merged[key]
        if not m or m.k < b.k then
            merged[key] = { kind = b.kind, id = b.id, p = b.p or (m and m.p), n = b.n or (m and m.n), k = b.k,
                drops = b.drops, own = m and m.own or 0 }
        end
    end
    local out = {}
    for _, m in pairs(merged) do
        m.chance = math.min(m.drops / m.k, 1) * 100
        out[#out + 1] = m
    end
    if #out == 0 then return nil end
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
                copper = list[i + 4], stack = width == 6 and list[i + 5] or nil, pin = CS:GetPin(list[i]) }
        end
    end
    return #out > 0 and out or nil
end

-- Where an NPC stands, for a map pin: { uiMap, x, y } with x and y from 0 to 1, or nil
function CS:GetPin(npcID)
    local p = npcID and self.BUILTIN_PINS and self.BUILTIN_PINS[npcID]
    if p then return { p[1], p[2] / 1000, p[3] / 1000 } end
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
    for i = 1, #q, 7 do
        if ForMe(q[i + 4], mine) then
            out[#out + 1] = { quest = q[i], name = q[i + 1] ~= "" and q[i + 1] or ("Quest " .. q[i]),
                giver = q[i + 2] ~= "" and q[i + 2] or nil, zone = MapName(q[i + 3]), level = q[i + 5] > 0 and q[i + 5] or nil,
                pin = self:GetPin(q[i + 6]) }
        end
    end
    return #out > 0 and out or nil
end

function CS:GetTrainers(recipeID)
    return SeenNpcs(self.BUILTIN_TRAINERS and self.BUILTIN_TRAINERS[recipeID], 5)
end

-- Creatures whose blanks we fill: drop sources, our own loot of counted items, built-in vendors and trainers
function CS:IsSourceNpc(npc)
    if not self.sourceNpcs then
        local set = {}
        for _, list in pairs(self.BUILTIN_VENDORS or {}) do
            for i = 1, #list, 6 do set[list[i]] = true end
        end
        for _, list in pairs(self.BUILTIN_TRAINERS or {}) do
            for i = 1, #list, 5 do set[list[i]] = true end
        end
        self.sourceNpcs = set
    end
    return self.sourceNpcs[npc] or self:IsRelevantNpc(npc) or self.data.npcs[npc] ~= nil
end

local SEEN_RANK = { "Elite", "Rare Elite", "Boss", "Rare" }

-- What we and other Craftseeker users saw of a creature: name, "lo-hi" level, zones (most seen first), pin
function CS:SeenNpc(npc)
    local own = self.data.npcs[npc]
    local name, lo, hi, pin, times = own and own.n, own and own.lo, own and own.hi, own and own.p, {}
    local rank, faction = own and own.r, own and own.f
    for zone, n in pairs(own and own.z or {}) do times[zone] = n end
    for _, peer in pairs(self.data.shared) do
        local e = peer.npcs and peer.npcs[npc]
        if e then
            name, pin, rank, faction = name or e.n, pin or e.p, rank or e.r, faction or e.f
            if e.lo and (not lo or e.lo < lo) then lo = e.lo end
            if e.hi and (not hi or e.hi > hi) then hi = e.hi end
            for zone, n in pairs(e.z or {}) do times[zone] = (times[zone] or 0) + n end
        end
    end
    local zones = {}
    for zone in pairs(times) do zones[#zones + 1] = zone end
    table.sort(zones, function(a, b) return times[a] > times[b] end)
    local level = lo and (hi and hi > lo and (lo .. "-" .. hi) or tostring(lo)) or nil
    return { name = name, level = level, zones = zones, pin = pin and { pin[1], pin[2] / 1000, pin[3] / 1000 },
        rank = SEEN_RANK[rank or 0], faction = faction }
end

function CS:SeenNpcName(npc)
    return npc and self:SeenNpc(npc).name or nil
end

-- Quests that players saw offering an item as a reward, for this character's faction (the opposite faction's too with
-- "Show opposite faction" on): { { name, giver, zone, pin, opposite }, ... }
function CS:SeenQuests(itemID)
    local mine = self.PlayerFaction() == 2 and 2 or 1
    local both = self.data.settings.opposite
    local out, seen = {}, {}
    local function Take(id, q)
        local ours = q.s == mine or q.s == 3
        if seen[id] or not q.n or not q.i[itemID] or not (ours or both) then return end
        seen[id] = true
        local who = q.g and self:SeenNpc(q.g)
        local zones = q.g and self:GetPlaces(q.g) or {}
        out[#out + 1] = { name = q.n, giver = q.g and (self:NpcName(q.g) or who.name),
            zone = zones[1] or (who and who.zones[1]), pin = q.g and (self:GetPin(q.g) or who.pin), opposite = not ours }
    end
    for id, q in pairs(self.data.quests) do Take(id, q) end
    for _, peer in pairs(self.data.shared) do
        for id, q in pairs(peer.quests or {}) do Take(id, q) end
    end
    return out
end

-- Where we or another Craftseeker user stood looting an object
function CS:SeenObjectPin(objectID)
    local p = self.data.objectPins[objectID]
    if not p then
        for _, peer in pairs(self.data.shared) do
            p = peer.objectPins and peer.objectPins[objectID]
            if p then break end
        end
    end
    return p and { p[1], p[2] / 1000, p[3] / 1000 } or nil
end

-- Zones an object was looted in, by us and other Craftseeker users, most loots first
function CS:SeenObjectZones(objectID)
    local times = {}
    for zone, n in pairs(self.data.objects[objectID] or {}) do times[zone] = n end
    for _, peer in pairs(self.data.shared) do
        for zone, n in pairs(peer.objects and peer.objects[objectID] or {}) do times[zone] = (times[zone] or 0) + n end
    end
    local out = {}
    for zone in pairs(times) do out[#out + 1] = zone end
    table.sort(out, function(a, b) return times[a] > times[b] end)
    return out
end

-- Vendor prices players saw for an item: [npc] = { copper per stack, stack, name? }, ours over other users', and ours
function CS:SeenPrices(itemID)
    local own = self.data.prices[itemID] or {}
    local out = {}
    for npc, p in pairs(own) do out[npc] = p end
    for _, peer in pairs(self.data.shared) do
        for npc, p in pairs(peer.prices and peer.prices[itemID] or {}) do out[npc] = out[npc] or p end
    end
    return out, own
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

CS.missingNames = {} -- [itemID] = true: shown before the client had its name

function CS:ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if name then return name end
    self.missingNames[itemID] = true
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return baked and baked[1]
end

local function Lower(key, name)
    if not name then return nil end
    local l = lowerNames[key]
    if not l then
        l = name:lower()
        lowerNames[key] = l
    end
    return l
end

-- Built-in quality first: the client's answer arrives late for uncached items
function CS:ItemQuality(itemID)
    local baked = self.BUILTIN_ITEMS and self.BUILTIN_ITEMS[itemID]
    return (baked and baked[2]) or C_Item.GetItemQualityByID(itemID)
end

function CS:KnownChanged()
    self.knownBy = nil
end

-- Who knows a recipe? returns "me", "alt" (with name), or nil. One pass over every character, kept until a window
-- scan changes what they know.
function CS:WhoKnows(recipeID)
    local by = self.knownBy
    if not by then
        local me = self.CharKey()
        by = {}
        for char, list in pairs(self.data.known) do
            if char ~= me then
                for id in pairs(list) do by[id] = by[id] or (char:match("^[^-]+") or char) end
            end
        end
        for id in pairs(rawget(self.data.known, me) or {}) do by[id] = true end
        self.knownBy = by
    end
    local v = by[recipeID]
    if v == true then return "me" end
    if v then return "alt", v end
    return nil
end

-- The other characters on this account who know a recipe, by name
function CS:AltsKnowing(recipeID)
    local me, out = self.CharKey(), {}
    for char, list in pairs(self.data.known) do
        if char ~= me and list[recipeID] then out[#out + 1] = char:match("^[^-]+") or char end
    end
    table.sort(out)
    return out
end

-- Listed when this character knows it or can get it, and its profession isn't hidden in the settings
function CS:Shown(recipeID, who)
    local rec = self.recipes[recipeID]
    if not rec or self.data.settings.hidden[rec.p or "?"] or not self:IsProven(recipeID) then return false end
    return (who or self:WhoKnows(recipeID)) == "me" or self.data.settings.opposite or self:IsObtainable(recipeID)
end

-- Favourites are ours, for any recipe and every character; tracking is the game's own objective tracker
function CS:IsFavorite(recipeID)
    return self.data.favorites[recipeID] == true
end

function CS:SetFavorite(recipeID, on)
    self.data.favorites[recipeID] = on or nil
end

-- Class spells and reagent-free recipes have nothing to track
function CS:CanTrack(recipeID)
    local rec = self.recipes[recipeID]
    return rec ~= nil and rec.r ~= nil and #rec.r > 0 and not (self.BUILTIN_CLASS and self.BUILTIN_CLASS[recipeID])
        and C_TradeSkillUI ~= nil and C_TradeSkillUI.SetRecipeTracked ~= nil
end

function CS:IsTracked(recipeID)
    local ok, tracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, false)
    return ok and tracked == true
end

function CS:SetTracked(recipeID, on)
    return (pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, on, false))
end

function CS:TrackedRecipes()
    local ok, list = pcall(C_TradeSkillUI.GetRecipesTracked, false)
    return ok and type(list) == "table" and list or {}
end

-- The profession window's category of a recipe (Bags, Cloaks, ...): its name and order there
function CS:Category(recipeID)
    local id = self.BUILTIN_CATEGORY and self.BUILTIN_CATEGORY[recipeID]
    local c = id and self.BUILTIN_CATEGORIES[id]
    if c then return c[1], c[2] end
end

-- The Filter menu's Sources, as the learn data's letters; class spells come from class trainers
CS.SOURCE_FILTERS = { { "t", "Trainer" }, { "v", "Vendor" }, { "d", "Drop" }, { "q", "Quest" }, { "w", "World object" },
    { "c", "Another profession" }, { "a", "Learned with the profession" } }

function CS:LearnSources(recipeID)
    if self.BUILTIN_CLASS and self.BUILTIN_CLASS[recipeID] then return "t" end
    local info = self:GetLearnInfo(recipeID)
    local how = info and info.how or ""
    if not how:find("t") and self.BUILTIN_TRAINERS and self.BUILTIN_TRAINERS[recipeID] then how = how .. "t" end
    return how
end

-- The Filter menu's Slots, from the crafted item's equip slot
local SLOT_OF = { INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_BODY = "Shirt", INVTYPE_TABARD = "Tabard",
    INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet",
    INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "One-Hand", INVTYPE_WEAPONMAINHAND = "One-Hand",
    INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_HOLDABLE = "Off Hand",
    INVTYPE_SHIELD = "Shield", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged",
    INVTYPE_AMMO = "Ammo", INVTYPE_BAG = "Bag", INVTYPE_QUIVER = "Bag" }
CS.SLOT_FILTERS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
    "Feet", "Finger", "Trinket", "One-Hand", "Two-Hand", "Off Hand", "Shield", "Ranged", "Ammo", "Bag", "Not equipment" }
local slotCache = {}

function CS:RecipeSlot(recipeID)
    local rec = self.recipes[recipeID]
    local item = rec and rec.o
    if not item then return "Not equipment" end
    local slot = slotCache[item]
    if not slot then
        local loc = C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(item))
        slot = SLOT_OF[loc or ""] or "Not equipment"
        slotCache[item] = slot
    end
    return slot
end

-- The browser's Filter menu: each ticked filter must hold for a recipe to be listed; sources and slots hold the
-- unticked entries
function CS:PassesFilters(recipeID)
    local filters, rec = self.data.settings.filters, self.recipes[recipeID]
    if not rec then return false end
    if filters.mine and not self:SkillOf(self.CharKey(), rec.p) then return false end
    if filters.skillUp and not self.SKILL_ATLAS[self:Difficulty(recipeID) or ""] then return false end
    if filters.unknown and self:WhoKnows(recipeID) == "me" then return false end
    if filters.materials and not self:HasMaterials(recipeID) then return false end
    local hidden = filters.sources
    if hidden and next(hidden) then
        -- a recipe without learn data stays: hiding it would hide it for a gap in the data
        local how, any = self:LearnSources(recipeID), false
        for letter in how:gmatch(".") do
            if not hidden[letter] then any = true end
        end
        if how ~= "" and not any then return false end
    end
    if filters.slots and filters.slots[self:RecipeSlot(recipeID)] then return false end
    return true
end

-- True when bags and bank hold every required reagent; optional reagents never block a craft
function CS:HasMaterials(recipeID)
    local rec = self.recipes[recipeID]
    if not rec or not rec.r then return false end
    for _, r in ipairs(rec.r) do
        if not r[3] and self:ItemCounts(r[1]) < r[2] then return false end
    end
    return true
end

function CS:AnyFilter()
    for _, on in pairs(self.data.settings.filters) do
        if on == true or (type(on) == "table" and next(on)) then return true end
    end
    return false
end

-- The recipes of a list this character can get: known first, then alts, then by profession and name
local function Obtainable(self, list)
    if not list then return nil end
    local out, rankOf = {}, {}
    local rank = { me = 0, alt = 1 }
    for i = 1, #list do
        local id = list[i]
        local who = self:WhoKnows(id)
        if self:Shown(id, who) then
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
-- Recipes whose name or crafted item matches, as the reagent search does for reagents
function CS:SearchRecipesByName(text)
    text = text:lower()
    local hits = {}
    for recipeID, rec in pairs(self.recipes) do
        local name = Lower("r" .. recipeID, rec.n)
        local made = rec.o and Lower(rec.o, self:ItemName(rec.o))
        if ((name and name:find(text, 1, true)) or (made and made:find(text, 1, true))) and self:Shown(recipeID) then
            hits[#hits + 1] = recipeID
        end
    end
    return Obtainable(self, hits) or {}
end

-- Skill ---------------------------------------------------------------------

-- The skill to learn a recipe and where it turns yellow, green and grey, as the profession window colours it
function CS:SkillRange(recipeID)
    local info = self:GetLearnInfo(recipeID)
    local learn = info and info.skill or 0
    local k = self.BUILTIN_SKILL and self.BUILTIN_SKILL[recipeID]
    if not k then return learn end
    return learn, k[1], math.floor((k[1] + k[2]) / 2), k[2]
end

-- A character's rank in a profession, or nil without the profession
function CS:SkillOf(char, prof)
    local s = self.data.skills[char]
    return s and s[prof]
end

-- "learn" (skill too low), "orange", "yellow", "green" or "grey", and the rank; nil without the profession
function CS:Difficulty(recipeID, char)
    local rec = self.recipes[recipeID]
    local rank = rec and self:SkillOf(char or self.CharKey(), rec.p)
    if not rank then return nil end
    local learn, yellow, green, grey = self:SkillRange(recipeID)
    if rank < learn then return "learn", rank end
    if not yellow then return nil, rank end
    if rank >= grey then return "grey", rank end
    if rank >= green then return "green", rank end
    if rank >= yellow then return "yellow", rank end
    return "orange", rank
end

function CS:SearchReagentsByName(text)
    text = text:lower()
    local hits, names, uses = {}, {}, {}
    for itemID in pairs(self.usedIn) do
        local name = self:ItemName(itemID)
        if not name then
            C_Item.RequestLoadItemDataByID(itemID)
        elseif Lower(itemID, name):find(text, 1, true) then
            local list = self:GetUses(itemID)
            if list then
                hits[#hits + 1] = itemID
                names[itemID], uses[itemID] = name, #list
            end
        end
    end
    table.sort(hits, function(a, b) return names[a] < names[b] end)
    return hits, uses
end
