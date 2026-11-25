-- Craftseeker: /cs profile wraps the addon's methods while running and reports time and memory per function
local _, CS = ...

local Profiler = { active = false, stats = {}, depth = 0, childMs = {}, childKB = {}, originals = {}, hitches = {} }
CS.Profiler = Profiler

local HITCH_MS = 25  -- a frame this long is logged with what Craftseeker did in it
local HITCH_MAX = 15
local TOP = 12
-- Library methods embedded in the addon and its modules; wrapping them would only add noise
local SKIP = { NewModule = true, GetModule = true, GetName = true, Enable = true, Disable = true, EnableModule = true,
    DisableModule = true, SetDefaultModuleLibraries = true, SetDefaultModuleState = true, SetDefaultModulePrototype = true,
    SetEnabledState = true, IterateModules = true, IterateEmbeds = true, IsEnabled = true, Print = true, Printf = true,
    RegisterEvent = true, UnregisterEvent = true, RegisterMessage = true, UnregisterMessage = true, SendMessage = true,
    UnregisterAllEvents = true, UnregisterAllMessages = true, RegisterBucketEvent = true, RegisterBucketMessage = true,
    UnregisterBucket = true, UnregisterAllBuckets = true, ScheduleTimer = true, ScheduleRepeatingTimer = true,
    CancelTimer = true, CancelAllTimers = true, TimeLeft = true, RegisterChatCommand = true, UnregisterChatCommand = true,
    GetArgs = true, Profile = true, IsSecret = true }

local frameMs, frameKB, frameSelf = 0, 0, {}

local function Finish(label, start, mem, ...)
    local ms = debugprofilestop() - start
    -- a garbage collection step inside the call shrinks memory; its allocation is then unknown and counted as none
    local kb = math.max(collectgarbage("count") - mem, 0)
    local depth = Profiler.depth
    if depth > 0 then
        local selfMs, selfKB = ms - Profiler.childMs[depth], math.max(kb - Profiler.childKB[depth], 0)
        Profiler.depth = depth - 1
        if depth > 1 then
            Profiler.childMs[depth - 1] = Profiler.childMs[depth - 1] + ms
            Profiler.childKB[depth - 1] = Profiler.childKB[depth - 1] + kb
        else
            frameMs, frameKB = frameMs + ms, frameKB + kb
        end
        local s = Profiler.stats[label]
        if not s then
            s = { label = label, calls = 0, ms = 0, self = 0, peak = 0, kb = 0 }
            Profiler.stats[label] = s
        end
        s.calls, s.ms, s.self, s.kb = s.calls + 1, s.ms + ms, s.self + selfMs, s.kb + selfKB
        if ms > s.peak then s.peak = ms end
        frameSelf[label] = (frameSelf[label] or 0) + selfMs
    end
    return ...
end

local function Wrap(label, fn)
    return function(...)
        if not Profiler.active then return fn(...) end
        local depth = Profiler.depth + 1
        Profiler.depth, Profiler.childMs[depth], Profiler.childKB[depth] = depth, 0, 0
        return Finish(label, debugprofilestop(), collectgarbage("count"), fn(...))
    end
end

-- For local functions and hooks the method wrapping can't reach; costs one check per call while stopped
function CS.Profile(label, fn)
    return Wrap(label, fn)
end

local function WrapTable(t, prefix)
    for key, fn in pairs(t) do
        if type(key) == "string" and type(fn) == "function" and not SKIP[key] then
            local wrapped = Wrap(prefix .. key, fn)
            t[key] = wrapped
            Profiler.originals[#Profiler.originals + 1] = { t, key, fn, wrapped }
        end
    end
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    Profiler.depth = 0
    Profiler.frames = Profiler.frames + 1
    Profiler.frameSum = Profiler.frameSum + frameMs
    if frameMs > Profiler.framePeak then Profiler.framePeak = frameMs end
    local mem = collectgarbage("count")
    local grown = mem - Profiler.lastMem
    Profiler.lastMem = mem
    if elapsed * 1000 >= HITCH_MS then
        local top = {}
        for label, ms in pairs(frameSelf) do top[#top + 1] = { label, ms } end
        table.sort(top, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(3, #top) do parts[i] = ("%s %.1f"):format(top[i][1], top[i][2]) end
        table.insert(Profiler.hitches, ("%6.1fs frame %5.0f ms, Craftseeker %5.1f ms %6.0f KB, all addons %s; %s"):format(
            GetTime() - Profiler.startedAt, elapsed * 1000, frameMs, frameKB,
            grown < 0 and ("gc freed " .. math.floor(-grown) .. " KB") or ("+" .. math.floor(grown) .. " KB"),
            #parts > 0 and table.concat(parts, ", ") or "-"))
        if #Profiler.hitches > HITCH_MAX then table.remove(Profiler.hitches, 1) end
    end
    frameMs, frameKB = 0, 0
    wipe(frameSelf)
end)

local function AddonMemory()
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage("Craftseeker") / 1024
end

function Profiler:Start()
    if self.active then return end
    WrapTable(CS, "CS:")
    for name, module in CS:IterateModules() do WrapTable(module, name .. ":") end
    wipe(self.stats)
    wipe(self.hitches)
    wipe(frameSelf)
    frameMs, frameKB = 0, 0
    self.frames, self.frameSum, self.framePeak, self.depth = 0, 0, 0, 0
    self.startedAt, self.lastMem, self.memAtStart = GetTime(), collectgarbage("count"), AddonMemory()
    self.active = true
    ticker:Show()
    CS:Print(("profiling; Craftseeker uses %.1f MB now. /cs profile again stops and reports."):format(self.memAtStart))
end

function Profiler:Stop()
    if not self.active then return end
    self.active = false
    ticker:Hide()
    for i = #self.originals, 1, -1 do
        local t, key, fn, wrapped = unpack(self.originals[i])
        if t[key] == wrapped then t[key] = fn end
    end
    wipe(self.originals)
    self:Report()
end

function Profiler:Report()
    local seconds = math.max(GetTime() - self.startedAt, 0.001)
    local list, totalKB = {}, 0
    for _, s in pairs(self.stats) do
        list[#list + 1] = s
        totalKB = totalKB + s.kb
    end
    local lines = {
        ("Craftseeker profile %s, %.0f s, %d frames"):format(date("%Y-%m-%d %H:%M"), seconds, self.frames),
        ("Addon memory %.1f MB at start, %.1f MB now (uncollected garbage included)"):format(self.memAtStart, AddonMemory()),
        ("Craftseeker Lua avg %.3f ms/frame, peak %.1f ms; allocated %.1f MB, %.0f KB/s"):format(
            self.frames > 0 and self.frameSum / self.frames or 0, self.framePeak, totalKB / 1024, totalKB / seconds),
        "Top by self ms: calls, total ms, self ms, peak ms, self KB",
    }
    local function Rows(key)
        table.sort(list, function(a, b) return a[key] > b[key] end)
        for i = 1, math.min(TOP, #list) do
            local s = list[i]
            lines[#lines + 1] = ("  %-36s %6d %8.1f %8.1f %7.1f %8.0f"):format(s.label, s.calls, s.ms, s.self, s.peak, s.kb)
        end
    end
    Rows("self")
    lines[#lines + 1] = "Top by self KB allocated: same columns"
    Rows("kb")
    lines[#lines + 1] = ("Frames of %d ms or more (last %d): time, frame, Craftseeker ms and KB, memory change, top self ms"):format(
        HITCH_MS, HITCH_MAX)
    for _, h in ipairs(self.hitches) do lines[#lines + 1] = "  " .. h end
    CS.data.profileReport = lines
    for _, line in ipairs(lines) do print(line) end
    CS:Print("report saved in SavedVariables\\Craftseeker.lua as profileReport after /reload or logout")
end

function Profiler:Toggle()
    if self.active then self:Stop() else self:Start() end
end
