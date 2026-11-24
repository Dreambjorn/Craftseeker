-- Craftseeker: creature, vendor, object and quest sources read from QuestieDB when it is installed
local _, CS = ...

local CONTRACT = 4 -- QuestieDB public API version this file was written against
local RANK = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local available

-- QuestieDB is optional; without it the browser falls back to the built-in data
function CS:HasQuestieDB()
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
    return npcID and self:HasQuestieDB() and NpcDB.Get(npcID, "name") or nil
end

-- QuestieDB's name, zones and map pin for a node or chest, or nil
function CS:ObjectInfo(objectID)
    if not objectID or not self:HasQuestieDB() then return nil end
    local name = ObjectDB.Get(objectID, "name")
    if not name then return nil end
    local spawns = ObjectDB.Get(objectID, "spawns")
    return name, Zones(spawns, ObjectDB.Get(objectID, "zoneID")), SpawnPin(spawns)
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

-- QuestieDB's level range ("16-17") and rank for a creature, for rows that came from drop counts alone
function CS:NpcLevel(npcID)
    if not npcID or not self:HasQuestieDB() then return nil end
    return Level(npcID), RANK[NpcDB.Get(npcID, "rank")]
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
-- drops and vendors: { npc, name, level, rank, zones }; objects: { name, zones }; quests: { name, level, zone }
local function Lookup(self, itemID)
    if not ItemDB.Exists(itemID) then return nil end
    local out = {
        drops = NpcEntries(ItemDB.Get(itemID, "npcDrops")),
        vendors = NpcEntries(ItemDB.Get(itemID, "vendors"), true),
        objects = {},
        quests = {},
    }
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
    if #out.drops + #out.vendors + #out.objects + #out.quests == 0 then return nil end
    return out
end

-- QuestieDB's data doesn't change during a session, and an item can drop from hundreds of creatures, so each item is
-- looked up once; callers copy what they change
local cache = {}
function CS:GetQuestieSources(itemID)
    if not itemID or not self:HasQuestieDB() then return nil end
    local hit = cache[itemID]
    if hit == nil then
        hit = Lookup(self, itemID) or false
        cache[itemID] = hit
    end
    return hit or nil
end
