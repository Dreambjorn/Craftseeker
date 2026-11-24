-- Craftseeker: records where reagents came from (vendors, loot, gathering, fishing)
local _, CS = ...
local Sources = CS:NewModule("Sources", "AceEvent-3.0")

local guidNames, guidCount = {}, 0 -- creature GUID -> name, from target and mouseover; also marks creatures learned
local lastCast                     -- last spell target, e.g. "Copper Vein"
local lootCounted = false          -- LOOT_READY can fire more than once for one loot window

local function Tracking()
    return CS.data.settings.sources
end

local function Bucket(itemID, kind)
    local all = CS.data.sources
    local s = all[itemID]
    if not s then
        s = {}
        all[itemID] = s
    end
    s[kind] = s[kind] or {}
    return s[kind]
end

-- A bucket keeps its BUCKET_MAX busiest places, so a reagent farmed everywhere doesn't grow without end
local BUCKET_MAX = 40
local function Bump(tbl, key)
    if not tbl[key] then
        local count, least = 0, nil
        for k, n in pairs(tbl) do
            count = count + 1
            if not least or n < tbl[least] then least = k end
        end
        if count >= BUCKET_MAX then tbl[least] = nil end
    end
    tbl[key] = (tbl[key] or 0) + 1
end

local function Zone()
    return GetRealZoneText() or "?"
end

local function IsNPCGUID(guid)
    local kind = guid:match("^(%a+)")
    return kind == "Creature" or kind == "Vehicle"
end

local function NpcOf(guid)
    if not guid or CS.IsSecret(guid) or not IsNPCGUID(guid) then return nil end
    return tonumber((select(6, strsplit("-", guid))))
end

-- Where the player stands, in thousandths of the map; nil where the game gives no position (most instances)
local function PlayerPin()
    local map = C_Map.GetBestMapForUnit("player")
    if not map or CS.IsSecret(map) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or CS.IsSecret(x, y) or x <= 0 or y <= 0 then return nil end
    return { map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5) }
end

-- What we learn about a creature the game data may leave blank: name, level range, zones and, when we stood next
-- to it (loot, a vendor or trainer window), a map pin. New facts count as news for other Craftseeker users.
local RANK_CODE = { elite = 1, rareelite = 2, worldboss = 3, rare = 4 }
local FACTION_CODE = { Alliance = 1, Horde = 2 }

local function Learn(npc, name, level, near, unit)
    local e, news = CS.data.npcs[npc], false
    if not e then
        e, news = { z = {} }, true
        CS.data.npcs[npc] = e
    end
    if name and not CS.IsSecret(name) and e.n ~= name then e.n, news = name, true end
    if level and not CS.IsSecret(level) and level > 0 then
        if not e.lo or level < e.lo then e.lo, news = level, true end
        if not e.hi or level > e.hi then e.hi, news = level, true end
    end
    local zone = Zone()
    if not e.z[zone] then news = true end
    if near or not e.z[zone] then e.z[zone] = (e.z[zone] or 0) + 1 end
    if near and not e.p then
        e.p = PlayerPin()
        news = news or e.p ~= nil
    end
    -- rank (elite, rare...) from any look at the unit; faction only from a vendor or trainer we spoke to (3 neutral)
    if unit then
        local class = UnitClassification(unit)
        local rank = class and not CS.IsSecret(class) and RANK_CODE[class]
        if rank and e.r ~= rank then e.r, news = rank, true end
        if near then
            local faction = UnitFactionGroup(unit)
            local code = faction and not CS.IsSecret(faction) and FACTION_CODE[faction] or 3
            if e.f ~= code then e.f, news = code, true end
        end
    end
    if news then CS.data.countsStamp = time() end
end
CS.LearnNpc = Learn

local function Remember(unit)
    local guid = UnitGUID(unit)
    if not guid or CS.IsSecret(guid) or not IsNPCGUID(guid) then return end
    if guidNames[guid] then return end
    local npc = NpcOf(guid)
    if npc and Tracking() and CS:IsSourceNpc(npc) then Learn(npc, UnitName(unit), UnitLevel(unit), false, unit) end
    local name = UnitName(unit)
    if not name or CS.IsSecret(name) then return end
    -- session-only cache; drop it rather than let it grow all evening
    if guidCount >= 1000 then
        wipe(guidNames)
        guidCount = 0
    end
    guidNames[guid] = name
    guidCount = guidCount + 1
end

function Sources:PLAYER_TARGET_CHANGED() Remember("target") end
function Sources:UPDATE_MOUSEOVER_UNIT() Remember("mouseover") end

function Sources:UNIT_SPELLCAST_SENT(_, unit, target)
    -- the whole payload can be secret, and comparing a secret value errors
    if CS.IsSecret(unit) or CS.IsSecret(target) or unit ~= "player" then return end
    lastCast = target and target ~= "" and { target = target, t = GetTime() } or nil
end

function Sources:MERCHANT_SHOW()
    if not Tracking() then return end
    local vendor = UnitName("npc")
    if not vendor or CS.IsSecret(vendor) then return end
    local key = vendor .. " (" .. Zone() .. ")"
    local npc = NpcOf(UnitGUID("npc"))
    local changed, sells = false, false
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        -- only reagents and recipe items; the price covers the whole stack the vendor sells, e.g. 5 for x
        if itemID and (CS.usedIn[itemID] or CS.recipeItems[itemID]) then
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            local copper, stack = ok and info and info.price, ok and info and math.max(info.stackCount or 1, 1) or 1
            if CS.usedIn[itemID] then
                Bucket(itemID, "vendor")[key] = copper and math.floor(copper / stack + 0.5) or 0
            end
            if npc and copper and copper > 0 then
                sells = true
                local prices = CS.data.prices[itemID] or {}
                CS.data.prices[itemID] = prices
                local old = prices[npc]
                if not old or old[1] ~= copper or old[2] ~= stack then changed = true end
                prices[npc] = { copper, stack, vendor }
            end
        end
    end
    if npc and (sells or CS:IsSourceNpc(npc)) then Learn(npc, vendor, UnitLevel("npc"), true, "npc") end
    -- a new price is news for other Craftseeker users, like new loot, and redraws an open window
    if changed then
        CS.data.countsStamp = time()
        CS:CountsChanged(true)
    end
end

local function RecordSource(itemID, guid, gathering)
    if not guid or CS.IsSecret(guid) then return end
    local kind = guid:match("^(%a+)")
    if kind == "Creature" or kind == "Vehicle" then
        -- area loot takes corpses never targeted or moused over, so fall back to QuestieDB's name
        local npcID = select(6, strsplit("-", guid))
        local name = guidNames[guid] or CS:NpcName(tonumber(npcID)) or CS:SeenNpcName(tonumber(npcID))
            or ("NPC #" .. (npcID or "?"))
        if gathering then
            Bump(Bucket(itemID, "gather"), gathering .. " " .. name .. " (" .. Zone() .. ")")
        else
            Bump(Bucket(itemID, "loot"), name .. " (" .. Zone() .. ")")
        end
    elseif kind == "GameObject" then
        local how = lastCast and GetTime() - lastCast.t < 8 and lastCast.target or "Node/object"
        Bump(Bucket(itemID, "gather"), how .. " (" .. Zone() .. ")")
    elseif kind == "Item" then
        Bump(Bucket(itemID, "container"), "Container")
    end
end

-- Profession casts that open a loot window: skinning, mining or herb gathering a corpse, or a node
local GATHER_SPELLS = { Skinning = "Skinning", Mining = "Mining", ["Herb Gathering"] = "Herbalism" }
local GATHER_WINDOW = 1.5   -- seconds from the cast finishing to its loot window
local LOOTED_TTL = 600      -- a corpse or node reopened within this (full bags) counts once
local lastGather            -- { prof, at } of the last gathering cast
local looted = {}           -- ["d"/"g" .. guid] = GetTime() it was counted

function Sources:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if CS.IsSecret(unit, spellID) or unit ~= "player" or not spellID then return end
    local name = C_Spell.GetSpellName(spellID)
    local prof = name and not CS.IsSecret(name) and GATHER_SPELLS[name]
    if prof then lastGather = { prof = prof, at = GetTime() } end
end

-- Own drop counts feed CS:GetDropRates: each corpse counts once as opened, and reagents and recipe items count per
-- corpse they came from
local function CountCorpse(opened, guid, itemID)
    local npc = NpcOf(guid)
    if not npc then return end
    local c = CS.data.counts[npc]
    if not c then
        c = {}
        CS.data.counts[npc] = c
    end
    if not opened[guid] then
        opened[guid] = true
        c.opened = (c.opened or 0) + 1
        c.name = c.name or guidNames[guid]
        if CS:IsSourceNpc(npc) then Learn(npc, guidNames[guid], nil, true) end
    end
    if itemID then
        c.items = c.items or {}
        c.items[itemID] = (c.items[itemID] or 0) + 1
    end
end

-- Gathering counts, kept apart from creature drops: "k" a corpse skinned (or mined, herb-gathered) by creature,
-- "g" a node or chest by object
local function Gather(kind, id, prof, name, items)
    local e = CS.data.gather[kind][id]
    if not e then
        e = { k = 0, i = {} }
        CS.data.gather[kind][id] = e
    end
    e.k, e.p = e.k + 1, prof
    if name then e.n = name end
    for item in pairs(items) do e.i[item] = (e.i[item] or 0) + 1 end
end

-- Chests and other objects that gave a reagent or recipe: where they stand
local function RecordObject(guid)
    local id = tonumber((select(6, strsplit("-", guid))))
    if not id then return end
    if not CS.data.objectPins[id] then
        CS.data.objectPins[id] = PlayerPin()
        if CS.data.objectPins[id] then CS.data.countsStamp = time() end
    end
    local zones = CS.data.objects[id] or {}
    CS.data.objects[id] = zones
    if not zones[Zone()] then CS.data.countsStamp = time() end
    zones[Zone()] = (zones[Zone()] or 0) + 1
end

function Sources:LOOT_READY()
    if not Tracking() or lootCounted then return end
    lootCounted = true
    local now = GetTime()
    for key, at in pairs(looted) do
        if now - at > LOOTED_TTL then looted[key] = nil end
    end
    local fishing = IsFishingLoot()
    local gathering = lastGather and now - lastGather.at < GATHER_WINDOW and lastGather.prof or nil
    lastGather = nil
    local opened, gathered, placed = {}, {}, {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = link and CS.ItemIDFromText(link)
        local counted = itemID and (CS.usedIn[itemID] or CS.recipeItems[itemID]) and itemID or nil
        -- area loot gives guid, quantity pairs, one per corpse or node
        local src = { GetLootSourceInfo(slot) }
        for i = 1, #src, 2 do
            local guid = src[i]
            if guid and not CS.IsSecret(guid) and not fishing then
                local object = guid:match("^GameObject") ~= nil
                if gathering or object then
                    gathered[guid] = gathered[guid] or {}
                    if counted then gathered[guid][counted] = true end
                    if object and counted and not placed[guid] then
                        placed[guid] = true
                        RecordObject(guid)
                    end
                elseif not looted["d" .. guid] then
                    CountCorpse(opened, guid, counted)
                end
            end
            if counted and CS.usedIn[counted] then
                if fishing then
                    if i == 1 then Bump(Bucket(counted, "fish"), Zone()) end
                else
                    RecordSource(counted, guid, gathering)
                end
            end
        end
    end
    local node = lastCast and now - lastCast.t < 8 and lastCast.target or nil
    for guid, items in pairs(gathered) do
        if not looted["g" .. guid] then
            looted["g" .. guid] = now
            local id = tonumber((select(6, strsplit("-", guid))))
            if id and guid:match("^GameObject") then
                Gather("g", id, gathering or "Chest", node, items)
            elseif id then
                Gather("k", id, gathering, nil, items)
            end
        end
    end
    for guid in pairs(opened) do looted["d" .. guid] = now end
    if next(opened) or next(gathered) then
        CS.data.countsStamp = time()
        CS:CountsChanged(true)
    end
end

-- Quests whose rewards hold a reagent or recipe item: name, giver and the factions that saw them offered
function Sources:QuestRewards()
    if not Tracking() or not GetQuestID then return end
    local id = GetQuestID()
    if not id or CS.IsSecret(id) or id == 0 then return end
    local items = {}
    for _, kind in ipairs({ { "reward", GetNumQuestRewards() }, { "choice", GetNumQuestChoices() } }) do
        for i = 1, kind[2] or 0 do
            local link = GetQuestItemLink(kind[1], i)
            local itemID = link and not CS.IsSecret(link) and CS.ItemIDFromText(link)
            if itemID and (CS.usedIn[itemID] or CS.recipeItems[itemID]) then items[itemID] = true end
        end
    end
    if not next(items) then return end
    local q, news = CS.data.quests[id], false
    if not q then
        q, news = { i = {} }, true
        CS.data.quests[id] = q
    end
    local title = GetTitleText()
    if title and not CS.IsSecret(title) and title ~= "" then q.n = title end
    local giver = NpcOf(UnitGUID("npc"))
    if giver then
        q.g = giver
        Learn(giver, UnitName("npc"), UnitLevel("npc"), true, "npc")
    end
    local side = UnitFactionGroup("player") == "Horde" and 2 or 1
    if q.s ~= side and q.s ~= 3 then q.s, news = (q.s and q.s ~= side) and 3 or side, true end
    for item in pairs(items) do
        if not q.i[item] then q.i[item], news = true, true end
    end
    if news then CS.data.countsStamp = time() end
end

-- Trainers that teach recipes: where they stand
function Sources:TRAINER_SHOW()
    if not Tracking() then return end
    local npc = NpcOf(UnitGUID("npc"))
    if npc and CS:IsSourceNpc(npc) then Learn(npc, UnitName("npc"), UnitLevel("npc"), true, "npc") end
end

function Sources:LOOT_CLOSED()
    lootCounted = false
end

function Sources:OnEnable()
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("TRAINER_SHOW")
    self:RegisterEvent("QUEST_DETAIL", "QuestRewards")
    self:RegisterEvent("QUEST_COMPLETE", "QuestRewards")
    self:RegisterEvent("LOOT_READY")
    self:RegisterEvent("LOOT_CLOSED")
end
