-- Craftseeker: creature, vendor, object and quest sources: built in, and read from QuestieDB when it is installed
local _, CS = ...

local CONTRACT = 4 -- QuestieDB public API version this file was written against
local RANK = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local available

-- QuestieDB is optional; without it the browser falls back to the built-in data
function CS:HasQuestieDB()
    -- asked again until found: QuestieDB may load after Craftseeker
    if not available then
        local lib = _G.LibQuestieDB
        available = lib and lib.RequireContract and lib.RequireContract(CONTRACT) and ItemDB and NpcDB
            and QuestDB and ObjectDB and true or false
    end
    return available
end

local function ZoneName(areaID)
    return areaID and areaID > 0 and C_Map.GetAreaInfo(areaID) or nil
end

-- Zones an NPC or object spawns in, falling back to its main zone; empty when nothing is recorded
local function Zones(spawns, mainZone)
    local out = {}
    if type(spawns) == "table" then
        for areaID in pairs(spawns) do
            local name = ZoneName(areaID)
            if name then out[#out + 1] = name end
        end
    end
    if #out == 0 then out[1] = ZoneName(mainZone) end
    table.sort(out)
    return out
end

local function FriendlyToMe(flag)
    if not flag or flag == "AH" then return true end
    return flag == (UnitFactionGroup("player") == "Horde" and "H" or "A")
end

-- A map pin from QuestieDB spawns ({ [areaID] = { { x, y }, ... } }), on a zone the built-in data can map
local function SpawnPin(spawns)
    if type(spawns) ~= "table" then return nil end
    local maps = CS.BUILTIN_AREAMAPS or {}
    for areaID, points in pairs(spawns) do
        local p = maps[areaID] and type(points) == "table" and points[1]
        if type(p) == "table" and p[1] and p[2] and p[1] > 0 then return { maps[areaID], p[1] / 100, p[2] / 100 } end
    end
end

-- QuestieDB's name for a creature, or nil
function CS:NpcName(npcID)
    if not npcID then return nil end
    return self:HasQuestieDB() and NpcDB.Get(npcID, "name") or (self.BUILTIN_NAMES and self.BUILTIN_NAMES[npcID]) or nil
end

-- A node's or chest's name, zones and map pin, from QuestieDB or the built-in data, or nil
function CS:ObjectInfo(objectID)
    if not objectID then return nil end
    local name = self:HasQuestieDB() and ObjectDB.Get(objectID, "name")
    if name then
        local spawns = ObjectDB.Get(objectID, "spawns")
        return name, Zones(spawns, ObjectDB.Get(objectID, "zoneID")), SpawnPin(spawns)
    end
    local o = self.BUILTIN_OBJECTS and self.BUILTIN_OBJECTS[objectID]
    if not o then return nil end
    local map = o[2] > 0 and C_Map.GetMapInfo(o[2])
    return o[1], { map and map.name or nil }, o[3] > 0 and { o[2], o[3] / 1000, o[4] / 1000 } or nil
end

-- QuestieDB's zones for a creature (dungeon bosses have a main zone but often no spawns), or nil
function CS:NpcZones(npcID)
    if not npcID or not self:HasQuestieDB() then return nil end
    local zones = Zones(NpcDB.Get(npcID, "spawns"), NpcDB.Get(npcID, "zoneID"))
    return #zones > 0 and zones or nil
end

local function Level(id)
    local minL, maxL = NpcDB.Get(id, "minLevel"), NpcDB.Get(id, "maxLevel")
    return minL and minL > 0 and (maxL and maxL > minL and (minL .. "-" .. maxL) or tostring(minL)) or nil
end

-- A creature's level range ("16-17") and rank, from QuestieDB or the built-in data, for rows from drop counts alone
function CS:NpcLevel(npcID)
    if not npcID then return nil end
    if self:HasQuestieDB() and Level(npcID) then return Level(npcID), RANK[NpcDB.Get(npcID, "rank")] end
    local l = self.BUILTIN_LEVELS and self.BUILTIN_LEVELS[npcID]
    if not l then return nil end
    return l[1] > 0 and (l[2] > l[1] and (l[1] .. "-" .. l[2]) or tostring(l[1])) or nil, RANK[l[3]]
end

local function NpcEntry(id)
    local name = NpcDB.Get(id, "name")
    if not name then return nil end
    local level = Level(id)
    local spawns = NpcDB.Get(id, "spawns")
    return { npc = id, name = name, level = level, rank = RANK[NpcDB.Get(id, "rank")],
        zones = Zones(spawns, NpcDB.Get(id, "zoneID")), pin = SpawnPin(spawns) or CS:GetPin(id) }
end

local function NpcEntries(ids, onlyFriendly)
    local out = {}
    for _, id in ipairs(ids or {}) do
        if not onlyFriendly or FriendlyToMe(NpcDB.Get(id, "friendlyToFaction")) then
            out[#out + 1] = NpcEntry(id)
        end
    end
    return out
end

local function QuestForMe(id)
    local races = QuestDB.Get(id, "requiredRaces")
    if not races or races == 0 then return true end
    local masks = LibQuestieDB.Enum and LibQuestieDB.Enum.factionRaceMasks
    local mine = masks and masks[UnitFactionGroup("player")]
    return not mine or bit.band(races, mine) ~= 0
end

-- Where an item comes from, per QuestieDB; nil when QuestieDB is missing or knows nothing.
-- drops and vendors: { npc, name, level, rank, zones }; objects: { name, zones }; quests: { name, level, zone };
-- containers: { id } of the items that hold it when opened
local function Lookup(self, itemID)
    if not ItemDB.Exists(itemID) then return nil end
    local out = {
        drops = NpcEntries(ItemDB.Get(itemID, "npcDrops")),
        vendors = NpcEntries(ItemDB.Get(itemID, "vendors"), true),
        objects = {},
        quests = {},
        containers = {},
    }
    for _, id in ipairs(ItemDB.Get(itemID, "itemDrops") or {}) do out.containers[#out.containers + 1] = { id = id } end
    for _, id in ipairs(ItemDB.Get(itemID, "objectDrops") or {}) do
        local name = ObjectDB.Get(id, "name")
        if name then
            local spawns = ObjectDB.Get(id, "spawns")
            out.objects[#out.objects + 1] = { id = id, name = name, zones = Zones(spawns, ObjectDB.Get(id, "zoneID")),
                pin = SpawnPin(spawns) }
        end
    end
    local quests = ItemDB.Get(itemID, "questRewards") or {}
    local start = ItemDB.Get(itemID, "startQuest")
    if start and start > 0 then quests[#quests + 1] = start end
    for _, id in ipairs(quests) do
        local name = QuestDB.Get(id, "name")
        if name and QuestForMe(id) then
            local level = QuestDB.Get(id, "questLevel") or QuestDB.Get(id, "requiredLevel")
            local sort = QuestDB.Get(id, "zoneOrSort") -- positive is a zone, negative a quest category
            local starters = QuestDB.Get(id, "startedBy") -- { npcs, objects, items }
            local giver = starters and starters[1] and starters[1][1] and NpcEntry(starters[1][1])
            out.quests[#out.quests + 1] = { name = name, level = level and level > 0 and level or nil,
                giver = giver and giver.name, zone = giver and giver.zones[1] or (sort and sort > 0 and ZoneName(sort)) or nil,
                pin = giver and giver.pin }
        end
    end
    if #out.drops + #out.vendors + #out.objects + #out.quests + #out.containers == 0 then return nil end
    return out
end

-- The built-in sources (from AllTheThings), shaped like QuestieDB's, so either works alone
local function MapName(uiMap)
    local info = uiMap and uiMap > 0 and C_Map.GetMapInfo(uiMap)
    return info and info.name or nil
end

local function MySide()
    return UnitFactionGroup("player") == "Horde" and 2 or 1
end

local function BuiltinNpc(id)
    local name = CS:NpcName(id)
    if not name then return nil end
    local l = CS.BUILTIN_LEVELS and CS.BUILTIN_LEVELS[id]
    local level = l and l[1] > 0 and (l[2] > l[1] and (l[1] .. "-" .. l[2]) or tostring(l[1])) or nil
    local zones = CS:GetPlaces(id)
    if #zones == 0 then zones = CS:NpcZones(id) or {} end
    return { npc = id, name = name, level = level, rank = l and RANK[l[3]], zones = zones, pin = CS:GetPin(id),
        side = l and l[4] or 0 }
end

local function BuiltinLookup(itemID)
    local src = CS.BUILTIN_ITEM_SOURCES and CS.BUILTIN_ITEM_SOURCES[itemID]
    if not src then return nil end
    local mine = MySide()
    local out = { drops = {}, vendors = {}, objects = {}, quests = {}, containers = {} }
    for _, id in ipairs(src[1]) do out.drops[#out.drops + 1] = BuiltinNpc(id) end
    for _, id in ipairs(src[2]) do
        local e = BuiltinNpc(id)
        if e and (e.side == 0 or e.side == mine) then out.vendors[#out.vendors + 1] = e end
    end
    for _, id in ipairs(src[3]) do
        local o = CS.BUILTIN_OBJECTS and CS.BUILTIN_OBJECTS[id]
        if o then
            out.objects[#out.objects + 1] = { id = id, name = o[1], zones = { MapName(o[2]) },
                pin = o[3] > 0 and { o[2], o[3] / 1000, o[4] / 1000 } or nil }
        end
    end
    for _, id in ipairs(src[4]) do
        local q = CS.BUILTIN_REWARDS and CS.BUILTIN_REWARDS[id]
        if q and (q[4] == 0 or q[4] == mine) then
            local giver = q[2] > 0 and BuiltinNpc(q[2])
            out.quests[#out.quests + 1] = { name = q[1], giver = giver and giver.name,
                zone = giver and giver.zones[1] or MapName(q[3]), pin = giver and giver.pin }
        end
    end
    for _, id in ipairs(src[5] or {}) do out.containers[#out.containers + 1] = { id = id } end
    return out
end

-- Both sources together, QuestieDB's rows added where the built-in ones lack them
local function Merge(a, b)
    if not a then return b end
    if not b then return a end
    for _, kind in ipairs({ "drops", "vendors" }) do
        local have = {}
        for _, e in ipairs(a[kind]) do have[e.npc] = true end
        for _, e in ipairs(b[kind]) do
            if not have[e.npc] then a[kind][#a[kind] + 1] = e end
        end
    end
    local objects, quests = {}, {}
    for _, o in ipairs(a.objects) do objects[o.id] = true end
    for _, o in ipairs(b.objects) do
        if not objects[o.id] then a.objects[#a.objects + 1] = o end
    end
    for _, q in ipairs(a.quests) do quests[q.name] = true end
    for _, q in ipairs(b.quests) do
        if not quests[q.name] then a.quests[#a.quests + 1] = q end
    end
    local containers = {}
    for _, c in ipairs(a.containers) do containers[c.id] = true end
    for _, c in ipairs(b.containers) do
        if not containers[c.id] then a.containers[#a.containers + 1] = c end
    end
    return a
end

-- Neither source changes during a session, and an item can drop from hundreds of creatures, so each item is looked up
-- once; callers copy what they change
local cache, cachedWithQuestie = {}, nil
function CS:GetItemSources(itemID)
    if not itemID then return nil end
    -- QuestieDB showing up later (loaded on demand) starts the cache over
    local questie = self:HasQuestieDB()
    if questie ~= cachedWithQuestie then
        wipe(cache)
        cachedWithQuestie = questie
    end
    local hit = cache[itemID]
    if hit == nil then
        hit = Merge(BuiltinLookup(itemID), questie and Lookup(self, itemID) or nil)
        if hit and #hit.drops + #hit.vendors + #hit.objects + #hit.quests + #hit.containers == 0 then hit = nil end
        cache[itemID] = hit or false
    end
    return hit or nil
end
