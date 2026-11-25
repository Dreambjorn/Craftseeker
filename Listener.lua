-- Craftseeker: reads the loot counts two other loot addons trade on Forever, so the drop rates grow with theirs too
local _, CS = ...
local Listener = CS:NewModule("Listener", "AceEvent-3.0", "AceTimer-3.0")

local TICK = 1.1

local function Enqueue(prefix, chatType, target, msg)
    CS.Transmit(prefix, chatType, target, msg, "NORMAL")
end

local function NpcFromGUID(guid)
    if not guid or CS.IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

local JOIN_GAP = 4
local function JoinHidden(name)
    pcall(JoinTemporaryChannel, name)
end

-- Drop Tables -----------------------------------------------------------------
-- Its users ask on a hidden channel about the mob they target ("Q|asker|npc|held") and whisper their counts back to
-- whoever asked ("D|origin|records"); "C|asker|npc" calls further answers off. Group members also send "D|" to the
-- group. Records are ";"-joined, numbers base 36: M<npc>.<bucket>.<kills>.<lootable>.<opened>.<money...> per level
-- bucket and I<npc>.<bucket>.<item>.<drops>.<qty>.<min>.<max>; the level, map and name records are skipped.
local DT_PREFIX, DT_CHANNEL = "DropTables", "DropTablesShare"
local DT_GAP = 5            -- seconds between two questions, the pace Drop Tables keeps
local DT_PAUSES = { 120, 300, 600, 1800 }  -- before the same mob again: answered, then each unanswered try
local DT_WINDOW = 120       -- answers are taken this long after the question
local DT_ENOUGH = 100       -- looted corpses of a mob worth asking for
local DT_ANSWERS = 10       -- installs that answered before the call-off
local DT_SOURCES = 12       -- installs kept per mob
local DT_FIELDS = { M = 9, I = 7, L = 3, Z = 3, P = 4 }
local dtChannel
local dtLast = -DT_GAP
local dtWaiting = {}        -- mobs waiting for the gap, newest last
local dtAsked = {}          -- [npc] = { at, step, answers, origins = {}, calledOff }
local dtKnown = {}          -- installs we hold counts of, filled at login and as answers arrive

local function DTEnabled()
    return CS.data.settings.dt
end

-- The records of one message, all about one mob, or nil when anything in it is malformed or impossible
function Listener.DecodeDT(body)
    local recs, npc = {}, nil
    for text in (body .. ";"):gmatch("([^;]*);") do
        local kind = text:sub(1, 1)
        local id
        if kind == "N" then
            id = CS.FromBase36(text:match("^N([0-9a-z]+)%.") or "")
            if not id then return nil end
        else
            local want = DT_FIELDS[kind]
            if not want then return nil end
            local f = {}
            for v in (text:sub(2) .. "."):gmatch("([^.]*)%.") do
                if v == "" then
                    f[#f + 1] = false
                else
                    f[#f + 1] = CS.FromBase36(v)
                    if not f[#f] then return nil end
                end
            end
            if #f ~= want or not f[1] then return nil end
            id = f[1]
            if kind == "M" then
                local bucket, kills, lootable, opened = f[2], f[3], f[4], f[5]
                if not (bucket and kills and lootable and opened) or bucket < 1 or bucket > 6
                    or lootable > kills or opened > lootable then return nil end
                recs[#recs + 1] = { kind = "M", bucket = bucket, kills = kills, lootable = lootable, opened = opened }
            elseif kind == "I" then
                local bucket, item, drops = f[2], f[3], f[4]
                if not (bucket and item and drops) or bucket < 1 or bucket > 6 or drops < 1 then return nil end
                recs[#recs + 1] = { kind = "I", bucket = bucket, item = item, drops = drops }
            end
        end
        if npc and id ~= npc then return nil end
        npc = id
    end
    return npc, recs
end

-- An S| message: one mob's skinning, "K<npc>.<skinned>" and "U<npc>.<item>.<drops>.<qty>.<min>.<max>" records
function Listener.DecodeDTSkins(body)
    local npc, skinned, items = nil, nil, {}
    for text in (body .. ";"):gmatch("([^;]*);") do
        local kind, rest = text:sub(1, 1), text:sub(2)
        local f = {}
        for v in (rest .. "."):gmatch("([^.]*)%.") do f[#f + 1] = v end
        local id = CS.FromBase36(f[1] or "")
        if not id or (npc and id ~= npc) then return nil end
        npc = id
        if kind == "K" and #f == 2 then
            skinned = CS.FromBase36(f[2])
        elseif kind == "U" and #f == 6 then
            local item, drops = CS.FromBase36(f[2]), CS.FromBase36(f[3])
            if not item or not drops then return nil end
            items[item] = drops
        else
            return nil
        end
    end
    if not npc or not skinned or skinned < 1 then return nil end
    for _, drops in pairs(items) do
        if drops > skinned then return nil end
    end
    return npc, skinned, items
end

local function DTSkinStore(origin, npc, skinned, items)
    local kept = {}
    for item, drops in pairs(items) do
        if CS:IsCountedItem(item) then kept[item] = drops end
    end
    if not next(kept) then return end
    local mobs = CS.data.bridges.dtSkins
    mobs[npc] = mobs[npc] or {}
    mobs[npc][origin] = { p = "Skinning", k = skinned, i = kept, at = time() }
    local count, fewest, smallest = 0, math.huge, nil
    for o, e in pairs(mobs[npc]) do
        count = count + 1
        if e.k < fewest then smallest, fewest = o, e.k end
    end
    if count > DT_SOURCES then mobs[npc][smallest] = nil end
    CS:CountsChanged()
end

local function DTKills(entry)
    local n = 0
    for _, m in pairs(entry.b) do n = n + m[1] end
    return n
end

-- Looted corpses of a mob over every install we hold
local function DTSample(npc)
    local n = 0
    for _, entry in pairs(CS.data.bridges.dt[npc] or {}) do
        for _, m in pairs(entry.b) do n = n + m[3] end
    end
    return n
end

-- A record replaces the one with the same key; only counted items are kept
local function DTStore(origin, npc, recs)
    local mobs = CS.data.bridges.dt
    mobs[npc] = mobs[npc] or {}
    local entry = mobs[npc][origin] or { b = {}, i = {} }
    for _, r in ipairs(recs) do
        if r.kind == "M" then
            entry.b[r.bucket] = { r.kills, r.lootable, r.opened }
        elseif r.kind == "I" and CS:IsCountedItem(r.item) then
            entry.i[r.bucket] = entry.i[r.bucket] or {}
            entry.i[r.bucket][r.item] = r.drops
        end
    end
    entry.at = time()
    mobs[npc][origin] = entry
    dtKnown[origin] = true
    CS:CountsChanged()
    -- too many installs for one mob: the one with the fewest kills goes
    local count, smallest, fewest = 0, nil, math.huge
    for o, e in pairs(mobs[npc]) do
        count = count + 1
        local k = DTKills(e)
        if k < fewest then smallest, fewest = o, k end
    end
    if count > DT_SOURCES then mobs[npc][smallest] = nil end
end

-- The question names the installs we already hold (id prefix and kills), as many as fit in one message
local function DTQuestion(npc)
    local head = ("Q|%s|%s|"):format(CS.data.dtInstall, CS.Base36(npc))
    local held, room = {}, 255 - #head
    for origin, entry in pairs(CS.data.bridges.dt[npc] or {}) do
        local tag = origin:sub(1, 6) .. CS.Base36(DTKills(entry))
        room = room - #tag - (#held > 0 and 1 or 0)
        if room < 0 then break end
        held[#held + 1] = tag
    end
    return head .. table.concat(held, ",")
end

function Listener:AskDT(npc)
    if not DTEnabled() or not dtChannel or not CS:IsRelevantNpc(npc) then return end
    local now, last = GetTime(), dtAsked[npc]
    if last and now - last.at < DT_PAUSES[last.answers > 0 and 1 or last.step] then return end
    if DTSample(npc) >= DT_ENOUGH and last then return end
    if now - dtLast < DT_GAP then
        for _, waiting in ipairs(dtWaiting) do if waiting == npc then return end end
        dtWaiting[#dtWaiting + 1] = npc
        if #dtWaiting > 3 then table.remove(dtWaiting, 1) end
        -- the ticker runs only while questions wait
        if not self.ticker then self.ticker = self:ScheduleRepeatingTimer("Tick", TICK) end
        return
    end
    dtLast = now
    dtAsked[npc] = { at = now, answers = 0, from = {},
        step = not last and 1 or last.answers > 0 and 1 or math.min(last.step + 1, #DT_PAUSES) }
    Enqueue(DT_PREFIX, "CHANNEL", dtChannel, DTQuestion(npc))
end

function Listener:OnDT(msg, chatType, sender)
    local kind, origin, body = msg:match("^([DSQC])|(%x+)|(.*)$")
    if not kind or kind == "Q" or kind == "C" or #origin ~= 16 or origin == CS.data.dtInstall then return end
    local npc, recs, skinned
    if kind == "S" then
        npc, skinned, recs = Listener.DecodeDTSkins(body)
    else
        npc, recs = Listener.DecodeDT(body)
    end
    if not npc then return end
    local group = chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT"
    local question = dtAsked[npc]
    if not group then
        -- whispered answers only to a question we asked a moment ago
        if chatType ~= "WHISPER" or not question or GetTime() - question.at > DT_WINDOW then return end
        if question.calledOff and not question.from[origin] then return end
    end
    if not dtKnown[origin] and not CS.AllowNewPeer("dt:" .. sender, 3) then return end
    -- skinning comes after the same install's loot, so it never counts as a new answer
    if skinned then
        DTSkinStore(origin, npc, skinned, recs)
        CS:Debug("Drop Tables skinning counts for creature %d from %s", npc, sender)
        return
    end
    DTStore(origin, npc, recs)
    CS:Debug("Drop Tables counts for creature %d from %s", npc, sender)
    if not question or question.from[origin] then return end
    question.from[origin] = true
    question.answers = question.answers + 1
    -- enough installs or corpses: ask the others not to answer
    local enough = question.answers >= DT_ANSWERS or DTSample(npc) >= DT_ENOUGH
    if enough and not question.calledOff and dtChannel then
        question.calledOff = true
        Enqueue(DT_PREFIX, "CHANNEL", dtChannel, ("C|%s|%s"):format(CS.data.dtInstall, CS.Base36(npc)))
    end
end

-- Forever Drops ---------------------------------------------------------------
-- Its users announce what they hold ("H^origin^rev^version", "A^origin^rev") to the guild, the group and a hidden
-- channel; "W^origin^fromRev" whispered back asks for records newer than fromRev, which arrive as "R^origin^record"
-- and end with "E^origin^rev". Each message starts with 1 (whole), 2 (first piece), 3 (middle) or 4 (last).
-- A record is "~"-separated: key, revision, name, levels, times looted, ..., items "id:drops:qty,...", ...
local FD_PREFIX, FD_CHANNEL = "FDrops", "ForeverDropsShare"
local FD_PENDING, FD_TIMEOUT, FD_ORIGINS = 3, 60, 50
local fdChannel
local fdPending = {}        -- [origin] = { from, t }
local fdBuffers = {}        -- [sender:chat] = { pieces, at = time }
local FD_BUFFER_TTL, FD_BUFFERS = 60, 20

local function FDEnabled()
    return CS.data.settings.fd
end

-- A mob's record as { npc, rev, k = corpses looted, items = { [itemID] = drops } }, or nil
function Listener.ParseFD(text)
    if type(text) ~= "string" or #text > 4000 then return nil end
    local f = {}
    for v in (text .. "~"):gmatch("([^~]*)~") do f[#f + 1] = v end
    if #f ~= 11 and #f ~= 13 then return nil end
    -- M:<npc> corpse loot; K:<profession>:<npc> skinning, mining or herb gathering a corpse; G:<object> a node or chest
    local npc = tonumber(f[1]:match("^M:(%d+)$") or "")
    local prof, corpse = f[1]:match("^K:(%a+):(%d+)$")
    local node = tonumber(f[1]:match("^G:(%d+)$") or "")
    local gather = (corpse and "k") or (node and "g") or nil
    local id = npc or tonumber(corpse or "") or node
    local rev, k = tonumber(f[2]), tonumber(f[6])
    if not id or not rev or not k or k < 0 or k > 1000000 or k ~= math.floor(k) then return nil end
    if gather and not prof then
        for _, v in ipairs(f) do
            if v == "Mining" or v == "Herbalism" or v == "Chest" then prof = v end
        end
    end
    local items = {}
    for entry in f[10]:gmatch("[^,]+") do
        local id, drops = entry:match("^(%d+):(%d+):%d+$")
        id, drops = tonumber(id), tonumber(drops)
        if not id or not drops or drops > k then return nil end
        items[id] = drops
    end
    if gather then
        return { gather = gather, id = id, prof = prof or "Chest", name = f[3] ~= "" and f[3] or nil, rev = rev, k = k,
            items = items }
    end
    return { npc = npc, rev = rev, k = k, items = items }
end

local function FDStore(origin, rec)
    local peers = CS.data.bridges.fd
    local peer = peers[origin]
    local kept = {}
    for id, drops in pairs(rec.items) do
        if CS:IsCountedItem(id) then kept[id] = drops end
    end
    if not next(kept) and (rec.gather or not CS:IsRelevantNpc(rec.npc)) then return end
    if not peer then
        local count, oldest, oldestAt = 0, nil, math.huge
        for o, p in pairs(peers) do
            count = count + 1
            if (p.at or 0) < oldestAt then oldest, oldestAt = o, p.at or 0 end
        end
        if count >= FD_ORIGINS then peers[oldest] = nil end
        peer = { rev = 0, npcs = {} }
        peers[origin] = peer
    end
    if rec.gather then
        peer.gather = peer.gather or { k = {}, g = {} }
        local book = peer.gather[rec.gather]
        local old = book[rec.id]
        if old and old.r and old.r > rec.rev then return end
        book[rec.id] = { p = rec.prof, n = rec.name and #rec.name <= 60 and not rec.name:find("|", 1, true) and rec.name
            or nil, k = rec.k, i = kept, r = rec.rev }
        peer.at = time()
        CS:CountsChanged()
        return
    end
    local old = peer.npcs[rec.npc]
    if old and old.r and old.r > rec.rev then return end
    peer.npcs[rec.npc] = { k = rec.k, i = kept, r = rec.rev }
    peer.at = time()
    CS:CountsChanged()
end

function Listener:ConsiderFD(origin, rev, sender)
    rev = tonumber(rev)
    if not rev or not origin or #origin > 20 or not sender then return end
    local peer = CS.data.bridges.fd[origin]
    local known = peer and peer.rev or 0
    if rev <= known then return end
    local now, active = GetTime(), 0
    for o, p in pairs(fdPending) do
        if now - p.t > FD_TIMEOUT then fdPending[o] = nil else active = active + 1 end
    end
    if fdPending[origin] or active >= FD_PENDING then return end
    if not peer and not CS.AllowNewPeer("fd:" .. sender, 3) then return end
    fdPending[origin] = { from = sender, t = now }
    Enqueue(FD_PREFIX, "WHISPER", sender, "1W^" .. origin .. "^" .. known)
end

-- Only records from the player we asked count, and only until the transfer ends or goes quiet
local function Asked(origin, sender)
    local wait = fdPending[origin]
    return wait and wait.from == sender and wait or nil
end

local fdKinds = {
    H = function(self, origin, rest, sender) self:ConsiderFD(origin, rest:match("^(%d+)"), sender) end,
    R = function(_, origin, rest, sender)
        local wait = Asked(origin, sender)
        if not wait then return end
        wait.t = GetTime()
        local rec = Listener.ParseFD(rest)
        if rec then FDStore(origin, rec) end
    end,
    E = function(_, origin, rest, sender)
        if not Asked(origin, sender) then return end
        fdPending[origin] = nil
        local peer, rev = CS.data.bridges.fd[origin], tonumber(rest)
        if peer and rev then peer.rev = math.max(peer.rev, rev) end
        CS:Debug("Forever Drops counts received from %s", sender)
    end,
}
fdKinds.A = fdKinds.H

function Listener:HandleFD(payload, sender)
    local kind, origin, rest = payload:match("^(%a)%^([^%^]+)%^?(.*)$")
    local handle = kind and fdKinds[kind]
    if handle then handle(self, origin, rest, sender) end
end

local PIECE = { ["1"] = "whole", ["2"] = "first", ["3"] = "middle", ["4"] = "last" }
local MAX_PIECES = 16

function Listener:OnFD(msg, chatType, sender)
    local piece = PIECE[msg:sub(1, 1)]
    if not piece then return end
    local key, body = sender .. "\0" .. chatType, msg:sub(2)
    if piece == "whole" or piece == "first" then
        fdBuffers[key] = nil
        if piece == "whole" then
            self:HandleFD(body, sender)
            return
        end
        -- a sender who never finishes holds no memory for long
        local now, open = GetTime(), 0
        for k, b in pairs(fdBuffers) do
            if now - b.at > FD_BUFFER_TTL then fdBuffers[k] = nil else open = open + 1 end
        end
        if open < FD_BUFFERS then fdBuffers[key] = { body, at = now } end
        return
    end
    local parts = fdBuffers[key]
    if not parts or #parts >= MAX_PIECES then
        fdBuffers[key] = nil
        return
    end
    parts[#parts + 1] = body
    if piece == "last" then
        fdBuffers[key] = nil
        self:HandleFD(table.concat(parts), sender)
    end
end

-- Both ------------------------------------------------------------------------

function Listener:CHAT_MSG_ADDON(_, prefix, msg, chatType, sender)
    if CS.IsSecret(prefix, msg, chatType, sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    if prefix == DT_PREFIX and DTEnabled() then
        self:OnDT(msg, chatType, sender)
    elseif prefix == FD_PREFIX and FDEnabled() and sender ~= UnitName("player") then
        self:OnFD(msg, chatType, sender)
    end
end

function Listener:PLAYER_TARGET_CHANGED()
    local npc = NpcFromGUID(UnitGUID("target"))
    if npc then self:AskDT(npc) end
end

function Listener:Tick()
    if dtWaiting[1] and GetTime() - dtLast >= DT_GAP then self:AskDT(table.remove(dtWaiting, 1)) end
    if not dtWaiting[1] and self.ticker then
        self:CancelTimer(self.ticker)
        self.ticker = nil
    end
end

-- Joins or leaves the two hidden channels as the settings say: leaves at once, joins at most once a minute, as Share does
local APPLY_GAP = 60
local lastJoin = -APPLY_GAP
function Listener:Apply()
    if self.pendingJoin then
        self:CancelTimer(self.pendingJoin)
        self.pendingJoin = nil
    end
    if not DTEnabled() and dtChannel then
        pcall(LeaveChannelByName, DT_CHANNEL)
        dtChannel = nil
    end
    if not FDEnabled() and fdChannel then
        pcall(LeaveChannelByName, FD_CHANNEL)
        fdChannel = nil
    end
    local joinDT, joinFD = DTEnabled() and not dtChannel, FDEnabled() and not fdChannel
    if not joinDT and not joinFD then return end
    local wait = lastJoin + APPLY_GAP - GetTime()
    if wait > 0 then
        self.pendingJoin = self:ScheduleTimer("Apply", wait)
        return
    end
    lastJoin = GetTime()
    if joinDT then JoinHidden(DT_CHANNEL) end
    -- joins a few seconds apart: back-to-back joins draw the server's "doing that too fast"
    if joinFD then C_Timer.After(JOIN_GAP, function() JoinHidden(FD_CHANNEL) end) end
    self:ScheduleTimer("ChannelsJoined", JOIN_GAP + 3)
end

function Listener:ChannelsJoined()
    if DTEnabled() then
        dtChannel = CS.ChannelNumber(DT_CHANNEL)
        if dtChannel then CS.HideChannel(DT_CHANNEL) end
    end
    if FDEnabled() then
        fdChannel = CS.ChannelNumber(FD_CHANNEL)
        if fdChannel then CS.HideChannel(FD_CHANNEL) end
    end
end

-- Counts not refreshed in a month go at login
function Listener.Prune()
    local now, b = time(), CS.data.bridges
    for npc, origins in pairs(b.dt) do
        for origin, entry in pairs(origins) do
            entry.at = entry.at or now
            if now - entry.at > CS.PEER_MAX_AGE then origins[origin] = nil else dtKnown[origin] = true end
        end
        if not next(origins) then b.dt[npc] = nil end
    end
    for npc, origins in pairs(b.dtSkins) do
        for origin, entry in pairs(origins) do
            if now - (entry.at or now) > CS.PEER_MAX_AGE then origins[origin] = nil end
        end
        if not next(origins) then b.dtSkins[npc] = nil end
    end
    for origin, peer in pairs(b.fd) do
        peer.at = peer.at or now
        if now - peer.at > CS.PEER_MAX_AGE then b.fd[origin] = nil end
    end
    CS:CountsChanged()
end

-- Install ids and mobs held, for /cs stats
function Listener:Stats()
    local dtInstalls, fdPeers = {}, 0
    for _, origins in pairs(CS.data.bridges.dt) do
        for o in pairs(origins) do dtInstalls[o] = true end
    end
    for _ in pairs(CS.data.bridges.fd) do fdPeers = fdPeers + 1 end
    local n = 0
    for _ in pairs(dtInstalls) do n = n + 1 end
    return n, fdPeers
end

function Listener:OnEnable()
    if not CS.data.dtInstall then
        local parts = {}
        for i = 1, 4 do parts[i] = ("%04x"):format(math.random(0, 0xffff)) end
        CS.data.dtInstall = table.concat(parts)
    end
    Listener.Prune()
    C_ChatInfo.RegisterAddonMessagePrefix(DT_PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(FD_PREFIX)
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:ScheduleTimer("Apply", 10)
end
