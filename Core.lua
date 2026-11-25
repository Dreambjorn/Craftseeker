-- Craftseeker: addon object, saved data and slash commands
local ADDON, ns = ...
local CS = LibStub("AceAddon-3.0"):NewAddon(ns, ADDON, "AceConsole-3.0")
_G.Craftseeker = CS

local defaults = {
    global = {
        recipes = {},              -- [recipeID] = { n, p, o, q, r = { { itemID, qty, optional } } } from windows
        known = { ["*"] = {} },    -- [character] = { [recipeID] = true }
        sources = {},              -- [itemID] = { vendor = {}, loot = {}, gather = {}, fish = {}, container = {} }
        verified = {},             -- [profession] = { [recipeID] = true }, the full list a window showed
        proven = {},               -- [recipeID] = true: a profession window, own or linked, showed it learned
        counts = {},               -- [npcID] = { name, opened = corpses looted, items = { [itemID] = drops } }
        shared = {},               -- [install] = { stamp, from, counts, prices }: other Craftseeker users' counts
        objects = {},              -- [objectID] = { [zone] = times }: where we looted reagents and recipes from objects
        gather = { k = {}, g = {} }, -- skinning etc. by creature (k) and nodes/chests by object (g): { p, k, i, n }
        objectPins = {},           -- [objectID] = { uiMap, x, y } in thousandths, where we stood looting it
        npcs = {},                 -- [npcID] = { n = name, lo, hi = level range, z = { [zone] = times }, p = pin }
        quests = {},               -- [questID] = { n = name, g = giver npcID, s = factions (1, 2, 3 both), i = { [itemID] = true } }
        favorites = {},            -- [recipeID] = true: the browser's Favorites section, every character
        prices = {},               -- [itemID] = { [npc] = { copper per stack, stack, vendor name } }: our vendor visits
        skills = {},               -- [character] = { [profession] = rank }
        items = {},                -- [character] = { bags = { [itemID] = n }, bank = { [itemID] = n } }
        bridges = { dt = {}, fd = {}, dtSkins = {} },  -- other loot addons' counts: dt, dtSkins [npc][install], fd [player id]
        -- hidden: [profession] = true; dt, fd: read those addons' counts; opposite: list the other faction's recipes
        settings = { share = true, hidden = {}, dt = true, fd = true, opposite = false, filters = {}, tooltip = true, debug = false },
        minimap = { hide = false },  -- LibDBIcon's button position and visibility
    },
}

-- Chat lines for troubleshooting, only with "Show debug messages" ticked in the settings
function CS:Debug(text, ...)
    if not (self.data and self.data.settings.debug) then return end
    self:Print("|cff9d9d9d" .. (select("#", ...) > 0 and text:format(...) or text) .. "|r")
end

-- Safe guard for secret values (combat-restricted data)
function CS.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- Forever returns "" for realm names; its character names are region-unique
function CS.CharKey()
    return UnitName("player") or "?"
end

function CS.Money(copper)
    if not copper or copper <= 0 then return "" end
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

function CS:OnInitialize()
    -- Data saved before the switch to AceDB sat at the top level
    local old = CraftseekerDB
    if type(old) == "table" and old.recipes and not old.global then
        CraftseekerDB = { global = { recipes = old.recipes, known = old.known, sources = old.sources,
            verified = old.verified } }
    end
    self.db = LibStub("AceDB-3.0"):New("CraftseekerDB", defaults, true)
    self.data = self.db.global
    self.data.settings.sources = nil -- source tracking is always on now; the old switch is dropped
    self:RebuildIndex()
    self:RegisterChatCommand("cs", "SlashCommand")
    self:RegisterChatCommand("craftseeker", "SlashCommand")
end

function CS:SlashCommand(input)
    local msg = strtrim(input or "")
    local cmd = (self:GetArgs(msg, 1) or ""):lower()
    local data = self.data
    if cmd == "" then
        self:GetModule("Browser"):Toggle()
    elseif cmd == "help" then
        self:Print("commands:")
        print("  /cs  - open the browser")
        print("  /cs <item link, ID or name>  - look up a reagent, recipe or crafted item")
        print("  /cs share  - turn sharing with other Craftseeker users on/off")
        print("  /cs options  - open the settings (also under Options > AddOns)")
        print("  /cs minimap  - show or hide the minimap button")
        print("  /cs stats  - what's been learned so far")
        print("  /cs status  - whether sharing reaches other players this session")
        print("  /cs hello  - announce yourself to other Craftseeker users now")
        print("  /cs reset  - wipe all learned data")
        print("  Alt+Click an item in your bags to look it up.")
    elseif cmd == "share" then
        data.settings.share = not data.settings.share
        self:GetModule("Share"):Apply()
        self:Print("sharing loot counts", data.settings.share and "on" or "off")
    elseif cmd == "options" or cmd == "config" then
        self:OpenSettings()
    elseif cmd == "minimap" then
        self:SetMinimapButton(data.minimap.hide)
    elseif cmd == "status" then
        -- is sharing reaching anyone: the channel's self-test and what came and went this session
        for _, line in ipairs(self:GetModule("Share"):Status()) do print("  " .. line) end
    elseif cmd == "hello" then
        self:GetModule("Share"):Hello()
        self:Print("hello sent to your guild, group, friends and the Craftseeker channel; /cs status shows who answers")
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
        local dt, fd = self:GetModule("Listener"):Stats()
        self:Print(self:CountRecipes() .. " recipes, " .. reagents .. " reagents, sources for " .. srcs .. " items, "
            .. "loot counts from " .. peers .. " other Craftseeker user" .. (peers == 1 and "" or "s")
            .. ", " .. dt .. " Drop Tables and " .. fd .. " Forever Drops users")
        for p, n in pairs(profs) do
            print("  " .. p .. ": " .. n)
        end
    elseif cmd == "reset" then
        wipe(data.recipes); wipe(data.known); wipe(data.sources); wipe(data.verified); wipe(data.counts); wipe(data.shared); wipe(data.prices); wipe(data.objects); wipe(data.objectPins); wipe(data.npcs); wipe(data.gather.k); wipe(data.gather.g); wipe(data.quests)
        wipe(data.bridges.dt); wipe(data.bridges.fd); wipe(data.bridges.dtSkins)
        self:CountsChanged()
        self:KnownChanged()
        self:RebuildIndex()
        self:GetModule("Scanner"):ReadSpellbook()
        self:Print("learned data wiped; built-in recipes remain. Known recipes are marked again from your spellbook.")
    else
        self:GetModule("Browser"):Show(msg)
    end
end
