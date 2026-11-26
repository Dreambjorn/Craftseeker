-- Craftseeker: recipe and source line text for the browser
local _, CS = ...

local GREY = "|cff9d9d9d"
local ALT = "|cff66bbff"
local KNOWN = "|A:common-icon-checkmark:16:16|a"

-- The profession window's colours; white without the profession, red when the skill is still too low
CS.DIFFICULTY_COLOR = { learn = "|cffff4040", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40",
    grey = "|cff808080" }

-- The profession window's skill-up arrows: orange high, yellow medium, green low chance; none once grey
CS.SKILL_ATLAS = { orange = "Professions-Icon-Skill-High", yellow = "Professions-Icon-Skill-Medium",
    green = "Professions-Icon-Skill-Low" }

-- Profession, the name (blue when only an alt knows it, red while the skill is too low, grey when not seen on Forever
-- yet), a check when this character knows it, and the skill-up arrow
function CS:RecipeLine(recipeID, reagentID)
    local rec = self.recipes[recipeID]
    local who = self:WhoKnows(recipeID)
    local diff = self:Difficulty(recipeID)
    local color = not self:IsProven(recipeID) and GREY or who == "alt" and ALT
        or diff == "learn" and self.DIFFICULTY_COLOR.learn or "|cffffffff"
    local _, optional = self.ReagentQty(rec, reagentID)
    local text = color .. (rec.n or "?") .. "|r"
    if optional then text = text .. GREY .. " (optional)|r" end
    -- the opposite faction's emblem instead of a long note, so the name keeps its room; the tooltip says why
    local right = who == "me" and KNOWN or nil
    if who ~= "me" and not self:IsObtainable(recipeID) then
        right = self.PlayerFaction() == 2 and "|A:AllianceSymbol:16:16|a" or "|A:HordeSymbol:16:16|a"
    end
    return (rec.p or "?"), text, right, self.SKILL_ATLAS[diff or ""]
end

-- Sorts list in place by get(entry); entries without a value go last, ties keep their order (table.sort isn't stable)
function CS.SortBy(list, get, descending)
    local value, pos = {}, {}
    for i, e in ipairs(list) do value[e], pos[e] = get(e), i end
    table.sort(list, function(a, b)
        local x, y = value[a], value[b]
        if x ~= y then
            if x == nil or y == nil then return y == nil end
            if descending then return x > y end
            return x < y
        end
        return pos[a] < pos[b]
    end)
end

-- A level text ("12" or "10-12") as lowest and highest level
function CS.LevelRange(level)
    local lo, hi = tostring(level or ""):match("^(%d+)%-?(%d*)$")
    lo = tonumber(lo)
    return lo, tonumber(hi) or lo
end

-- Sorted "key: value" lines for a source bucket
local function TopEntries(bucket, limit, fmt)
    local list = {}
    for k, v in pairs(bucket) do list[#list + 1] = { k, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(limit, #list) do
        out[#out + 1] = fmt(list[i][1], list[i][2])
    end
    return out
end

-- { label, text } pairs for where an item has come from
function CS:SourceLines(itemID, limit)
    local lines = {}
    local s = self.data.sources[itemID]
    if s then
        if s.vendor then
            for _, t in ipairs(TopEntries(s.vendor, limit, function(k, v) return k .. "  " .. CS.Money(v) end)) do
                lines[#lines + 1] = { "Vendor", t }
            end
        end
        if s.gather then
            for _, t in ipairs(TopEntries(s.gather, limit, function(k) return k end)) do lines[#lines + 1] = { "Gathered", t } end
        end
        if s.loot then
            -- older records keep "NPC #id" when no name was known then; name and merge them now when possible
            local loot = {}
            for k, v in pairs(s.loot) do
                local id, zone = k:match("^NPC #(%d+) (.*)$")
                local name = id and self:NpcName(tonumber(id))
                if name then k = name .. " " .. zone end
                loot[k] = (loot[k] or 0) + v
            end
            for _, t in ipairs(TopEntries(loot, limit, function(k, v) return k .. GREY .. " (" .. v .. "x)|r" end)) do
                lines[#lines + 1] = { "Looted", t }
            end
        end
        if s.container then
            -- records before the container's name was kept say only "Container"
            for _, t in ipairs(TopEntries(s.container, limit, function(k, v)
                return (k == "Container" and "A container" or k) .. GREY .. " (" .. v .. "x)|r"
            end)) do
                lines[#lines + 1] = { "Opened", t }
            end
        end
    end
    return lines
end
