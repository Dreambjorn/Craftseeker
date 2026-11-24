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
    local rebuild, unlearned = false, false
    local listed = {}
    for _, recipeID in ipairs(ids) do
        listed[recipeID] = true
        local rec, info = ScanRecipe(recipeID)
        if rec then
            local old = CS.recipes[recipeID]
            if old and IndexChanged(old, rec) then rebuild = true end
            CS:SetRecipe(recipeID, rec)
        end
        -- a window lists other seasons' recipes too; one somebody has learned is proof it exists here
        if info and info.learned then data.proven[recipeID] = true end
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
    CS:KnownChanged()
end

-- This character's professions and ranks, kept for the skill colours and for alts
local skillsSeen -- the ranks the spellbook was last read for
function Scanner:ReadSkills(events)
    local ranks, seen = {}, {}
    for _, index in pairs({ GetProfessions() }) do
        local name, _, rank = GetProfessionInfo(index)
        if name and not CS.IsSecret(name, rank) then
            ranks[name] = rank
            seen[#seen + 1] = name .. rank
        end
    end
    CS.data.skills[CS.CharKey()] = ranks
    -- the spellbook only changes with a new recipe, a new rank or a new level (class spells)
    table.sort(seen)
    seen = table.concat(seen, ",") .. "," .. (UnitLevel("player") or 0)
    local learned = type(events) == "table" and (events.NEW_RECIPE_LEARNED or events.LEARNED_SPELL_IN_SKILL_LINE)
    if learned or seen ~= skillsSeen then
        skillsSeen = seen
        self:ReadSpellbook()
    end
    self:SendMessage("CRAFTSEEKER_ITEMS")
end

-- Recipes are spells the character knows, so no profession window is needed to mark them. Only adds: a window scan
-- stays the one place that clears a mark.
function Scanner:ReadSpellbook()
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return end
    local me = CS.CharKey()
    local skills, known = CS.data.skills[me] or {}, CS.data.known[me]
    local class = UnitClass("player")
    local added = 0
    local level = UnitLevel("player") or 0
    for recipeID, rec in pairs(CS.recipes) do
        local rank = skills[rec.p]
        -- a recipe above the character's rank (or a class spell above its level) can't be known yet
        local reachable = rank and rank >= CS:SkillRange(recipeID)
            or rec.p == class and level >= (CS.BUILTIN_CLASS and CS.BUILTIN_CLASS[recipeID] or 0)
        if reachable and not known[recipeID] then
            local ok, has = pcall(C_SpellBook.IsSpellKnown, recipeID)
            if ok and has == true then
                known[recipeID] = true
                CS.data.proven[recipeID] = true
                added = added + 1
            end
        end
    end
    if added > 0 then CS:KnownChanged() end
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
    self:RegisterBucketEvent({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE",
        "PLAYER_LEVEL_UP" }, 1, "ReadSkills")
    self:ReadSkills()
end
