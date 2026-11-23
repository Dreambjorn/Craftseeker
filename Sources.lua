-- Reagent Scout: records where reagents came from (vendors, loot, gathering, fishing)
local _, RS = ...
local Sources = RS:NewModule("Sources", "AceEvent-3.0")

local guidNames, guidCount = {}, 0 -- creature GUID -> name, from target and mouseover
local lastCast                     -- last spell target, e.g. "Copper Vein"
local lootCounted = false          -- LOOT_READY can fire more than once for one loot window

local function Tracking()
    return RS.data.settings.sources
end

local function Bucket(itemID, kind)
    local all = RS.data.sources
    local s = all[itemID]
    if not s then
        s = {}
        all[itemID] = s
    end
    s[kind] = s[kind] or {}
    return s[kind]
end

local function Bump(tbl, key)
    tbl[key] = (tbl[key] or 0) + 1
end

local function Zone()
    return GetRealZoneText() or "?"
end

local function IsNPCGUID(guid)
    local kind = guid:match("^(%a+)")
    return kind == "Creature" or kind == "Vehicle"
end

local function Remember(unit)
    local guid = UnitGUID(unit)
    if not guid or RS.IsSecret(guid) or not IsNPCGUID(guid) or guidNames[guid] then return end
    local name = UnitName(unit)
    if not name or RS.IsSecret(name) then return end
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
    if RS.IsSecret(unit) or RS.IsSecret(target) or unit ~= "player" then return end
    lastCast = target and target ~= "" and { target = target, t = GetTime() } or nil
end

function Sources:MERCHANT_SHOW()
    if not Tracking() then return end
    local vendor = UnitName("npc")
    if not vendor or RS.IsSecret(vendor) then return end
    local key = vendor .. " (" .. Zone() .. ")"
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        -- only remember vendor sources for items we know are reagents
        if itemID and RS.usedIn[itemID] then
            local price = 0
            local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
            if ok and info and info.price then
                -- price covers the whole stack the vendor sells, e.g. 5 for x
                price = math.floor(info.price / math.max(info.stackCount or 1, 1) + 0.5)
            end
            Bucket(itemID, "vendor")[key] = price
        end
    end
end

local function RecordSource(itemID, guid)
    if not guid or RS.IsSecret(guid) then return end
    local kind = guid:match("^(%a+)")
    if kind == "Creature" or kind == "Vehicle" then
        local name = guidNames[guid]
        if not name then
            local npcID = select(6, strsplit("-", guid))
            name = "NPC #" .. (npcID or "?")
        end
        Bump(Bucket(itemID, "loot"), name .. " (" .. Zone() .. ")")
    elseif kind == "GameObject" then
        local how = lastCast and GetTime() - lastCast.t < 8 and lastCast.target or "Node/object"
        Bump(Bucket(itemID, "gather"), how .. " (" .. Zone() .. ")")
    elseif kind == "Item" then
        Bump(Bucket(itemID, "container"), "Container")
    end
end

local function NpcOf(guid)
    if not guid or RS.IsSecret(guid) or not IsNPCGUID(guid) then return nil end
    return tonumber((select(6, strsplit("-", guid))))
end

-- Own drop counts feed RS:GetDropRates: every corpse in a loot window counts once as opened,
-- and reagents and recipe items count per corpse they came from
local function CountSlot(counts, opened, slot, itemID)
    local src = { GetLootSourceInfo(slot) }
    for i = 1, #src, 2 do
        local npc = NpcOf(src[i])
        if npc then
            local c = counts[npc]
            if not c then
                c = {}
                counts[npc] = c
            end
            if not opened[npc] then
                opened[npc] = true
                c.opened = (c.opened or 0) + 1
                c.name = c.name or guidNames[src[i]]
            end
            RS.data.countsStamp = time()
            if itemID and (RS.usedIn[itemID] or RS.recipeItems[itemID]) then
                c.items = c.items or {}
                c.items[itemID] = (c.items[itemID] or 0) + 1
            end
        end
    end
end

function Sources:LOOT_READY()
    if not Tracking() or lootCounted then return end
    lootCounted = true
    local fishing = IsFishingLoot()
    local opened = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = link and RS.ItemIDFromText(link)
        if not fishing then CountSlot(RS.data.counts, opened, slot, itemID) end
        if itemID and RS.usedIn[itemID] then
            if fishing then
                Bump(Bucket(itemID, "fish"), Zone())
            else
                -- area loot returns guid, quantity pairs, one per corpse
                local src = { GetLootSourceInfo(slot) }
                for i = 1, #src, 2 do
                    RecordSource(itemID, src[i])
                end
            end
        end
    end
end

function Sources:LOOT_CLOSED()
    lootCounted = false
end

function Sources:OnEnable()
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    self:RegisterEvent("UNIT_SPELLCAST_SENT")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("LOOT_READY")
    self:RegisterEvent("LOOT_CLOSED")
end
