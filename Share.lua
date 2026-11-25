-- Craftseeker: trades loot counts with every other Craftseeker user: a hidden channel, the guild, the group, friends
local _, CS = ...
local Share = CS:NewModule("Share", "AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0")

local PREFIX = "Craftseeker"
local VERSION = "1"
local CHUNK = 200          -- addon messages carry 255 bytes; the rest is the header
local HELLO_EVERY = 900    -- announce our counts this often
local MAX_OPENED = 300     -- one install never outweighs everyone else
local MAX_PROVEN = 1000    -- proven recipes one install sends or we keep
local MAX_FRIENDS = 10
local CHANNEL = "CraftseekerShare"
local REPLIES = 6          -- data replies per REPLY_WINDOW seconds, however many ask
local REPLY_WINDOW = 600
local MAX_PEERS = 50       -- installs whose counts we keep, the most recently heard first
local NEW_PER_SENDER = 3   -- installs a day one sender may bring that we've never seen
local incoming = {}        -- [install] = { stamp, n, parts = {}, at }
local INCOMING_TTL, INCOMING_MAX = 120, 20  -- unfinished transfers are dropped after this, and never more than this many
local asked = {}           -- [install] = stamp requested this session
local answered = {}        -- [sender] = GetTime() of our last data reply
local roster, online      -- group members and online friends at the last look; nil until the first
local channelId, channelOk, pingToken
local replies = {}         -- GetTime() of recent data replies
local requests = {}        -- GetTime() of recent data requests
local REQUESTS = 3         -- data requests per minute: a busy channel answers with many hellos at once
local BROADCAST_EVERY = 1800 -- our data on the channel, for the opposite faction, at most this often
local lastBroadcast = -BROADCAST_EVERY
-- What sharing heard and sent this session, for /cs status
local heard = { hellos = {}, installs = {}, opposite = {}, asked = {}, data = {}, replies = 0, broadcasts = 0 }
local function Tally(t, key) t[key] = (t[key] or 0) + 1 end
local Deflate = LibStub("LibDeflate")

local function Enabled()
    return CS.data.settings.share
end

local function GroupType()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Friends()
    local list, seen = {}, {}
    local count = C_FriendList.GetNumFriends() or 0
    for i = 1, CS.IsSecret(count) and 0 or count do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and not CS.IsSecret(info.name) and info.connected and info.name and info.name ~= "" then
            seen[info.name] = true
            list[#list + 1] = { "WHISPER", info.name }
        end
    end
    local bn = BNGetNumFriends() or 0
    for i = 1, CS.IsSecret(bn) and 0 or bn do
        for a = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
            local g = C_BattleNet.GetFriendGameAccountInfo(i, a)
            if g and not CS.IsSecret(g.clientProgram, g.wowProjectID, g.isOnline, g.gameAccountID, g.characterName)
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

local function Send(chatType, target, msg, prio, onSent)
    CS.Transmit(PREFIX, chatType, target, msg, prio, onSent)
end

local GATHER_PROFS = { Skinning = true, Mining = true, Herbalism = true, Chest = true, Container = true }

-- Zone names can hold the separators, so ",", ";", ":" and "%" travel as %XX
local function Escape(text)
    return (text:gsub("[%%,;:]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- Text from other players never carries "|" codes into our window
local function Unescape(text)
    text = text:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    if text == "" or #text > 60 or text:find("|", 1, true) then return nil end
    return text
end

local function ParsePin(field)
    local m, x, y = (field or ""):match("^@(%d+):(%d+):(%d+)$")
    m, x, y = tonumber(m), tonumber(x), tonumber(y)
    if m and x > 0 and x < 1000 and y > 0 and y < 1000 then return { m, x, y } end
end

local function ParseZones(fields, from, cap)
    local out = {}
    for i = from, #fields do
        local zone, n = fields[i]:match("^(.+):(%d+)$")
        zone, n = zone and Unescape(zone), tonumber(n)
        if zone and n and n > 0 then out[zone] = math.min(n, cap) end
    end
    return out
end

-- Our counts as text: "npc,opened,item:drops,...;" for creatures that matter to drop rates
-- Receivers take at most 200 chunks, so the text stops short of that, most useful entries first
local MAX_TEXT = 200 * CHUNK - 1000

function Share:Serialize()
    local parts, size = {}, 0
    local function Add(fields)
        local entry = table.concat(fields, ",")
        if size + #entry + 1 > MAX_TEXT then return end
        parts[#parts + 1] = entry
        size = size + #entry + 1
    end
    for npc, c in pairs(CS.data.counts) do
        if (c.opened or 0) > 0 and (c.items or CS:IsRelevantNpc(npc)) then
            local fields = { npc, c.opened }
            for item, n in pairs(c.items or {}) do fields[#fields + 1] = item .. ":" .. n end
            Add(fields)
        end
    end
    -- vendor prices as "v<npc>,item:copper:stack,...": older versions skip an entry that doesn't start with a number
    local byNpc = {}
    for item, vendors in pairs(CS.data.prices) do
        for npc, p in pairs(vendors) do
            byNpc[npc] = byNpc[npc] or { "v" .. npc }
            table.insert(byNpc[npc], item .. ":" .. p[1] .. ":" .. p[2])
        end
    end
    for _, fields in pairs(byNpc) do Add(fields) end
    -- gathering as "k<npc>,profession,times,,item:drops,..." (corpses), "g<object>,profession,times,name,..." (nodes) and
    -- "c<item>,Container,times,,..." (containers; older versions skip it)
    for kind, book in pairs(CS.data.gather) do
        for id, e in pairs(book) do
            if e.k > 0 and next(e.i) then
                local fields = { kind .. id, e.p or "", e.k, Escape(e.n or "") }
                for item, n in pairs(e.i) do fields[#fields + 1] = item .. ":" .. n end
                Add(fields)
            end
        end
    end
    -- object places as "o<object>,@map:x:y,zone:times,...", zone names escaped
    for id, zones in pairs(CS.data.objects) do
        local pin = CS.data.objectPins[id]
        local fields = { "o" .. id, pin and ("@%d:%d:%d"):format(pin[1], pin[2], pin[3]) or "@" }
        for zone, n in pairs(zones) do fields[#fields + 1] = Escape(zone) .. ":" .. n end
        Add(fields)
    end
    -- quests as "q<quest>,name,giver,factions,item,...", for quests rewarding reagents or recipe items
    for id, q in pairs(CS.data.quests) do
        local fields = { "q" .. id, Escape(q.n or ""), q.g or 0, q.s or 0 }
        for item in pairs(q.i) do fields[#fields + 1] = item end
        Add(fields)
    end
    -- recipes our game proved that the built-in data hides or lacks, as "pr,<recipe>,..." (older versions skip it)
    local proven = {}
    for id in pairs(CS.data.proven) do
        if CS:NeedsProof(id) then proven[#proven + 1] = id end
    end
    table.sort(proven)
    for i = 1, math.min(#proven, MAX_PROVEN), 40 do
        Add({ "pr", table.concat(proven, ",", i, math.min(i + 39, #proven, MAX_PROVEN)) })
    end
    -- creatures as "n<npc>,name,lo,hi,@map:x:y,zone:times,..."
    for npc, e in pairs(CS.data.npcs) do
        local fields = { "n" .. npc, Escape(e.n or ""), e.lo or 0, e.hi or 0,
            e.p and ("@%d:%d:%d"):format(e.p[1], e.p[2], e.p[3]) or "@" }
        for zone, n in pairs(e.z or {}) do fields[#fields + 1] = Escape(zone) .. ":" .. n end
        Add(fields)
        -- rank and faction in an entry of their own ("f<npc>,rank,faction"), which 1.0.0 skips
        if e.r or e.f then Add({ "f" .. npc, e.r or 0, e.f or 0 }) end
    end
    return table.concat(parts, ";")
end

-- Their counts and vendor prices back, checked: whole numbers only, drops never above corpses, at most MAX_OPENED
-- corpses each, prices below 10,000 gold
function Share.Parse(text)
    local counts, prices, objects, objectPins, npcs, gather, quests = {}, {}, {}, {}, {}, { k = {}, g = {}, c = {} }, {}
    local proven, nProven = {}, 0
    for entry in text:gmatch("[^;]+") do
        local fields = { strsplit(",", entry) }
        if fields[1] == "pr" then
            for i = 2, #fields do
                local id = tonumber(fields[i])
                if id and id > 0 and id < 2 ^ 31 and id == math.floor(id) and nProven < MAX_PROVEN and not proven[id] then
                    proven[id], nProven = true, nProven + 1
                end
            end
        end
        local gkind, gid = fields[1]:match("^([kgc])(%d+)$")
        local times = tonumber(fields[3])
        gid = tonumber(gid)
        if gkind and gid and GATHER_PROFS[fields[2]] and times and times > 0 and times == math.floor(times) then
            local scale = times > MAX_OPENED and MAX_OPENED / times or 1
            local e = { p = fields[2], k = math.floor(times * scale + 0.5), n = fields[4] and Unescape(fields[4]), i = {} }
            for i = 5, #fields do
                local item, n = fields[i]:match("^(%d+):(%d+)$")
                item, n = tonumber(item), tonumber(n)
                if item and n and n <= times then e.i[item] = math.floor(n * scale + 0.5) end
            end
            gather[gkind][gid] = e
        end
        local object = tonumber(fields[1]:match("^o(%d+)$"))
        if object then
            objectPins[object] = ParsePin(fields[2])
            objects[object] = ParseZones(fields, 3, MAX_OPENED)
        end
        local npc = tonumber(fields[1]:match("^n(%d+)$"))
        if npc and #fields >= 5 then
            local lo, hi = tonumber(fields[3]), tonumber(fields[4])
            local e = npcs[npc] or {}
            npcs[npc] = e
            e.n, e.lo = Unescape(fields[2]), lo and lo > 0 and lo <= 100 and lo or nil
            e.hi, e.p, e.z = hi and hi > 0 and hi <= 100 and hi or nil, ParsePin(fields[5]), ParseZones(fields, 6, MAX_OPENED)
        end
        local quest = tonumber(fields[1]:match("^q(%d+)$"))
        if quest and #fields >= 5 then
            local giver, sides = tonumber(fields[3]), tonumber(fields[4])
            local q = { n = Unescape(fields[2]), g = giver and giver > 0 and giver or nil,
                s = sides and sides >= 1 and sides <= 3 and sides or nil, i = {} }
            for i = 5, math.min(#fields, 20) do
                local item = tonumber(fields[i])
                if item and item > 0 then q.i[item] = true end
            end
            if q.n and q.s and next(q.i) then quests[quest] = q end
        end
        local ranked = tonumber(fields[1]:match("^f(%d+)$"))
        if ranked then
            local rank, faction = tonumber(fields[2]), tonumber(fields[3])
            npcs[ranked] = npcs[ranked] or { z = {} }
            npcs[ranked].r = rank and rank >= 1 and rank <= 4 and rank or nil
            npcs[ranked].f = faction and faction >= 1 and faction <= 3 and faction or nil
        end
        local vendor = tonumber(fields[1]:match("^v(%d+)$"))
        for i = 2, vendor and #fields or 0 do
            local item, copper, stack = fields[i]:match("^(%d+):(%d+):(%d+)$")
            item, copper, stack = tonumber(item), tonumber(copper), tonumber(stack)
            if item and copper and copper > 0 and copper < 1e8 and stack and stack >= 1 and stack <= 1000 then
                prices[item] = prices[item] or {}
                prices[item][vendor] = { copper, stack }
            end
        end
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
    return counts, prices, objects, objectPins, npcs, gather, quests, proven
end

-- Keeps the newest MAX_PEERS installs and drops those not heard from in a month
function Share.Trim()
    local shared, now, list = CS.data.shared, time(), {}
    for install, peer in pairs(shared) do
        peer.at = peer.at or now
        if now - peer.at > CS.PEER_MAX_AGE then
            shared[install] = nil
        else
            list[#list + 1] = install
        end
    end
    table.sort(list, function(a, b) return shared[a].at > shared[b].at end)
    for i = MAX_PEERS + 1, #list do shared[list[i]] = nil end
    CS:CountsChanged(false, "shared")
end

-- Peers who log in later announce themselves and get ours back, so a repeat is only needed after new loot
function Share:HelloIfChanged()
    if CS.data.countsStamp ~= self.helloStamp then self:Hello() end
end

-- "A" or "H": whispers never cross factions, so the opposite faction asks and answers on the channel instead
local function MyFaction()
    return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function HelloText()
    return "H" .. VERSION .. "," .. CS.data.install .. "," .. (CS.data.countsStamp or 0) .. "," .. MyFaction()
end

function Share:Hello()
    if not Enabled() then return end
    self.helloStamp = CS.data.countsStamp
    local msg = HelloText()
    if IsInGuild() then Send("GUILD", nil, msg) end
    local group = GroupType()
    if group then Send(group, nil, msg) end
    if channelOk then Send("CHANNEL", channelId, msg) end
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
        if name and not CS.IsSecret(name) then
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

-- Data goes out compressed ("Z") to peers that said they read it, plain ("D") to older versions
function Share:SendData(chatType, target, compressed)
    local data = self:Serialize()
    local kind = "D"
    if compressed then
        data = Deflate:EncodeForWoWAddonChannel(Deflate:CompressDeflate(data))
        kind = "Z"
    end
    local n = math.max(1, math.ceil(#data / CHUNK))
    local head = kind .. VERSION .. "," .. CS.data.install .. "," .. (CS.data.countsStamp or 0) .. ","
    for i = 1, n do
        Send(chatType, target, head .. i .. "," .. n .. "," .. data:sub((i - 1) * CHUNK + 1, i * CHUNK), "BULK")
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
    -- our own ping coming back proves the channel carries addon messages
    if kind == "P" and chatType == "CHANNEL" and install == CS.data.install and stamp == pingToken then
        channelOk = true
        CS:Debug("sharing channel %s works (self-test passed)", CHANNEL)
        self:Hello()
        return
    end
    if not kind or version ~= VERSION or install == CS.data.install or not stamp then return end
    local shared = CS.data.shared
    if kind == "H" then
        Tally(heard.hellos, chatType)
        heard.installs[install] = true
        if rest ~= "" and rest ~= MyFaction() then heard.opposite[install] = true end
        -- they have newer counts than we stored: ask once per stamp, a few peers a minute
        local now = GetTime()
        while requests[1] and now - requests[1] > 60 do table.remove(requests, 1) end
        if stamp > ((shared[install] and shared[install].stamp) or 0) and asked[install] ~= stamp and #requests < REQUESTS then
            asked[install] = stamp
            requests[#requests + 1] = now
            local have = (shared[install] and shared[install].stamp) or 0
            if chatType == "CHANNEL" and rest ~= "" and rest ~= MyFaction() then
                -- the opposite faction: ask on the channel, naming their install ("Q" is unknown to older versions)
                if channelOk then
                    Send("CHANNEL", channelId, ("Q%s,%s,%d,%s,z"):format(VERSION, CS.data.install, have, install))
                    Tally(heard.asked, "channel")
                end
                return
            end
            local t, target = ReplyTarget(chatType, sender, bnAccount)
            -- ",z": we read compressed data
            Send(t, target, "R" .. VERSION .. "," .. CS.data.install .. "," .. have .. ",z")
            Tally(heard.asked, t == "BN" and "Battle.net" or "whisper")
            -- and tell them about ours, so both sides catch up
            Send(t, target, HelloText())
        end
    elseif kind == "Q" then
        -- asked on the channel for our data: everyone listening gets it, so once per BROADCAST_EVERY at most
        local target = rest:match("^(%x+)")
        local now = GetTime()
        if chatType == "CHANNEL" and target == CS.data.install and channelOk and (CS.data.countsStamp or 0) > stamp
            and now - lastBroadcast > BROADCAST_EVERY then
            lastBroadcast = now
            heard.broadcasts = heard.broadcasts + 1
            CS:Debug("broadcasting our counts on the channel for the opposite faction")
            self:SendData("CHANNEL", channelId, true)
        end
    elseif kind == "R" then
        -- everyone on the channel may ask at once: a few replies per ten minutes, one per player per five
        local now = GetTime()
        while replies[1] and now - replies[1] > REPLY_WINDOW do table.remove(replies, 1) end
        -- Battle.net messages carry an account number, not a name
        local who = sender or ("bn:" .. tostring(bnAccount))
        if (CS.data.countsStamp or 0) > stamp and now - (answered[who] or -999) > 300 and #replies < REPLIES then
            answered[who] = now
            replies[#replies + 1] = now
            local t, target = ReplyTarget(chatType, sender, bnAccount)
            heard.replies = heard.replies + 1
            CS:Debug("sending our counts to %s (%s)", tostring(sender or bnAccount), chatType)
            self:SendData(t, target, rest == "z")
        end
    elseif kind == "D" or kind == "Z" then
        local i, n, chunk = rest:match("^(%d+),(%d+),(.*)$")
        i, n = tonumber(i), tonumber(n)
        if not i or not n or n > 200 or i > n then return end
        local inc = incoming[install]
        if not inc or inc.stamp ~= stamp or inc.kind ~= kind then
            local now, open, oldest = GetTime(), 0, nil
            for key, other in pairs(incoming) do
                if now - other.at > INCOMING_TTL then
                    incoming[key] = nil
                else
                    open = open + 1
                    if not oldest or other.at < incoming[oldest].at then oldest = key end
                end
            end
            if open >= INCOMING_MAX then incoming[oldest] = nil end
            inc = { stamp = stamp, n = n, parts = {}, got = 0, kind = kind, at = now }
            incoming[install] = inc
        end
        if not inc.parts[i] then
            inc.parts[i] = chunk
            inc.got = inc.got + 1
        end
        if inc.got == inc.n then
            incoming[install] = nil
            if not shared[install] and not CS.AllowNewPeer(sender or tostring(bnAccount), NEW_PER_SENDER) then return end
            local text = table.concat(inc.parts)
            if kind == "Z" then
                local raw = Deflate:DecodeForWoWAddonChannel(text)
                text = raw and Deflate:DecompressDeflate(raw)
                if not text then return end
            end
            Tally(heard.data, chatType)
            CS:Debug("counts received from %s (%s, install %s)", tostring(sender or bnAccount), chatType, install)
            local counts, prices, objects, objectPins, npcs, gather, quests, proven = Share.Parse(text)
            shared[install] = { stamp = stamp, from = sender, at = time(), counts = counts, prices = prices,
                objects = objects, objectPins = objectPins, npcs = npcs, gather = gather, quests = quests, proven = proven }
            Share.Trim()
            CS:CountsChanged(false, "shared")
        end
    end
end

function Share:CHAT_MSG_ADDON(_, prefix, msg, chatType, sender)
    if CS.IsSecret(prefix, msg, chatType, sender) or prefix ~= PREFIX or type(msg) ~= "string" then return end
    self:OnMessage(msg, chatType, sender)
end

function Share:BN_CHAT_MSG_ADDON(_, prefix, msg, _, bnAccount)
    if CS.IsSecret(prefix, msg, bnAccount) or prefix ~= PREFIX or type(msg) ~= "string" then return end
    self:OnMessage(msg, "BN", nil, bnAccount)
end

-- Lines for /cs status: whether the channel works, and what was heard and sent this session
local function Breakdown(t)
    local out = {}
    for key, n in pairs(t) do out[#out + 1] = key:lower() .. " " .. n end
    table.sort(out)
    return #out > 0 and table.concat(out, ", ") or "none"
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Share:Status()
    local channel = not Enabled() and "sharing is off (/cs share)"
        or not channelId and "not joined"
        or channelOk and ("joined as channel %d, self-test passed"):format(channelId)
        or channelOk == false and ("joined as channel %d, self-test failed: addon messages don't cross it"):format(channelId)
        or ("joined as channel %d, self-test waiting"):format(channelId)
    local wait = BROADCAST_EVERY - (GetTime() - lastBroadcast)
    return {
        ("Channel %s: %s. You are %s."):format(CHANNEL, channel, MyFaction() == "H" and "Horde" or "Alliance"),
        ("Hellos heard: %s, from %d installs, %d of them the opposite faction."):format(Breakdown(heard.hellos),
            Count(heard.installs), Count(heard.opposite)),
        ("Data asked for: %s. Data received: %s."):format(Breakdown(heard.asked), Breakdown(heard.data)),
        ("Sent: %d replies, %d channel broadcasts%s."):format(heard.replies, heard.broadcasts,
            wait > 0 and heard.broadcasts > 0 and (" (next in %d min)"):format(math.ceil(wait / 60)) or ""),
        ("Kept: counts from %d other Craftseeker users."):format(Count(CS.data.shared)),
    }
end

-- The hidden channel reaches Craftseeker users who share no guild, group or friends list
function Share:JoinChannel()
    if not Enabled() or channelId or channelOk == false then return end
    pcall(JoinTemporaryChannel, CHANNEL)
    self:ScheduleTimer("ChannelJoined", 3)
end

function Share:ChannelJoined()
    channelId = CS.ChannelNumber(CHANNEL)
    if not channelId then return end
    CS.HideChannel(CHANNEL)
    local token = math.random(100000, 999999)
    pingToken = token
    -- the wait starts once the ping leaves: messaging lockdown can hold it back for a whole boss fight
    Send("CHANNEL", channelId, "P" .. VERSION .. "," .. CS.data.install .. "," .. token, nil, function()
        self:ScheduleTimer("ChannelChecked", 20, token)
    end)
end

-- No ping back: this client doesn't carry addon messages there, so the channel is left until the next login
function Share:ChannelChecked(token)
    if token ~= pingToken or channelOk or not channelId then return end
    CS:Debug("sharing channel %s carries no addon messages; left until the next login", CHANNEL)
    channelOk, channelId = false, nil
    pcall(LeaveChannelByName, CHANNEL)
end

-- The settings checkbox and /cs share: leave at once; join and announce at most once a minute, so flipping the switch
-- never floods the channel, the guild, the group or friends
local APPLY_GAP = 60
local lastOn = -APPLY_GAP
function Share:Apply()
    if self.pendingOn then
        self:CancelTimer(self.pendingOn)
        self.pendingOn = nil
    end
    if Enabled() then
        local wait = lastOn + APPLY_GAP - GetTime()
        if wait > 0 then
            self.pendingOn = self:ScheduleTimer("Apply", wait)
            return
        end
        lastOn = GetTime()
        self:JoinChannel()
        self:Hello()
    else
        -- turned off and on again, the channel gets another try
        if channelId then pcall(LeaveChannelByName, CHANNEL) end
        channelId, channelOk = nil, nil
    end
end

function Share:GROUP_JOINED()
    roster = nil
    self:ScheduleTimer("Hello", 5)
end

function Share:OnEnable()
    if not CS.data.install then
        CS.data.install = ("%08x"):format(math.random(0, 0x7fffffff))
    end
    Share.Trim()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("BN_CHAT_MSG_ADDON")
    self:RegisterEvent("GROUP_JOINED")
    self:RegisterBucketEvent("GROUP_ROSTER_UPDATE", 3, "RosterChanged")
    self:RegisterBucketEvent({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" }, 5, "FriendsChanged")
    self:RosterChanged()
    self:ScheduleTimer("JoinChannel", 8)
    self:ScheduleTimer("Hello", 30)
    self:ScheduleRepeatingTimer("HelloIfChanged", HELLO_EVERY)
end
