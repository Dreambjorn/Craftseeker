-- Craftseeker: recipe and source line text for the browser
local _, CS = ...

local GREEN = "|cff40ff40"
local YELLOW = "|cffffd100"
local GREY = "|cff9d9d9d"

function CS:RecipeLine(recipeID, reagentID)
    local rec = self.recipes[recipeID]
    local who, alt = self:WhoKnows(recipeID)
    local color = who == "me" and GREEN or who == "alt" and YELLOW or GREY
    local _, optional = self.ReagentQty(rec, reagentID)
    local text = color .. (rec.n or "?") .. "|r"
    if optional then text = text .. GREY .. " (optional)|r" end
    if who == "alt" then text = text .. YELLOW .. " - " .. alt .. "|r" end
    return (rec.p or "?"), text
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
        if s.fish then
            for _, t in ipairs(TopEntries(s.fish, limit, function(k) return k end)) do lines[#lines + 1] = { "Fished", t } end
        end
        if s.loot then
            for _, t in ipairs(TopEntries(s.loot, limit, function(k, v) return k .. GREY .. " (" .. v .. "x)|r" end)) do
                lines[#lines + 1] = { "Looted", t }
            end
        end
        if s.container then
            lines[#lines + 1] = { "Looted", "From containers" }
        end
    end
    return lines
end
