-- Reagent Scout: creature, vendor, object and quest sources read from QuestieDB when it is installed
local _, RS = ...

local CONTRACT = 4 -- QuestieDB public API version this file was written against
local RANK = { [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }
local available

-- QuestieDB is optional; without it the browser falls back to the built-in zones
function RS:HasQuestieDB()
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

-- Zones an NPC or object spawns in, falling back to its main zone
local function Zones(spawns, mainZone)
    local out = {}
    if type(spawns) == "table" then
        for areaID in pairs(spawns) do
            local name = ZoneName(areaID)
            if name then out[#out + 1] = name end
        end
    end
    -- new Forever creatures often have no spawn data yet
    if #out == 0 then out[1] = ZoneName(mainZone) or "Zone not recorded" end
    return out
end

local function FriendlyToMe(flag)
    if not flag or flag == "AH" then return true end
    return flag == (UnitFactionGroup("player") == "Horde" and "H" or "A")
end

-- Groups { zone, label } pairs as { { zone = name, names = { ... } }, ... }, busiest zone first
local function ByZone(pairsList)
    local zones, order = {}, {}
    for _, p in ipairs(pairsList) do
        local z = zones[p[1]]
        if not z then
            z = { zone = p[1], names = {}, seen = {} }
            zones[p[1]] = z
            order[#order + 1] = z
        end
        if not z.seen[p[2]] then
            z.seen[p[2]] = true
            z.names[#z.names + 1] = p[2]
        end
    end
    table.sort(order, function(a, b)
        if #a.names ~= #b.names then return #a.names > #b.names end
        return a.zone < b.zone
    end)
    for _, z in ipairs(order) do
        table.sort(z.names)
        z.seen = nil
    end
    return order
end

local function NpcLabel(id, withLevel)
    local name = NpcDB.Get(id, "name")
    if not name then return nil end
    local minL, maxL, rank = NpcDB.Get(id, "minLevel"), NpcDB.Get(id, "maxLevel"), NpcDB.Get(id, "rank")
    local level = withLevel and minL and minL > 0 and (maxL and maxL > minL and (minL .. "-" .. maxL) or tostring(minL))
    local extra = {}
    if level then extra[#extra + 1] = level end
    if RANK[rank] then extra[#extra + 1] = RANK[rank] end
    return #extra > 0 and (name .. " (" .. table.concat(extra, ", ") .. ")") or name
end

local function NpcsByZone(ids, onlyFriendly)
    local list = {}
    for _, id in ipairs(ids or {}) do
        if not onlyFriendly or FriendlyToMe(NpcDB.Get(id, "friendlyToFaction")) then
            local label = NpcLabel(id, not onlyFriendly) -- levels help with drops, not vendors
            if label then
                for _, zone in ipairs(Zones(NpcDB.Get(id, "spawns"), NpcDB.Get(id, "zoneID"))) do
                    list[#list + 1] = { zone, label }
                end
            end
        end
    end
    return ByZone(list)
end

local function QuestForMe(id)
    local races = QuestDB.Get(id, "requiredRaces")
    if not races or races == 0 then return true end
    local masks = LibQuestieDB.Enum and LibQuestieDB.Enum.factionRaceMasks
    local mine = masks and masks[UnitFactionGroup("player")]
    return not mine or bit.band(races, mine) ~= 0
end

-- Where an item comes from, per QuestieDB; nil when QuestieDB is missing or knows nothing
function RS:GetQuestieSources(itemID)
    if not itemID or not self:HasQuestieDB() or not ItemDB.Exists(itemID) then return nil end
    local out = {
        drops = NpcsByZone(ItemDB.Get(itemID, "npcDrops")),
        vendors = NpcsByZone(ItemDB.Get(itemID, "vendors"), true),
        objects = {},
        quests = {},
    }
    local objects = {}
    for _, id in ipairs(ItemDB.Get(itemID, "objectDrops") or {}) do
        local name = ObjectDB.Get(id, "name")
        if name then
            for _, zone in ipairs(Zones(ObjectDB.Get(id, "spawns"), ObjectDB.Get(id, "zoneID"))) do
                objects[#objects + 1] = { zone, name }
            end
        end
    end
    out.objects = ByZone(objects)
    local quests = ItemDB.Get(itemID, "questRewards") or {}
    local start = ItemDB.Get(itemID, "startQuest")
    if start and start > 0 then quests[#quests + 1] = start end
    for _, id in ipairs(quests) do
        local name = QuestDB.Get(id, "name")
        if name and QuestForMe(id) then
            local level = QuestDB.Get(id, "questLevel") or QuestDB.Get(id, "requiredLevel")
            local sort = QuestDB.Get(id, "zoneOrSort") -- positive is a zone, negative a quest category
            local zone = sort and sort > 0 and ZoneName(sort)
            out.quests[#out.quests + 1] = name .. (level and level > 0 and (" (level " .. level .. ")") or "")
                .. (zone and (" in " .. zone) or "")
        end
    end
    if #out.drops + #out.vendors + #out.objects + #out.quests == 0 then return nil end
    return out
end
