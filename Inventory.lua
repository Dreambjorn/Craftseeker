-- Craftseeker: counts reagents and recipe items in every character's bags and bank
local _, CS = ...
local Inventory = CS:NewModule("Inventory", "AceEvent-3.0", "AceBucket-3.0")

local BAGS = { Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag }
local BANK = { Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9 }
local bankOpen = false
local bankReadAt                 -- last time the bank was read from item counts
local BANK_REREAD = 300

local function Mine()
    local key = CS.CharKey()
    local items = CS.data.items
    if not items[key] then items[key] = { bags = {}, bank = {} } end
    return items[key]
end

-- Only reagents and recipe items are kept, so the saved data stays small
local function Scan(range)
    local out = {}
    for bag = range[1], range[2] do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not CS.IsSecret(id) and (CS.usedIn[id] or CS.recipeItems[id]) then
                out[id] = (out[id] or 0) + (info.stackCount or 1)
            end
        end
    end
    return out
end

-- The game knows the bank's contents without a visit: an item's count with the bank, less the one without it
local function BankFromCounts()
    local out = {}
    for _, set in ipairs({ CS.usedIn, CS.recipeItems }) do
        for id in pairs(set) do
            if not out[id] then
                local all, carried = C_Item.GetItemCount(id, true), C_Item.GetItemCount(id)
                if not CS.IsSecret(all, carried) and all > carried then out[id] = all - carried end
            end
        end
    end
    return out
end

-- Marks in `into` every item whose count differs between two scans
local function Diff(old, new, into)
    for id, n in pairs(new) do
        if old[id] ~= n then into[id] = true end
    end
    for id in pairs(old) do
        if new[id] == nil then into[id] = true end
    end
end

-- Only a change in reagent or recipe-item counts is news: moving items or looting other things redraws nothing
function Inventory:Update()
    local mine, changed = Mine(), {}
    local bags = Scan(BAGS)
    Diff(mine.bags or {}, bags, changed)
    mine.bags = bags
    -- the bank tabs fill in while the bank is open; otherwise item counts give it, every few minutes at most
    local bank
    if bankOpen then
        bank = Scan(BANK)
    elseif not bankReadAt or GetTime() - bankReadAt > BANK_REREAD then
        bankReadAt = GetTime()
        -- counts not loaded yet read as an empty bank; keep the last known contents then
        bank = BankFromCounts()
        if not next(bank) and next(mine.bank or {}) then bank = nil end
    end
    if bank then
        Diff(mine.bank or {}, bank, changed)
        mine.bank = bank
    end
    if next(changed) then self:SendMessage("CRAFTSEEKER_ITEMS", changed) end
end

function Inventory:ReadBank()
    bankReadAt = nil
    self:Update()
end

function Inventory:BANKFRAME_OPENED()
    bankOpen = true
    self:Update()
end

function Inventory:BANKFRAME_CLOSED()
    bankOpen = false
    bankReadAt = GetTime()
end

-- This character's count (bags and bank), the alts that have some ({ { name, count }, ... } most first), and its bank count
function CS:ItemCounts(itemID)
    local me, have, alts, bank = self.CharKey(), 0, {}, 0
    for char, c in pairs(self.data.items) do
        local n = (c.bags[itemID] or 0) + (c.bank[itemID] or 0)
        if char == me then
            have, bank = n, c.bank[itemID] or 0
        elseif n > 0 then
            alts[#alts + 1] = { char:match("^[^-]+") or char, n }
        end
    end
    table.sort(alts, function(a, b) return a[2] > b[2] end)
    return have, alts, bank
end

function Inventory:OnEnable()
    self:RegisterEvent("BANKFRAME_OPENED")
    self:RegisterEvent("BANKFRAME_CLOSED")
    self:RegisterBucketEvent("BAG_UPDATE_DELAYED", 1, "Update")
    self:Update()
    -- item counts can still be empty right after login; read the bank again shortly
    C_Timer.After(10, function() self:ReadBank() end)
end
