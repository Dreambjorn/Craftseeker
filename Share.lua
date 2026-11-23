-- Reagent Scout: trades loot counts with other Reagent Scout users in the guild, the group and the friends lists
local _, RS = ...
local Share = RS:NewModule("Share", "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")

local PREFIX = "ReagentScout"
local VERSION = "1"
local CHUNK = 200          -- addon messages carry 255 bytes; the rest is the header
local GAP = 0.7            -- seconds between our messages
local HELLO_EVERY = 900    -- announce our counts this often
local MAX_OPENED = 300     -- one install never outweighs everyone else
local MAX_FRIENDS = 10
local queue, pumping = {}, false
local incoming = {}        -- [install] = { stamp, n, parts = {} }
local asked = {}           -- [install] = stamp requested this session
local answered = {}        -- [sender] = GetTime() of our last data reply
local roster, online      -- group members and online friends at the last look; nil until the first

local function Enabled()
    return RS.data.settings.share
end

-- Forever refuses addon messages to custom channels, so peers are reached through these
local function GroupType()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Friends()
    local list, seen = {}, {}
    local count = C_FriendList.GetNumFriends() or 0
    for i = 1, RS.IsSecret(count) and 0 or count do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and not RS.IsSecret(info.name) and info.connected and info.name and info.name ~= "" then
            seen[info.name] = true
            list[#list + 1] = { "WHISPER", info.name }
        end
    end
    local bn = BNGetNumFriends() or 0
    for i = 1, RS.IsSecret(bn) and 0 or bn do
        for a = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
            local g = C_BattleNet.GetFriendGameAccountInfo(i, a)
            if g and not RS.IsSecret(g.clientProgram, g.wowProjectID, g.isOnline, g.gameAccountID, g.characterName)
                and g.clientProgram == "WoW" and g.wowProjectID == WOW_PROJECT_ID and g.isOnline
                and type(g.gameAccountID) == "number" and not seen[g.characterName or ""] then
                list[#list + 1] = { "BN", g.gameAccountID }
            end
        end
    end
    while #list > MAX_FRIENDS do table.remove(list) end
    return list
end

-- Sending ---------------------------------------------------------------------

local function RawSend(chatType, target, msg)
    local ok, result
    if chatType == "BN" then
        ok, result = pcall(BNSendGameData, target, PREFIX, msg)
    else
        ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chatType, target)
    end
    local throttled = ok and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.AddonMessageThrottle
    return not throttled
end

function Share:Pump()
    local item = queue[1]
    if not item then
        self:CancelTimer(self.pumpTimer)
        pumping = false
        return
    end
    -- trial accounts and closed friends can refuse; a refused message is dropped, a throttled one waits
    if RawSend(item[1], item[2], item[3]) or (item.tries or 0) >= 3 then
        table.remove(queue, 1)
    else
        item.tries = (item.tries or 0) + 1
    end
end

local function Send(chatType, target, msg)
    if #queue >= 400 then return end
    queue[#queue + 1] = { chatType, target, msg }
    if not pumping then
        pumping = true
        Share.pumpTimer = Share:ScheduleRepeatingTimer("Pump", GAP)
    end
end

-- Our counts as text: "npc,opened,item:drops,...;" for creatures that matter to drop rates
function Share:Serialize()
    local relevant = {}
    for _, r in pairs(RS.BUILTIN_RATES or {}) do
        for i = 1, #r, 4 do relevant[r[i]] = true end
    end
    local parts = {}
    for npc, c in pairs(RS.data.counts) do
        if (c.opened or 0) > 0 and (c.items or relevant[npc]) then
            local fields = { npc, c.opened }
            for item, n in pairs(c.items or {}) do fields[#fields + 1] = item .. ":" .. n end
            parts[#parts + 1] = table.concat(fields, ",")
        end
    end
    return table.concat(parts, ";")
end

-- Their counts back, checked: whole numbers only, drops never above corpses, at most MAX_OPENED corpses each
function Share.Parse(text)
    local counts = {}
    for entry in text:gmatch("[^;]+") do
        local fields = { strsplit(",", entry) }
        local npc, opened = tonumber(fields[1]), tonumber(fields[2])
        if npc and opened and opened > 0 and opened == math.floor(opened) then
            local scale = opened > MAX_OPENED and MAX_OPENED / opened or 1
            local c = { opened = math.floor(opened * scale + 0.5), items = {} }
            for i = 3, #fields do
                local item, n = fields[i]:match("^(%d+):(%d+)$")
                item, n = tonumber(item), tonumber(n)
                if item and n and n <= opened then c.items[item] = math.floor(n * scale + 0.5) end
            end
            counts[npc] = c
        end
    end
    return counts
end

-- Peers who log in later announce themselves and get ours back, so a repeat is only needed after new loot
function Share:HelloIfChanged()
    if RS.data.countsStamp ~= self.helloStamp then self:Hello() end
end

local function HelloText()
    return "H" .. VERSION .. "," .. RS.data.install .. "," .. (RS.data.countsStamp or 0)
end

function Share:Hello()
    if not Enabled() then return end
    self.helloStamp = RS.data.countsStamp
    local msg = HelloText()
    if IsInGuild() then Send("GUILD", nil, msg) end
    local group = GroupType()
    if group then Send(group, nil, msg) end
    online = {}
    for _, f in ipairs(Friends()) do
        online[f[1] .. tostring(f[2])] = true
        Send(f[1], f[2], msg)
    end
end

-- Someone joined the group: one message to the group reaches them
function Share:RosterChanged()
    local group = GroupType()
    local now, joined = {}, false
    for i = 1, group and GetNumGroupMembers() or 0 do
        local name = GetRaidRosterInfo(i)
        if name and not RS.IsSecret(name) then
            now[name] = true
            if roster and not roster[name] then joined = true end
        end
    end
    roster = now
    if joined and Enabled() then Send(group, nil, HelloText()) end
end

-- A friend or Battle.net friend came online: tell just them
function Share:FriendsChanged()
    if not online or not Enabled() then return end
    local now = {}
    for _, f in ipairs(Friends()) do
        local key = f[1] .. tostring(f[2])
        now[key] = true
        if not online[key] then Send(f[1], f[2], HelloText()) end
    end
    online = now
end

function Share:SendData(chatType, target)
    local data = self:Serialize()
    local n = math.max(1, math.ceil(#data / CHUNK))
    local head = "D" .. VERSION .. "," .. RS.data.install .. "," .. (RS.data.countsStamp or 0) .. ","
    for i = 1, n do
        Send(chatType, target, head .. i .. "," .. n .. "," .. data:sub((i - 1) * CHUNK + 1, i * CHUNK))
    end
end

-- Receiving -------------------------------------------------------------------

-- Where to answer: a whisper for guild and group messages, the same Battle.net account for those
local function ReplyTarget(chatType, sender, bnAccount)
    if chatType == "BN" then return "BN", bnAccount end
    return "WHISPER", sender
end

function Share:OnMessage(msg, chatType, sender, bnAccount)
    if not Enabled() then return end
    local kind, version, install, stamp, rest = msg:match("^(%a)(%d+),(%x+),(%d+),?(.*)$")
    stamp = tonumber(stamp)
    if not kind or version ~= VERSION or install == RS.data.install or not stamp then return end
    local shared = RS.data.shared
    if kind == "H" then
        -- they have newer counts than we stored: ask once per stamp
        if stamp > ((shared[install] and shared[install].stamp) or 0) and asked[install] ~= stamp then
            asked[install] = stamp
            local t, target = ReplyTarget(chatType, sender, bnAccount)
            Send(t, target, "R" .. VERSION .. "," .. RS.data.install .. "," .. ((shared[install] and shared[install].stamp) or 0))
            -- and tell them about ours, so both sides catch up
            Send(t, target, HelloText())
        end
    elseif kind == "R" then
        if (RS.data.countsStamp or 0) > stamp and GetTime() - (answered[sender] or -999) > 300 then
            answered[sender] = GetTime()
            self:SendData(ReplyTarget(chatType, sender, bnAccount))
        end
    elseif kind == "D" then
        local i, n, chunk = rest:match("^(%d+),(%d+),(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not i or not n or n > 200 or i > n then return end
        local inc = incoming[install]
        if not inc or inc.stamp ~= stamp then
            inc = { stamp = stamp, n = n, parts = {}, got = 0 }
            incoming[install] = inc
        end
        if not inc.parts[i] then
            inc.parts[i] = chunk
            inc.got = inc.got + 1
        end
        if inc.got == inc.n then
            incoming[install] = nil
            shared[install] = { stamp = stamp, from = sender, counts = Share.Parse(table.concat(inc.parts)) }
            RS.sharedChanged = true
        end
    end
end

function Share:CHAT_MSG_ADDON(_, prefix, msg, chatType, sender)
    if RS.IsSecret(prefix, msg, chatType, sender) or prefix ~= PREFIX or type(msg) ~= "string" then return end
    self:OnMessage(msg, chatType, sender)
end

function Share:BN_CHAT_MSG_ADDON(_, prefix, msg, _, bnAccount)
    if RS.IsSecret(prefix, msg, bnAccount) or prefix ~= PREFIX or type(msg) ~= "string" then return end
    self:OnMessage(msg, "BN", nil, bnAccount)
end

function Share:GROUP_JOINED()
    roster = nil
    self:ScheduleTimer("Hello", 5)
end

function Share:OnEnable()
    if not RS.data.install then
        RS.data.install = ("%08x"):format(math.random(0, 0x7fffffff))
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("BN_CHAT_MSG_ADDON")
    self:RegisterEvent("GROUP_JOINED")
    self:RegisterBucketEvent("GROUP_ROSTER_UPDATE", 3, "RosterChanged")
    self:RegisterBucketEvent({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" }, 5, "FriendsChanged")
    self:RosterChanged()
    self:ScheduleTimer("Hello", 30)
    self:ScheduleRepeatingTimer("HelloIfChanged", HELLO_EVERY)
end
