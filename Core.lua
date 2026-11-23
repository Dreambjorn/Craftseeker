-- Reagent Scout: addon object, saved data and slash commands
local ADDON, ns = ...
local RS = LibStub("AceAddon-3.0"):NewAddon(ns, ADDON, "AceConsole-3.0")
_G.ReagentScout = RS

local defaults = {
    global = {
        recipes = {},              -- [recipeID] = { n, p, o, q, r = { { itemID, qty, optional } } } from windows
        known = { ["*"] = {} },    -- [character] = { [recipeID] = true }
        sources = {},              -- [itemID] = { vendor = {}, loot = {}, gather = {}, fish = {}, container = {} }
        verified = {},             -- [profession] = { [recipeID] = true }, the full list a window showed
        counts = {},               -- [npcID] = { name, opened = corpses looted, items = { [itemID] = drops } }
        shared = {},               -- [install] = { stamp, from, counts }: other Reagent Scout users' counts
        settings = { sources = true },
    },
}

-- Safe guard for secret values (combat-restricted data)
function RS.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- Forever returns "" for realm names; its character names are region-unique
function RS.CharKey()
    return UnitName("player") or "?"
end

function RS.Money(copper)
    if not copper or copper <= 0 then return "" end
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

function RS:OnInitialize()
    -- Data saved before the switch to AceDB sat at the top level
    local old = ReagentScoutDB
    if type(old) == "table" and old.recipes and not old.global then
        ReagentScoutDB = { global = { recipes = old.recipes, known = old.known, sources = old.sources,
            verified = old.verified, settings = { sources = not old.settings or old.settings.sources ~= false } } }
    end
    self.db = LibStub("AceDB-3.0"):New("ReagentScoutDB", defaults, true)
    self.data = self.db.global
    self:RebuildIndex()
    self:RegisterChatCommand("rs", "SlashCommand")
    self:RegisterChatCommand("reagentscout", "SlashCommand")
end

function RS:SlashCommand(input)
    local msg = strtrim(input or "")
    local cmd = (self:GetArgs(msg, 1) or ""):lower()
    local data = self.data
    if cmd == "" then
        self:GetModule("Browser"):Toggle()
    elseif cmd == "help" then
        self:Print("commands:")
        print("  /rs  - open the browser")
        print("  /rs <item link, ID or name>  - look up a reagent")
        print("  /rs sources  - turn source tracking on/off")
        print("  /rs stats  - what's been learned so far")
        print("  /rs reset  - wipe all learned data")
        print("  Alt+Click an item in your bags to look it up.")
    elseif cmd == "sources" then
        data.settings.sources = not data.settings.sources
        self:Print("source tracking", data.settings.sources and "on" or "off")
    elseif cmd == "stats" then
        local profs = {}
        for _, rec in pairs(self.recipes) do
            profs[rec.p or "?"] = (profs[rec.p or "?"] or 0) + 1
        end
        local reagents, srcs = 0, 0
        for _ in pairs(self.usedIn) do reagents = reagents + 1 end
        for _ in pairs(data.sources) do srcs = srcs + 1 end
        local peers = 0
        for _ in pairs(data.shared) do peers = peers + 1 end
        self:Print(self:CountRecipes() .. " recipes, " .. reagents .. " reagents, sources for " .. srcs .. " items, "
            .. "loot counts from " .. peers .. " other Reagent Scout user" .. (peers == 1 and "" or "s"))
        for p, n in pairs(profs) do
            print("  " .. p .. ": " .. n .. (data.verified[p] and "" or " (not checked against a window yet)"))
        end
    elseif cmd == "reset" then
        wipe(data.recipes); wipe(data.known); wipe(data.sources); wipe(data.verified); wipe(data.counts); wipe(data.shared)
        self:RebuildIndex()
        self:Print("learned data wiped; built-in recipes remain. Open your profession windows to relearn.")
    else
        self:GetModule("Browser"):Show(msg)
    end
end
