-- Craftseeker: addon-message helpers for our own sharing and for reading other loot addons' counts
local _, CS = ...

local RESULT = Enum.SendAddonMessageResult or {}
-- Sending -------------------------------------------------------------------
-- Everything goes through ChatThrottleLib, which shares one bandwidth budget with every addon using it, so Craftseeker
-- never crowds out a raid or meter addon. Messages wait out combat lockdown and boss fights, and a whisper the client
-- refuses outright to "First Last" gets one more try as "First-Last".
local CTL = ChatThrottleLib
local THROTTLED = RESULT.AddonMessageThrottle or 3
local TARGET_OFFLINE = RESULT.TargetOffline
local held, flushing = {}, false
local Transmit

-- Whispers the server answers with "No player named ...": offline, or the other faction, which a shared channel also
-- holds and nothing tells apart beforehand. As other Forever addons do, we whisper, hide that line for our own
-- whispers only, and leave the name alone for UNREACHABLE seconds, across reloads; a message from them by whisper,
-- guild or group clears it.
local ERROR_WINDOW, UNREACHABLE, RECENT_MAX = 15, 3 * 3600, 30
local recent, hiddenAt = {}, {}

-- Only the last few seconds of whispers are kept; older names and failures are forgotten
local function Prune(now)
    for name, list in pairs(recent) do
        while list[1] and now - list[1].at > ERROR_WINDOW do table.remove(list, 1) end
        if not list[1] then recent[name] = nil end
    end
    for name, at in pairs(hiddenAt) do
        if now - at > ERROR_WINDOW then hiddenAt[name] = nil end
    end
end

local function Unreachable(name)
    local list = CS.data and CS.data.unreachable
    local at = list and list[name]
    if at and time() - at > UNREACHABLE then
        list[name], at = nil, nil
    end
    return at ~= nil
end

-- They reached us by whisper, guild or group: whispers to them work again
function CS.Reachable(name)
    local list = CS.data and CS.data.unreachable
    if list and type(name) == "string" then list[name] = nil end
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

-- Marks every form we whispered the name in, so no queued message to them goes out either
local function MarkUnreachable(name)
    local list = CS.data and CS.data.unreachable
    if not list then return end
    if not list[name] then CS:Debug("%s can't be whispered (offline or the other faction); skipped for 3 hours", name) end
    local now = time()
    for _, key in ipairs({ name, (name:gsub(" ", "-")), (name:gsub("-", " ")) }) do list[key] = now end
    for key in pairs(recent) do
        if key:match("^[^-]+") == name then list[key] = now end
    end
end

local function NotFound(name)
    recent[name], hiddenAt[name] = nil, GetTime()
    MarkUnreachable(name)
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
    if m.onSent then m.onSent(didSend) end
    if didSend and m.chatType == "WHISPER" then Remember(m) end
    -- the client may know they're gone before the server says so: no chat line then
    if m.chatType == "WHISPER" and TARGET_OFFLINE and result == TARGET_OFFLINE then
        MarkUnreachable(m.target)
        return
    end
    if not didSend and m.chatType == "WHISPER" and not m.dashed and result ~= THROTTLED and CS.DashedName(m.target) then
        m.target, m.dashed = CS.DashedName(m.target), true
        Transmit(m)
    end
end

function Transmit(m)
    if m.chatType == "WHISPER" and Unreachable(m.target) then return end
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

-- prio: "NORMAL" for announcements and requests, "BULK" for data; onSent(didSend) runs once it really goes out
function CS.Transmit(prefix, chatType, target, msg, prio, onSent)
    Transmit({ prefix = prefix, chatType = chatType, target = target, msg = msg, prio = prio or "NORMAL", onSent = onSent })
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
