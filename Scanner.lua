-- Craftseeker: learns recipes and what each character knows from profession windows
local _, CS = ...
local Scanner = CS:NewModule("Scanner", "AceEvent-3.0", "AceBucket-3.0")

local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
-- LIST_UPDATE fires after every craft; only the first one per window opening needs a scan
local scanned = false

local function ProfessionNameFor(recipeID)
    local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
    if info then
        local n = info.parentProfessionName
        if n and n ~= "" then return n end
        if info.professionName and info.professionName ~= "" then return info.professionName end
    end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    return base and base.professionName or "?"
end

local function ScanRecipe(recipeID)
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if not info then return nil end
    local schem = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not schem then return nil end

    local rec = {
        n = info.name or schem.name,
        p = ProfessionNameFor(recipeID),
        o = schem.outputItemID,
        q = schem.quantityMin,
        r = {},
    }
    for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
        local optional = (slot.required == false) or (slot.reagentType ~= nil and slot.reagentType ~= BASIC)
        for _, reagent in ipairs(slot.reagents or {}) do
            if reagent.itemID then
                rec.r[#rec.r + 1] = { reagent.itemID, slot.quantityRequired or 1, optional or nil }
            end
        end
    end
    if #rec.r == 0 then return nil, info end
    return rec, info
end

-- True when a rescan changed what the reverse index points at
local function IndexChanged(old, new)
    if old.o ~= new.o or #old.r ~= #new.r then return true end
    for i = 1, #new.r do
        if old.r[i][1] ~= new.r[i][1] then return true end
    end
    return false
end

function Scanner:Scan()
    if scanned or not C_TradeSkillUI.IsTradeSkillReady() then return end
    -- Only record "known" for your own professions, not linked/guild/NPC windows
    local ownWindow = not (C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsNPCCrafting())
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if not ids or #ids == 0 then return end
    scanned = true

    local data = CS.data
    local known = data.known[CS.CharKey()]
    local added, rebuild, unlearned = 0, false, false
    local listed = {}
    for _, recipeID in ipairs(ids) do
        listed[recipeID] = true
        local rec, info = ScanRecipe(recipeID)
        if rec then
            local old = CS.recipes[recipeID]
            if not old then
                added = added + 1
            elseif IndexChanged(old, rec) then
                rebuild = true
            end
            CS:SetRecipe(recipeID, rec)
        end
        if ownWindow and info then
            known[recipeID] = info.learned and true or nil
            if not info.learned then unlearned = true end
        end
    end
    local base = C_TradeSkillUI.GetBaseProfessionInfo()
    local prof = base and base.professionName
    -- Only a list that includes unlearned recipes is complete enough to hide built-in ones
    if ownWindow and unlearned and prof and prof ~= "" then
        data.verified[prof] = listed
        rebuild = true
    end
    -- IndexRecipe only adds, so drop entries for reagents a recipe no longer uses
    if rebuild then CS:RebuildIndex() end
    if added > 0 then
        CS:Print(("learned %d new recipes from %s (%d total)."):format(added, prof or "this profession", CS:CountRecipes()))
    end
end

function Scanner:Reset()
    scanned = false
end

function Scanner:OnEnable()
    -- A new window, data source or recipe needs a fresh scan
    self:RegisterEvent("TRADE_SKILL_SHOW", "Reset")
    self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", "Reset")
    self:RegisterEvent("NEW_RECIPE_LEARNED", "Reset")
    self:RegisterEvent("TRADE_SKILL_CLOSE", "Reset")
    -- Half a second of quiet lets the window finish loading; LIST_UPDATE covers data that was late
    self:RegisterBucketEvent({ "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED",
        "TRADE_SKILL_LIST_UPDATE" }, 0.5, "Scan")
end
