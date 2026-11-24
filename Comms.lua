-- Craftseeker: addon-message helpers for our own sharing and for reading other loot addons' counts
local _, CS = ...

local RESULT = Enum.SendAddonMessageResult or {}
-- Sending -------------------------------------------------------------------
-- Everything goes through ChatThrottleLib, which shares one bandwidth budget with every addon using it, so Craftseeker
-- never crowds out a raid or meter addon. Messages wait out combat lockdown and boss fights, and a whisper the server
-- refuses to "First Last" gets one more try as "First-Last".
local CTL = ChatThrottleLib
local THROTTLED = RESULT.AddonMessageThrottle or 3
local held, flushing = {}, false
local Transmit

-- Whispers the server answers with "No player named ...": a "First Last" name moves to "First-Last" and its recent
-- messages go again, and a name that fails that way too is skipped for half an hour. Only errors for our own whispers
-- are hidden; the player's typed whispers keep theirs.
local ERROR_WINDOW, OFFLINE_SKIP, RECENT_MAX = 15, 1800, 30
local recent, dashedFor, offline, hiddenAt = {}, {}, {}, {}

-- Only the last few seconds of whispers are kept; older names and failures are forgotten
local function Prune(now)
    for name, list in pairs(recent) do
        while list[1] and now - list[1].at > ERROR_WINDOW do table.remove(list, 1) end
        if not list[1] then recent[name] = nil end
    end
    for name, at in pairs(offline) do
        if now - at > OFFLINE_SKIP then offline[name], dashedFor[name], hiddenAt[name] = nil, nil, nil end
    end
end

local pruneAt = 0
local function MaybePrune(now)
    if now - pruneAt > ERROR_WINDOW then
        pruneAt = now
        Prune(now)
    end
end

local function Remember(m)
    local now = GetTime()
    MaybePrune(now)
    local list = recent[m.target]
    if not list then
        list = {}
        recent[m.target] = list
    end
    if #list >= RECENT_MAX then table.remove(list, 1) end
    list[#list + 1] = { m = m, at = now }
end

-- The server may name the player with a space or a dash, and without the realm
local function WhisperedLately(name)
    for _, key in ipairs({ name, (name:gsub(" ", "-")), (name:gsub("-", " ")) }) do
        local list = recent[key]
        if list and list[#list] and GetTime() - list[#list].at <= ERROR_WINDOW then return true end
    end
    for key, list in pairs(recent) do
        if key:match("^[^-]+") == name and list[#list] and GetTime() - list[#list].at <= ERROR_WINDOW then return true end
    end
    return false
end

local function NotFound(name)
    local now = GetTime()
    local list = recent[name]
    recent[name], hiddenAt[name] = nil, now
    local dashed = CS.DashedName(name)
    if dashed and not dashedFor[name] then
        CS:Debug("%s not found; whispering %s instead", name, dashed)
        dashedFor[name] = dashed
        -- each message is noted when queued and when sent; send it again once
        local again = {}
        for _, r in ipairs(list or {}) do
            if now - r.at <= ERROR_WINDOW and not again[r.m] then
                again[r.m] = true
                r.m.target, r.m.dashed = dashed, true
                Transmit(r.m)
            end
        end
    elseif dashedFor[name] then
        -- the server may name a failed "First-Last" whisper with a space too: once those went out, skip the player
        local d = dashedFor[name]
        local sent = recent[d]
        if sent and sent[#sent] and now - sent[#sent].at <= ERROR_WINDOW then
            if not offline[d] then CS:Debug("%s not found either; no whispers to them for 30 minutes", d) end
            offline[d] = now
        end
    else
        -- one error per queued message: say it once
        if not offline[name] then CS:Debug("%s not found; no whispers to them for 30 minutes", name) end
        offline[name] = now
    end
end

local notFoundPattern
local function OfflineFilter(_, _, text)
    if not notFoundPattern or type(text) ~= "string" or CS.IsSecret(text) then return false end
    local name = text:match(notFoundPattern)
    if not name then return false end
    -- every chat window runs the filter for the same line, so only the first acts
    if WhisperedLately(name) then NotFound(name) return true end
    return hiddenAt[name] ~= nil and GetTime() - hiddenAt[name] < 2
end

if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
    notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%(%)%.%[%]%*%+%-%?%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then pcall(add, "CHAT_MSG_SYSTEM", OfflineFilter) end
end

local function Flush()
    flushing = false
    if CS.MessagingBlocked() then
        flushing = true
        C_Timer.After(5, Flush)
        return
    end
    local list = held
    held = {}
    for _, m in ipairs(list) do Transmit(m) end
end

local function Sent(m, didSend, result)
    if didSend and m.chatType == "WHISPER" then Remember(m) end
    if not didSend and m.chatType == "WHISPER" and not m.dashed and result ~= THROTTLED and CS.DashedName(m.target) then
        m.target, m.dashed = CS.DashedName(m.target), true
        Transmit(m)
    end
end

function Transmit(m)
    if m.chatType == "WHISPER" then
        m.target = dashedFor[m.target] or m.target
        if offline[m.target] and GetTime() - offline[m.target] < OFFLINE_SKIP then return end
    end
    if CS.MessagingBlocked() then
        if #held < 200 then held[#held + 1] = m end
        if not flushing then
            flushing = true
            C_Timer.After(5, Flush)
        end
        return
    end
    if m.chatType == "BN" then
        CTL:BNSendGameData(m.prio, m.prefix, m.msg, "WHISPER", m.target, nil, Sent, m)
    else
        -- noted when queued as well as when sent, so a whisper waiting in the queue is covered too
        if m.chatType == "WHISPER" then Remember(m) end
        CTL:SendAddonMessage(m.prio, m.prefix, m.msg, m.chatType, m.target, nil, Sent, m)
    end
end

-- prio: "NORMAL" for announcements and requests, "BULK" for data
function CS.Transmit(prefix, chatType, target, msg, prio)
    Transmit({ prefix = prefix, chatType = chatType, target = target, msg = msg, prio = prio or "NORMAL" })
end

-- Combat lockdown and boss fights hold addon messages back
function CS.MessagingBlocked()
    return (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
        or (IsEncounterInProgress and IsEncounterInProgress()) or false
end

function CS.ChannelNumber(name)
    local id = GetChannelName(name)
    return type(id) == "number" and id > 0 and id or nil
end

-- Hidden channels carry addon messages only, so they leave every chat window
function CS.HideChannel(name)
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, frame, name)
            elseif ChatFrameUtil and ChatFrameUtil.RemoveChannel then
                pcall(ChatFrameUtil.RemoveChannel, frame, name)
            end
        end
    end
end

-- Forever writes some names "First Last"; a whisper the server refuses that way is tried as "First-Last"
function CS.DashedName(name)
    return type(name) == "string" and name:find(" ") and (name:gsub(" ", "-")) or nil
end

local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

-- Whole numbers from 0 up, in lower-case base 36
function CS.Base36(n)
    n = math.max(0, math.floor(n))
    local digit = BASE36:sub(n % 36 + 1, n % 36 + 1)
    return n < 36 and digit or CS.Base36(n / 36) .. digit
end

-- Six digits stay below 2^32, which is as far as tonumber(s, 36) reaches
function CS.FromBase36(s)
    if type(s) ~= "string" or s == "" or #s > 6 or not s:match("^[0-9a-z]+$") then return nil end
    return tonumber(s, 36)
end

-- Other players' counts not refreshed for this long are dropped at login, so saved data doesn't grow for ever
CS.PEER_MAX_AGE = 30 * 86400

-- A sender may bring only a few installs a day we've never seen, so nobody fills our tables with made-up ones
local newBySender = {} -- [sender] = { day, n }, this session only
function CS.AllowNewPeer(sender, limit)
    local day = math.floor(time() / 86400)
    local e = newBySender[sender]
    if not e or e.day ~= day then
        e = { day = day, n = 0 }
        newBySender[sender] = e
    end
    if e.n >= limit then return false end
    e.n = e.n + 1
    return true
end

-- Items whose drop counts are kept: reagents and recipe items
function CS:IsCountedItem(itemID)
    return self.usedIn[itemID] ~= nil or self.recipeItems[itemID] ~= nil
end

-- Creatures worth asking about: the built-in rates list them, or our own loot of them held a counted item
function CS:IsRelevantNpc(npc)
    if not self.relevantNpcs then
        self.relevantNpcs = {}
        for _, r in pairs(self.BUILTIN_RATES or {}) do
            for i = 1, #r, 4 do self.relevantNpcs[r[i]] = true end
        end
    end
    local own = self.data.counts[npc]
    return self.relevantNpcs[npc] or (own and own.items ~= nil) or false
end

-- The game's red "doing that too fast" names no culprit. Calls known to be throttled are noted with the addon that made
-- them, and with debug messages on, the error prints what came just before it.
local recentCalls = {}
local function NoteCall(name)
    if not (CS.data and CS.data.settings.debug) then return end
    local line = debugstack(3, 1, 0) or ""
    local addon = line:match("AddOns[/\\]([^/\\]+)") or line:match("^%[?([^%]:]+)") or "?"
    table.insert(recentCalls, { name = name, addon = addon, at = GetTime() })
    if #recentCalls > 12 then table.remove(recentCalls, 1) end
end

for _, name in ipairs({ "JoinTemporaryChannel", "JoinChannelByName", "JoinPermanentChannel", "LeaveChannelByName",
    "ListChannelByName", "SetSelectedDisplayChannel", "DisplayChannelOwner", "RandomRoll", "DoEmote" }) do
    if type(_G[name]) == "function" then hooksecurefunc(name, function() NoteCall(name) end) end
end
for lib, names in pairs({ C_FriendList = { "ShowFriends", "SendWho" }, C_GuildInfo = { "GuildRoster" },
    C_ChatInfo = { "SendChatMessage" } }) do
    for _, name in ipairs(names) do
        if _G[lib] and type(_G[lib][name]) == "function" then
            hooksecurefunc(_G[lib], name, function() NoteCall(lib .. "." .. name) end)
        end
    end
end

local errorWatch = CreateFrame("Frame")
errorWatch:RegisterEvent("UI_ERROR_MESSAGE")
errorWatch:SetScript("OnEvent", function(_, _, _, message)
    if type(message) ~= "string" or CS.IsSecret(message) or not (CS.data and CS.data.settings.debug) then return end
    local throttle = type(ERR_GENERIC_THROTTLE) == "string" and message == ERR_GENERIC_THROTTLE
    if not throttle and not message:lower():find("too fast", 1, true) then return end
    local now, parts = GetTime(), {}
    for i = #recentCalls, 1, -1 do
        local c = recentCalls[i]
        if now - c.at <= 10 then parts[#parts + 1] = ("%s by %s %.1f s before"):format(c.name, c.addon, now - c.at) end
    end
    CS:Debug("\"%s\" - %s", message, #parts > 0 and table.concat(parts, "; ") or "no channel, friends or guild call in the last 10 s")
end)
