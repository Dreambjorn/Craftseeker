-- Craftseeker: /cs profiler wraps the addon's methods while running and shows time and memory per function in a window
local _, CS = ...

local Profiler = { active = false, stats = {}, depth = 0, childMs = {}, childKB = {}, originals = {}, hitches = {} }
CS.Profiler = Profiler

local HITCH_MS = 25  -- a frame this long is logged with what Craftseeker did in it
local BUSY_MS = 16   -- Craftseeker alone taking a 60 fps frame's whole budget
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
    if frameMs >= BUSY_MS then Profiler.busy = Profiler.busy + 1 end
    local mem = collectgarbage("count")
    local grown = mem - Profiler.lastMem
    Profiler.lastMem = mem
    if elapsed * 1000 >= HITCH_MS then
        local top = {}
        for label, ms in pairs(frameSelf) do top[#top + 1] = { label, ms } end
        table.sort(top, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(3, #top) do parts[i] = ("%s %.1f ms"):format(top[i][1], top[i][2]) end
        table.insert(Profiler.hitches, { at = GetTime() - Profiler.startedAt, frame = elapsed * 1000, ms = frameMs,
            kb = frameKB, grown = grown, top = #parts > 0 and table.concat(parts, ", ") or "nothing" })
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
    self.frames, self.frameSum, self.framePeak, self.depth, self.busy = 0, 0, 0, 0, 0
    self.startedAt, self.lastMem, self.memAtStart = GetTime(), collectgarbage("count"), AddonMemory()
    self.memNow = self.memAtStart
    self.active = true
    ticker:Show()
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
    self.memNow = AddonMemory()
    CS.data.profileReport = self:ReportLines()
    self:Refresh()
end

local cleaned -- Craftseeker's memory right after a full collection, once the player asks for one

-- The measured numbers, for the window and the saved report
function Profiler:Summary()
    local seconds = math.max(GetTime() - (self.startedAt or GetTime()), 0.001)
    local list, totalKB = {}, 0
    for _, s in pairs(self.stats) do
        list[#list + 1] = s
        totalKB = totalKB + s.kb
    end
    local frames = self.frames or 0
    return { seconds = seconds, frames = frames, list = list, totalKB = totalKB,
        avg = frames > 0 and self.frameSum / frames or 0, peak = self.framePeak or 0, busy = self.busy or 0 }
end

-- Plain text lines kept in SavedVariables as profileReport, for reading after a /reload
function Profiler:ReportLines()
    local s = self:Summary()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Craftseeker", "Version") or "?"
    local function Count(t)
        local n = 0
        for _ in pairs(t or {}) do n = n + 1 end
        return n
    end
    local data = CS.data
    local lines = {
        ("Craftseeker profile %s, %.0f s, %d frames"):format(date("%Y-%m-%d %H:%M"), s.seconds, s.frames),
        ("Version %s, client %s"):format(version, (GetBuildInfo())),
        ("Data: %d recipes, %d other users, %d Forever Drops peers, %d Drop Tables creatures, %d creatures seen"):format(
            Count(CS.recipes), Count(data.shared), Count(data.bridges.fd), Count(data.bridges.dt), Count(data.npcs)),
        ("Addon memory %.1f MB at start, %.1f MB now (uncollected garbage included)%s"):format(self.memAtStart or 0,
            AddonMemory(), cleaned and (", %.1f MB after a cleanup"):format(cleaned) or ""),
        ("Craftseeker Lua avg %.3f ms/frame, peak %.1f ms, %d frames over %d ms; allocated %.1f MB, %.0f KB/s"):format(
            s.avg, s.peak, s.busy, BUSY_MS, s.totalKB / 1024, s.totalKB / s.seconds),
    }
    -- one fact after another, never padded columns: the copy box and chat both use proportional fonts
    local function Rows(title, key)
        lines[#lines + 1] = title
        table.sort(s.list, function(a, b) return a[key] > b[key] end)
        for i = 1, math.min(TOP, #s.list) do
            local r = s.list[i]
            lines[#lines + 1] = ("- %s: %d calls, %.1f ms total, %.1f ms own, slowest %.1f ms, %.0f KB"):format(r.label,
                r.calls, r.ms, r.self, r.peak, r.kb)
        end
    end
    Rows("Most time", "self")
    Rows("Most garbage", "kb")
    lines[#lines + 1] = ("Frames of %d ms or more (last %d)"):format(HITCH_MS, HITCH_MAX)
    for _, h in ipairs(self.hitches) do
        lines[#lines + 1] = ("- at %.1f s: frame %.0f ms, Craftseeker %.1f ms and %.0f KB, all addons %s; busiest: %s"):format(
            h.at, h.frame, h.ms, h.kb, h.grown < 0 and ("gc freed " .. math.floor(-h.grown) .. " KB")
            or ("+" .. math.floor(h.grown) .. " KB"), h.top)
    end
    return lines
end

-- Window ----------------------------------------------------------------------
-- Laid out like the browser's recipe pane: a portrait frame, gold section lines, tables in a scrolling inset

local W, PAD_X, BUTTON_W = 760, 28, 100
local CONTENT_W = W - 2 * PAD_X - 26
local GREY, GOLD = "|cff9d9d9d", "|cffffd100"
local win, content, cursor
local pool, used = { text = {}, lines = {} }, { text = 0, lines = 0 }

local function GoldLine(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(2)
    local tex = line:CreateTexture(nil, "ARTWORK")
    tex:SetAtlas("Options_HorizontalDivider")
    tex:SetAllPoints()
    tex:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())
    return line
end

local function Text(x, width, text, font, justify)
    used.text = used.text + 1
    local fs = pool.text[used.text]
    if not fs then
        fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pool.text[used.text] = fs
    end
    fs:SetFontObject(font or "GameFontHighlight")
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, cursor)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    fs:Show()
    return fs
end

local function Line(text, font)
    local fs = Text(0, CONTENT_W, text, font)
    cursor = cursor - fs:GetStringHeight() - 6
end

local function Section(title)
    cursor = cursor - 14
    local fs = Text(0, CONTENT_W, title, "GameFontNormalMed2")
    cursor = cursor - fs:GetStringHeight() - 5
    used.lines = used.lines + 1
    local line = pool.lines[used.lines]
    if not line then
        line = GoldLine(content)
        line:SetWidth(CONTENT_W)
        pool.lines[used.lines] = line
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 0, cursor)
    line:Show()
    cursor = cursor - 10
end

-- name, calls, time, slowest, memory
local COLUMNS = { { 0, 300, "LEFT" }, { 300, 80, "RIGHT" }, { 380, 95, "RIGHT" }, { 475, 95, "RIGHT" }, { 570, CONTENT_W - 570, "RIGHT" } }

local function Row(cells, font, columns)
    for i, c in ipairs(columns or COLUMNS) do
        local fs = Text(c[1], c[2], cells[i] or "", font, c[3])
        fs:SetWordWrap(false)
    end
    cursor = cursor - 20
end

local function Table(list, key)
    table.sort(list, function(a, b) return a[key] > b[key] end)
    Row({ "Part of Craftseeker", "Calls", "Time", "Slowest", "Garbage" }, "GameFontDisable")
    for i = 1, math.min(TOP, #list) do
        local r = list[i]
        Row({ r.label, tostring(r.calls), ("%.1f ms"):format(r.self), ("%.1f ms"):format(r.peak), ("%.0f KB"):format(r.kb) })
    end
    if #list == 0 then Line(GREY .. "Nothing ran yet|r") end
end

-- From the average and how often Craftseeker alone filled a frame: one slow search or page draws a single spike,
-- which the player asked for and barely sees
local function Verdict(avg, busy, seconds)
    local perMinute = busy * 60 / math.max(seconds, 60)
    if avg < 0.1 and perMinute <= 2 then return "|cff40ff40Light|r: you won't notice it" end
    if avg < 0.5 and perMinute <= 10 then return GOLD .. "Moderate|r: an occasional busy frame" end
    return "|cffff4040Heavy|r: it may cost frames; the tables show where"
end

-- when, the whole frame, Craftseeker's share, every addon's memory change, what Craftseeker ran most
local SLOW_COLUMNS = { { 0, 60, "RIGHT" }, { 70, 70, "RIGHT" }, { 150, 95, "RIGHT" }, { 255, 110, "RIGHT" },
    { 380, CONTENT_W - 380, "LEFT" } }

function Profiler:Refresh()
    if not (win and win:IsShown()) or win.Copy:IsShown() then return end
    for kind, list in pairs(pool) do
        for _, w in ipairs(list) do w:Hide() end
        used[kind] = 0
    end
    cursor = -4
    local s = self:Summary()
    win.Toggle:SetText(self.active and "Stop" or "Start again")
    win.Status:SetText(self.active and ("Measuring for %d s"):format(s.seconds) or (self.startedAt and "Stopped" or "Not started"))

    if self.active then
        Line(GREY .. "Play and use Craftseeker as usual for a few minutes, then press Stop and Report.|r")
    end

    Section("Speed")
    Line(Verdict(s.avg, s.busy, s.seconds))
    Line(("Average |cffffffff%.3f ms|r a frame, slowest |cffffffff%.1f ms|r, |cffffffff%d|r frames over %d ms"):format(
        s.avg, s.peak, s.busy, BUSY_MS))

    Section("Memory")
    -- the game's own memory read walks every addon and stalls a frame, so it isn't repeated each second
    Line(("|cffffffff%.1f MB|r when you %s%s"):format(self.memNow or 0,
        cleaned and "cleaned up" or self.active and "started" or "stopped",
        cleaned and "" or (GREY .. ", garbage included; Clean up shows the real size|r")))
    Line(("|cffffffff%.0f KB|r of garbage a second while measuring"):format(s.totalKB / s.seconds))

    Section("Most time")
    Table(s.list, "self")
    Section("Most garbage")
    Table(s.list, "kb")

    Section(("Slow frames, %d ms or more"):format(HITCH_MS))
    if #self.hitches == 0 then
        Line(GREY .. "None|r")
    else
        Row({ "At", "Frame", "Craftseeker", "All addons", "Craftseeker ran" }, "GameFontDisable", SLOW_COLUMNS)
    end
    for _, h in ipairs(self.hitches) do
        Row({ ("%.1f s"):format(h.at), ("%.0f ms"):format(h.frame), ("%.1f ms"):format(h.ms),
            h.grown < 0 and ("%d KB freed"):format(math.floor(-h.grown)) or ("+%d KB"):format(math.floor(h.grown)), h.top }, nil, SLOW_COLUMNS)
    end
    content:SetHeight(-cursor + 10)
end

-- One short line under a button; text may be a function, for buttons whose job changes
local function ButtonTip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip_AddHighlightLine(GameTooltip, type(text) == "function" and text() or text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

local function Build()
    win = CreateFrame("Frame", "CraftseekerProfiler", UIParent, "PortraitFrameTemplate")
    win:SetSize(W, 560)
    win:SetPoint("CENTER", 60, -20)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CS.data.settings.profilerAt = { self:GetLeft(), self:GetTop() }
    end)
    local at = CS.data.settings.profilerAt
    if at then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at[1], at[2])
    end
    -- above the browser window, which sits in HIGH
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetTitle("Craftseeker profiler")
    win:SetPortraitToAsset("Interface\\Icons\\INV_Misc_PocketWatch_01")
    tinsert(UISpecialFrames, "CraftseekerProfiler")

    local toggle = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    toggle:SetSize(BUTTON_W, 22)
    toggle:SetPoint("TOPRIGHT", -14, -38)
    toggle:SetScript("OnClick", function() Profiler:Toggle() end)
    win.Toggle = toggle
    ButtonTip(toggle, function()
        return Profiler.active and "Stop measuring and save the report" or "Measure again from now"
    end)
    local clean = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    clean:SetSize(BUTTON_W, 22)
    clean:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
    clean:SetText("Clean up")
    win.Clean = clean
    ButtonTip(clean, "Clear garbage to show the real memory size")
    -- a full collection stalls a frame, so it runs only on request
    clean:SetScript("OnClick", function()
        collectgarbage("collect")
        cleaned = AddonMemory()
        Profiler.memNow = cleaned
        Profiler:Refresh()
    end)

    local panel = CreateFrame("Frame", nil, win)
    win.Panel = panel
    panel:SetPoint("TOPLEFT", 5, -72)
    panel:SetPoint("BOTTOMRIGHT", -5, 5)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAtlas("Professions-Recipe-Background")
    bg:SetAllPoints()
    local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
    border:SetAllPoints()
    NineSliceUtil.ApplyLayoutByName(border, "InsetFrameTemplate")
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", PAD_X, -12)
    scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    win.Stats, win.StatsBar = scroll, bar

    -- the report as plain text, selected for Ctrl+C, in place of the stats
    local copy = CreateFrame("ScrollFrame", nil, panel)
    copy:SetPoint("TOPLEFT", PAD_X, -12)
    copy:SetPoint("BOTTOMRIGHT", -24, 8)
    local copyBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    copyBar:SetPoint("TOPLEFT", copy, "TOPRIGHT", 6, 0)
    copyBar:SetPoint("BOTTOMLEFT", copy, "BOTTOMRIGHT", 6, 0)
    local box = CreateFrame("EditBox", nil, copy)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlight")
    box:SetWidth(CONTENT_W)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- for copying only: any typing, cutting or pasting puts the report back
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.report then
            self:SetText(self.report)
            self:HighlightText()
        end
    end)
    copy:SetScrollChild(box)
    ScrollUtil.InitScrollFrameWithScrollBar(copy, copyBar)
    copy:Hide()
    copyBar:Hide()
    win.Copy, win.CopyBar, win.CopyBox = copy, copyBar, box

    local report = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    report:SetSize(BUTTON_W, 22)
    report:SetPoint("RIGHT", clean, "LEFT", -6, 0)
    report:SetText("Report")
    -- the report needs the panel, so a minimized window opens up first
    report:SetScript("OnClick", function()
        if win.minimized then win.Size:Maximize() end
        Profiler:ShowReport(not win.Copy:IsShown())
    end)
    win.ReportButton = report
    ButtonTip(report, function() return win.Copy:IsShown() and "Back to the tables" or "The report as text, to copy" end)

    -- the heading stops short of the buttons, so a long status never runs under them
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge2")
    title:SetPoint("TOPLEFT", 66, -30)
    title:SetPoint("RIGHT", report, "LEFT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("Time and memory")
    win.Status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.Status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    win.Status:SetPoint("RIGHT", report, "LEFT", -12, 0)
    win.Status:SetJustifyH("LEFT")
    win.Status:SetWordWrap(false)
    win.Status:SetTextColor(0.7, 0.7, 0.7)

    -- live numbers while measuring, once a second; closing the window stops the measuring
    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 and Profiler.active then
            elapsed = 0
            Profiler:Refresh()
        end
    end)
    win:SetScript("OnHide", function() Profiler:Stop() end)

    -- the title bar's minimize button, as the profession window has; minimized, only the live numbers stay
    local size = CreateFrame("Frame", nil, win, "MaximizeMinimizeButtonFrameTemplate")
    size:SetPoint("RIGHT", win.CloseButton, "LEFT", 0, 0)
    size:SetOnMinimizedCallback(function() Profiler:SetMinimized(true) end)
    size:SetOnMaximizedCallback(function() Profiler:SetMinimized(false) end)
    win.Size = size
end

-- The top edge stays put while the window grows or shrinks under it
function Profiler:SetMinimized(on)
    local left, top = win:GetLeft(), win:GetTop()
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    CS.data.settings.profilerAt = { left, top }
    win:SetHeight(on and 120 or 560) -- shorter, the portrait corner's art runs into the bottom corner's
    win.minimized = on
    win.Panel:SetShown(not on)
    if on and win.Copy:IsShown() then self:ShowReport(false) end
end

-- The report to copy and paste, or back to the stats
function Profiler:ShowReport(on)
    win.Copy:SetShown(on)
    win.CopyBar:SetShown(on)
    win.Stats:SetShown(not on)
    win.StatsBar:SetShown(not on)
    win.ReportButton:SetText(on and "Back" or "Report")
    if not on then
        win.CopyBox:ClearFocus()
        return self:Refresh()
    end
    local lines = self:ReportLines()
    win.CopyBox.report = table.concat(lines, "\n")
    win.CopyBox:SetText(win.CopyBox.report)
    win.CopyBox:SetHeight(#lines * 30 + 20) -- long lines wrap, so room for two each
    win.CopyBox:SetFocus()
    win.CopyBox:HighlightText()
    win.Status:SetText("Ctrl+C copies it, all selected")
end

-- /cs profiler: the window, measuring from the moment it opens
function Profiler:Open()
    if not win then Build() end
    cleaned = nil
    win:Show()
    self:ShowReport(false)
    self:Start()
    self:Refresh()
end

function Profiler:Toggle()
    if self.active then self:Stop() else self:Start() end
    self:Refresh()
end
