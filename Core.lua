--[[
    Oso Party Buffs - Core.lua

    Scans the buffs on you and your party members, filters them through the
    allow/deny lists, and draws them as icons next to the party frames. Also
    owns the saved settings, game events, and the /opb slash commands.
    The options panel lives in Options.lua.
]]

local ADDON_NAME, ns = ...

ns.DEFAULTS = {
    enabled = true,
    showOnPlayer = false,       -- also show on your own frame (handy for testing solo)
    showTooltips = true,        -- show the buff tooltip when hovering an icon
    highlightMine = true,       -- green border on buffs you cast
    showTimers = true,
    hideBlizzardPopup = false,  -- hide the buff pop-up Blizzard shows when hovering a party frame
    filterMode = "all",         -- "all" = everything except deny list, "allow" = only allow list
    iconSize = 20,
    perRow = 8,
    maxIcons = 16,
    spacing = 2,
    anchor = "RIGHT",           -- "RIGHT" or "BELOW" the unit frame
    offsetX = 0,
    offsetY = -4,
    allow = {},
    deny = {},
}

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local LISTS = { "allow", "deny" }
local MAX_SCAN = 40
local TIMER_INTERVAL = 0.2

local db
local containers = {}               -- [unit] = icon container frame
local trackedUnits = {}             -- [unit] = true for every unit in UNITS
local allowRank, denySet = {}, {}   -- keyed by lowercase buff name or numeric spell ID
local compactUnits = {}             -- [raid-style frame] = unit, filled by hooking CompactUnitFrame_SetUnit
local lowerNames = {}               -- [buff name] = lowercase name, so each name is lowercased once
local layoutVersion = 0             -- bumped by RefreshAll; containers re-layout icons when it changes

for _, unit in ipairs(UNITS) do
    trackedUnits[unit] = true
end

local floor, ceil, min, max, format = math.floor, math.ceil, math.min, math.max, string.format
local GetTime, UnitExists = GetTime, UnitExists

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffOso Party Buffs|r: " .. msg)
end

-- Fills in any missing keys in dst from src, leaving existing values alone
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

-- GetBuff(unit, index) returns name, icon, count, duration, expirationTime, sourceUnit, spellId.
-- UnitBuff is preferred because it returns plain values; C_UnitAuras builds a new table on every call.
local GetBuff
if UnitBuff then
    GetBuff = function(unit, index)
        local name, icon, count, _, duration, expirationTime, source, _, _, spellId = UnitBuff(unit, index)
        return name, icon, count, duration, expirationTime, source, spellId
    end
else
    GetBuff = function(unit, index)
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, index)
        if not aura then return end
        return aura.name, aura.icon, aura.applications, aura.duration, aura.expirationTime, aura.sourceUnit, aura.spellId
    end
end

---------------------------------------------------------------------------
-- Allow / deny lists
---------------------------------------------------------------------------

-- List entries match by lowercase name, or by spell ID when the entry is a number
local function FilterKey(entry)
    entry = strlower(strtrim(entry))
    return tonumber(entry) or entry
end

-- Rebuilds the lookup tables from the saved lists; call after any list change
function ns.RebuildFilters()
    wipe(allowRank)
    wipe(denySet)
    for i, entry in ipairs(db.allow) do
        local key = FilterKey(entry)
        if not allowRank[key] then allowRank[key] = i end
    end
    for _, entry in ipairs(db.deny) do
        denySet[FilterKey(entry)] = true
    end
end

-- Adds text to the "allow" or "deny" list; returns false if empty or already listed
function ns.AddEntry(listKey, text)
    text = text and strtrim(text) or ""
    if text == "" then return false end
    local lower = strlower(text)
    for _, entry in ipairs(db[listKey]) do
        if strlower(entry) == lower then return false end
    end
    tinsert(db[listKey], text)
    ns.RebuildFilters()
    ns.RefreshAll()
    return true
end

-- Removes the entry at index from the "allow" or "deny" list
function ns.RemoveEntry(listKey, index)
    tremove(db[listKey], index)
    ns.RebuildFilters()
    ns.RefreshAll()
end

-- Moves the entry at index up (delta -1) or down (delta 1) in the "allow" or "deny" list
function ns.MoveEntry(listKey, index, delta)
    local list = db[listKey]
    local target = index + delta
    if target < 1 or target > #list then return end
    list[index], list[target] = list[target], list[index]
    ns.RebuildFilters()
    ns.RefreshAll()
end

-- Removes text from both lists; returns true if anything was removed
function ns.RemoveByName(text)
    local lower = strlower(strtrim(text or ""))
    local removed = false
    for _, listKey in ipairs(LISTS) do
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

local function FormatTime(seconds)
    if seconds >= 3600 then
        return format("%dh", ceil(seconds / 3600))
    elseif seconds >= 60 then
        return format("%dm", ceil(seconds / 60))
    end
    return format("%d", seconds)
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
    local icon = CreateFrame("Frame", nil, container)

    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetReverse(true)
    icon.cooldown:SetDrawEdge(false)
    if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(true) end

    -- Text sits above the cooldown swipe
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)

    icon.count = overlay:CreateFontString(nil, "OVERLAY")
    icon.count:SetPoint("TOPRIGHT", 2, 1)
    icon.timer = overlay:CreateFontString(nil, "OVERLAY")
    icon.timer:SetPoint("BOTTOM", 0, 1)

    icon:SetScript("OnEnter", Icon_OnEnter)
    icon:SetScript("OnLeave", Icon_OnLeave)
    return icon
end

-- Applies size, position and font settings; only runs when settings change or the icon is new
local function LayoutIcon(container, i, icon)
    local size, step = db.iconSize, db.iconSize + db.spacing
    local fontSize = max(8, floor(size * 0.45))
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", container, "TOPLEFT", ((i - 1) % db.perRow) * step, -floor((i - 1) / db.perRow) * step)
    icon:EnableMouse(db.showTooltips)
    icon.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    icon.timer:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
end

-- Updates the time-remaining text, only touching a FontString when its whole-second value changes
local function UpdateTimers(container)
    local now = GetTime()
    for i = 1, container.numShown do
        local icon = container.icons[i]
        local seconds = icon.expiration > 0 and ceil(icon.expiration - now) or 0
        if seconds < 0 then seconds = 0 end
        if icon.timerSeconds ~= seconds then
            icon.timerSeconds = seconds
            icon.timer:SetText(seconds > 0 and FormatTime(seconds) or "")
        end
    end
end

local function Container_OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < TIMER_INTERVAL then return end
    self.elapsed = 0
    UpdateTimers(self)
end

local function GetContainer(unit)
    local container = containers[unit]
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        container.unit = unit
        container.icons = {}
        container.entries = {}
        container.numShown = 0
        container.elapsed = 0
        container:SetSize(1, 1)
        container:Hide()
        containers[unit] = container
    end
    return container
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

local function AnchorContainer(container)
    local anchor = FindAnchor(container.unit)
    container.anchor = anchor
    if not anchor then return end
    container:SetParent(anchor)
    container:SetFrameStrata(anchor:GetFrameStrata())
    container:SetFrameLevel(anchor:GetFrameLevel() + 5)
    container:ClearAllPoints()
    if db.anchor == "BELOW" then
        container:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", db.offsetX, db.offsetY)
    else
        container:SetPoint("TOPLEFT", anchor, "TOPRIGHT", db.offsetX, db.offsetY)
    end
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- Fills entries with the unit's buffs that pass the filters, sorted for display; returns the count
local function CollectBuffs(unit, entries)
    local n = 0
    local allowOnly = db.filterMode == "allow"
    for i = 1, MAX_SCAN do
        local name, texture, count, duration, expiration, source, spellId = GetBuff(unit, i)
        if not name then break end
        local key = lowerNames[name]
        if not key then
            key = strlower(name)
            lowerNames[name] = key
        end
        local rank = allowRank[key] or (spellId and allowRank[spellId])
        local denied = denySet[key] or (spellId and denySet[spellId])
        if not denied and (rank or not allowOnly) then
            n = n + 1
            local entry = entries[n] or {}
            entries[n] = entry
            entry.index, entry.texture, entry.count = i, texture, count
            entry.duration, entry.expiration = duration, expiration
            entry.mine = source == "player"
            -- Allow-list buffs come first, in list order, so they always sit in the same spot
            entry.order = (rank or 1000) * 100 + i
        end
    end

    -- Insertion sort of the first n entries (n is small)
    for i = 2, n do
        local entry = entries[i]
        local j = i - 1
        while j >= 1 and entries[j].order > entry.order do
            entries[j + 1] = entries[j]
            j = j - 1
        end
        entries[j + 1] = entry
    end
    return n
end

local function UpdateUnit(unit)
    local container = containers[unit]
    if not container then return end

    if not db.enabled or (unit == "player" and not db.showOnPlayer)
        or not container.anchor or not UnitExists(unit) then
        container.numShown = 0
        container:SetScript("OnUpdate", nil)
        container:Hide()
        return
    end

    local icons = container.icons
    if container.layoutVersion ~= layoutVersion then
        container.layoutVersion = layoutVersion
        for i, icon in ipairs(icons) do
            LayoutIcon(container, i, icon)
        end
    end

    local shown = min(CollectBuffs(unit, container.entries), db.maxIcons)
    local hasTimer = false

    for i = 1, shown do
        local entry = container.entries[i]
        local icon = icons[i]
        if not icon then
            icon = CreateIcon(container)
            icons[i] = icon
            LayoutIcon(container, i, icon)
        end
        icon.unit, icon.index = unit, entry.index

        icon.texture:SetTexture(entry.texture)
        if db.highlightMine and entry.mine then
            icon.border:SetColorTexture(0.1, 1, 0.1, 1)
        else
            icon.border:SetColorTexture(0, 0, 0, 1)
        end

        local timed = entry.duration and entry.duration > 0 and entry.expiration and entry.expiration > 0
        if timed then
            icon.cooldown:SetCooldown(entry.expiration - entry.duration, entry.duration)
            icon.cooldown:Show()
            hasTimer = true
        else
            icon.cooldown:Hide()
        end
        icon.expiration = (timed and db.showTimers) and entry.expiration or 0
        icon.timerSeconds = nil

        icon.count:SetText(entry.count and entry.count > 1 and entry.count or "")
        icon:Show()
    end
    for i = shown + 1, #icons do
        icons[i]:Hide()
    end

    container.numShown = shown
    UpdateTimers(container)
    -- Only tick while there is a countdown to show
    container:SetScript("OnUpdate", (hasTimer and db.showTimers) and Container_OnUpdate or nil)
    container:SetShown(shown > 0)
end

-- Re-anchors and redraws every unit; call after any settings change
function ns.RefreshAll()
    if not db then return end
    layoutVersion = layoutVersion + 1
    for _, unit in ipairs(UNITS) do
        AnchorContainer(GetContainer(unit))
        UpdateUnit(unit)
    end
end

-- Coalesces bursts of roster/frame events into a single RefreshAll
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
    if event == "UNIT_AURA" then
        -- Most frequent event, so it is checked first
        if containers[arg1] then UpdateUnit(arg1) end
    elseif event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        OsoPartyBuffsDB = OsoPartyBuffsDB or {}
        db = CopyDefaults(ns.DEFAULTS, OsoPartyBuffsDB)
        ns.db = db
        ns.RebuildFilters()
        ns.RegisterOptions()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if PartyMemberBuffTooltip then
            PartyMemberBuffTooltip:HookScript("OnShow", function(self)
                if db.hideBlizzardPopup then self:Hide() end
            end)
        end
        if CompactUnitFrame_SetUnit then
            -- Also called for every nameplate, so only refresh when a party/player frame changes
            hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
                if not trackedUnits[unit] then unit = nil end
                if compactUnits[frame] ~= unit then
                    compactUnits[frame] = unit
                    ScheduleRefresh()
                end
            end)
        end
        ns.RefreshAll()
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
        Print("/opb list - print both lists")
        Print("/opb reset - restore defaults")
    end
    ns.RefreshOptions()
end
