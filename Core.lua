local ADDON_NAME, ns = ...

ns.DEFAULTS = {
    enabled = true,
    showOnPlayer = false,   -- also show on your own frame (handy for testing solo)
    tooltips = true,
    highlightMine = true,   -- green border on buffs you cast
    showTimers = true,
    filterMode = "all",     -- "all" = everything except deny list, "allow" = only allow list
    iconSize = 20,
    perRow = 8,
    maxIcons = 16,
    spacing = 2,
    anchor = "RIGHT",       -- "RIGHT" or "BELOW" the unit frame
    offsetX = 0,
    offsetY = -4,
    allow = { "Rejuvenation" },
    deny = {},
}

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local MAX_SCAN = 40

local db
local containers = {}
local allowRank, denySet = {}, {}
local compactUnits = {} -- [compactFrame] = unit, filled by hooking CompactUnitFrame_SetUnit

local floor, ceil, max, format = math.floor, math.ceil, math.max, string.format

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffOso Party Buffs|r: " .. msg)
end
ns.Print = Print

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = CopyDefaults(v, {})
            else
                dst[k] = v
            end
        end
    end
    return dst
end

-- Returns name, icon, count, duration, expirationTime, sourceUnit, spellId
local function GetBuff(unit, index)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local a = C_UnitAuras.GetBuffDataByIndex(unit, index)
        if not a then return end
        return a.name, a.icon, a.applications, a.duration, a.expirationTime, a.sourceUnit, a.spellId
    end
    local name, icon, count, _, duration, expirationTime, source, _, _, spellId = UnitBuff(unit, index)
    return name, icon, count, duration, expirationTime, source, spellId
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------

function ns.RebuildFilters()
    wipe(allowRank)
    wipe(denySet)
    for i, entry in ipairs(db.allow) do
        local key = strlower(strtrim(entry))
        if not allowRank[key] then allowRank[key] = i end
    end
    for _, entry in ipairs(db.deny) do
        denySet[strlower(strtrim(entry))] = true
    end
end

function ns.AddEntry(listKey, text)
    text = text and strtrim(text) or ""
    if text == "" then return false end
    local lower = strlower(text)
    for _, v in ipairs(db[listKey]) do
        if strlower(v) == lower then return false end
    end
    tinsert(db[listKey], text)
    ns.RebuildFilters()
    ns.RefreshAll()
    return true
end

function ns.RemoveEntry(listKey, index)
    tremove(db[listKey], index)
    ns.RebuildFilters()
    ns.RefreshAll()
end

function ns.RemoveByName(text)
    local lower = strlower(strtrim(text or ""))
    local removed = false
    for _, listKey in ipairs({ "allow", "deny" }) do
        local list = db[listKey]
        for i = #list, 1, -1 do
            if strlower(list[i]) == lower then
                tremove(list, i)
                removed = true
            end
        end
    end
    ns.RebuildFilters()
    ns.RefreshAll()
    return removed
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function FormatTime(t)
    if t >= 3600 then
        return format("%dh", ceil(t / 3600))
    elseif t >= 60 then
        return format("%dm", ceil(t / 60))
    end
    return format("%d", ceil(t))
end

local function Icon_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetUnitBuff(self.unit, self.index)
    GameTooltip:Show()
end

local function Icon_OnLeave()
    GameTooltip:Hide()
end

local function CreateIcon(container)
    local b = CreateFrame("Frame", nil, container)

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end

    -- Text sits above the cooldown swipe
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(b.cd:GetFrameLevel() + 1)

    b.count = overlay:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("TOPRIGHT", 2, 1)
    b.timer = overlay:CreateFontString(nil, "OVERLAY")
    b.timer:SetPoint("BOTTOM", 0, 1)

    b:SetScript("OnEnter", Icon_OnEnter)
    b:SetScript("OnLeave", Icon_OnLeave)
    return b
end

local function Container_OnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    if not db.showTimers then return end
    local now = GetTime()
    for i = 1, self.numShown do
        local b = self.icons[i]
        if b.expiration and b.expiration > 0 then
            local left = b.expiration - now
            b.timer:SetText(left > 0 and FormatTime(left) or "")
        else
            b.timer:SetText("")
        end
    end
end

local function GetContainer(unit)
    local c = containers[unit]
    if not c then
        c = CreateFrame("Frame", nil, UIParent)
        c.unit = unit
        c.icons = {}
        c.entries = {}
        c.numShown = 0
        c:SetSize(1, 1)
        c:SetScript("OnUpdate", Container_OnUpdate)
        c:Hide()
        containers[unit] = c
    end
    return c
end

---------------------------------------------------------------------------
-- Anchoring
---------------------------------------------------------------------------

local function FindAnchor(unit)
    -- Raid-style frames take priority when they are the ones being shown
    for frame, frameUnit in pairs(compactUnits) do
        if frameUnit == unit and frame:IsVisible() then
            return frame
        end
    end
    if unit == "player" then
        return PlayerFrame
    end
    local i = tonumber(unit:match("^party(%d)$"))
    return _G["PartyMemberFrame" .. i] or (PartyFrame and PartyFrame["MemberFrame" .. i])
end

local function AnchorContainer(c)
    local anchor = FindAnchor(c.unit)
    c.anchor = anchor
    if not anchor then return end
    c:SetParent(anchor)
    c:SetFrameStrata(anchor:GetFrameStrata())
    c:SetFrameLevel(anchor:GetFrameLevel() + 5)
    c:ClearAllPoints()
    if db.anchor == "BELOW" then
        c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", db.offsetX, db.offsetY)
    else
        c:SetPoint("TOPLEFT", anchor, "TOPRIGHT", db.offsetX, db.offsetY)
    end
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

local function CollectBuffs(unit, entries)
    local n = 0
    local allowOnly = db.filterMode == "allow"
    for i = 1, MAX_SCAN do
        local name, icon, count, duration, expiration, source, spellId = GetBuff(unit, i)
        if not name then break end
        local key = strlower(name)
        local idKey = spellId and tostring(spellId)
        local rank = allowRank[key] or (idKey and allowRank[idKey])
        local denied = denySet[key] or (idKey and denySet[idKey])
        if not denied and (rank or not allowOnly) then
            n = n + 1
            local e = entries[n] or {}
            entries[n] = e
            e.index, e.icon, e.count = i, icon, count
            e.duration, e.expiration = duration, expiration
            e.mine = source == "player"
            -- Allow-list buffs come first, in list order, so they always sit in the same spot
            e.order = (rank or 1000) * 100 + i
        end
    end

    -- Insertion sort of the first n entries (n is small)
    for i = 2, n do
        local e = entries[i]
        local j = i - 1
        while j >= 1 and entries[j].order > e.order do
            entries[j + 1] = entries[j]
            j = j - 1
        end
        entries[j + 1] = e
    end
    return n
end

local function UpdateUnit(unit)
    local c = containers[unit]
    if not c then return end

    if not db.enabled or (unit == "player" and not db.showOnPlayer)
        or not c.anchor or not UnitExists(unit) then
        c.numShown = 0
        c:Hide()
        return
    end

    local n = CollectBuffs(unit, c.entries)
    local shown = math.min(n, db.maxIcons)
    local size, gap, perRow = db.iconSize, db.spacing, db.perRow
    local fontSize = max(8, floor(size * 0.45))

    for i = 1, shown do
        local e = c.entries[i]
        local b = c.icons[i]
        if not b then
            b = CreateIcon(c)
            c.icons[i] = b
        end
        b.unit, b.index, b.expiration = unit, e.index, e.expiration
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", c, "TOPLEFT", ((i - 1) % perRow) * (size + gap), -floor((i - 1) / perRow) * (size + gap))
        b:EnableMouse(db.tooltips)

        b.icon:SetTexture(e.icon)
        if db.highlightMine and e.mine then
            b.border:SetColorTexture(0.1, 1, 0.1, 1)
        else
            b.border:SetColorTexture(0, 0, 0, 1)
        end

        if e.duration and e.duration > 0 and e.expiration and e.expiration > 0 then
            b.cd:SetCooldown(e.expiration - e.duration, e.duration)
            b.cd:Show()
        else
            b.cd:Hide()
        end

        b.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        b.count:SetText(e.count and e.count > 1 and e.count or "")
        b.timer:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        b.timer:SetText("")
        b:Show()
    end
    for i = shown + 1, #c.icons do
        c.icons[i]:Hide()
    end

    c.numShown = shown
    c.elapsed = 1 -- refresh timer text on the next frame
    local cols = math.min(shown, perRow)
    local rows = ceil(shown / perRow)
    c:SetSize(max(1, cols * (size + gap)), max(1, rows * (size + gap)))
    c:SetShown(shown > 0)
end

function ns.RefreshAll()
    if not db then return end
    for _, unit in ipairs(UNITS) do
        AnchorContainer(GetContainer(unit))
        UpdateUnit(unit)
    end
end

local refreshPending = false
local function ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.1, function()
        refreshPending = false
        ns.RefreshAll()
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("CVAR_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        OsoPartyBuffsDB = OsoPartyBuffsDB or {}
        db = CopyDefaults(ns.DEFAULTS, OsoPartyBuffsDB)
        ns.db = db
        ns.RebuildFilters()
        ns.CreateOptions()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if CompactUnitFrame_SetUnit then
            hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if unit and (unit == "player" or unit:match("^party%d$")) then
                    compactUnits[frame] = unit
                else
                    compactUnits[frame] = nil
                end
                ScheduleRefresh()
            end)
        end
        ns.RefreshAll()
    elseif event == "UNIT_AURA" then
        if containers[arg1] then UpdateUnit(arg1) end
    else
        ScheduleRefresh()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function PrintList(listKey)
    local list = db[listKey]
    Print(listKey .. " list: " .. (#list > 0 and table.concat(list, ", ") or "(empty)"))
end

SLASH_OSOPARTYBUFFS1 = "/opb"
SLASH_OSOPARTYBUFFS2 = "/osopartybuffs"
SlashCmdList.OSOPARTYBUFFS = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = strlower(cmd or "")

    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.OpenOptions()
    elseif cmd == "allow" or cmd == "deny" then
        if ns.AddEntry(cmd, rest) then
            Print("Added '" .. rest .. "' to the " .. cmd .. " list.")
        else
            Print("Nothing added (empty or already listed).")
        end
    elseif cmd == "remove" then
        Print(ns.RemoveByName(rest) and ("Removed '" .. rest .. "'.") or ("'" .. rest .. "' was not in either list."))
    elseif cmd == "size" then
        local n = tonumber(rest)
        if n then
            db.iconSize = math.min(48, math.max(10, floor(n)))
            ns.RefreshAll()
            Print("Icon size set to " .. db.iconSize .. ".")
        else
            Print("Usage: /opb size 10-48")
        end
    elseif cmd == "mode" then
        rest = strlower(rest)
        if rest == "all" or rest == "allow" then
            db.filterMode = rest
            ns.RefreshAll()
            Print("Filter mode: " .. rest)
        else
            Print("Usage: /opb mode all | allow")
        end
    elseif cmd == "list" then
        PrintList("allow")
        PrintList("deny")
    elseif cmd == "reset" then
        wipe(db)
        CopyDefaults(ns.DEFAULTS, db)
        ns.RebuildFilters()
        ns.RefreshAll()
        Print("Settings reset to defaults.")
    else
        Print("Commands:")
        Print("/opb - open options")
        Print("/opb allow <name or spell ID> - add to allow list")
        Print("/opb deny <name or spell ID> - add to deny list")
        Print("/opb remove <name or spell ID> - remove from both lists")
        Print("/opb size <10-48> - icon size")
        Print("/opb mode all|allow - show all buffs, or only the allow list")
        Print("/opb list - print both lists")
        Print("/opb reset - restore defaults")
    end
    ns.RefreshOptions()
end
