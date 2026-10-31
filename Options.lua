--[[
    Oso Party Buffs - Options.lua

    The settings panel under Options > AddOns: checkboxes, filter and position
    choices, size/layout sliders, and editors for the allow and deny lists.
    The panel is registered at load but its controls are only built the first
    time it is opened, so it costs nothing at login. Settings are read from and
    written to ns.db, which Core.lua sets up.
]]

local _, ns = ...

local panel
local built = false
local controls = {}     -- every control with a Refresh method, refreshed when the panel shows

local LEFT_X, RIGHT_X = 16, 330
local LIST_WIDTH, LIST_HEIGHT = 270, 220
local ROW_HEIGHT = 18

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function Label(parent, text, template)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label
end

local function Register(control)
    controls[#controls + 1] = control
    return control
end

-- Checkbox bound to a boolean setting
local function CheckBox(parent, text, key, x, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    check.label = Label(check, text, "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        ns.RefreshAll()
    end)
    function check:Refresh()
        self:SetChecked(ns.db[key])
    end
    return Register(check)
end

-- Radio buttons bound to one setting; choices = { { value, text }, ... }
local function RadioGroup(parent, title, key, choices, x, y)
    local group = CreateFrame("Frame", nil, parent)
    group:SetPoint("TOPLEFT", x, y)
    group:SetSize(290, 18 + #choices * 20)
    Label(group, title):SetPoint("TOPLEFT")

    group.buttons = {}
    for i, choice in ipairs(choices) do
        local radio = CreateFrame("CheckButton", nil, group, "UIRadioButtonTemplate")
        radio:SetPoint("TOPLEFT", 4, -18 - (i - 1) * 20)
        radio.value = choice[1]
        radio.label = Label(radio, choice[2], "GameFontHighlightSmall")
        radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
        radio:SetScript("OnClick", function(self)
            ns.db[key] = self.value
            group:Refresh()
            ns.RefreshAll()
        end)
        group.buttons[i] = radio
    end

    function group:Refresh()
        for _, radio in ipairs(self.buttons) do
            radio:SetChecked(ns.db[key] == radio.value)
        end
    end
    return Register(group)
end

-- Slider bound to a numeric setting, with its current value shown in the label
local function Slider(parent, text, key, minValue, maxValue, step, x, y, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width, 36)

    holder.label = Label(holder, "", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT")

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -14)
    slider:SetPoint("TOPRIGHT", 0, -14)
    slider:SetHeight(18)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.6)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)

    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(32, 32)

    local function Snap(value)
        return math.floor(value / step + 0.5) * step
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = Snap(value)
        holder.label:SetText(text .. ": " .. value)
        if holder.refreshing then return end
        if ns.db[key] ~= value then
            ns.db[key] = value
            ns.RefreshAll()
        end
    end)

    -- Mouse wheel for exact one-step adjustments
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(Snap(self:GetValue()) + delta * step)
    end)

    function holder:Refresh()
        self.refreshing = true
        slider:SetValue(ns.db[key])
        self.label:SetText(text .. ": " .. ns.db[key])
        self.refreshing = false
    end
    return Register(holder)
end

-- Text box, Add button and scrolling list with remove buttons for the "allow" or "deny" list
local function ListEditor(parent, title, hint, listKey, x, y)
    local editor = CreateFrame("Frame", nil, parent)
    editor:SetPoint("TOPLEFT", x, y)
    editor:SetSize(LIST_WIDTH, LIST_HEIGHT)

    local titleLabel = Label(editor, title)
    titleLabel:SetPoint("TOPLEFT")
    local hintLabel = Label(editor, hint, "GameFontDisableSmall")
    hintLabel:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -2)
    hintLabel:SetWidth(LIST_WIDTH)

    local input = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    input:SetSize(LIST_WIDTH - 72, 20)
    input:SetPoint("TOPLEFT", hintLabel, "BOTTOMLEFT", 6, -4)
    input:SetAutoFocus(false)

    local addButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    addButton:SetSize(60, 22)
    addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
    addButton:SetText("Add")

    local function AddFromInput()
        if ns.AddEntry(listKey, input:GetText()) then
            input:SetText("")
        end
        input:ClearFocus()
        editor:Refresh()
    end
    addButton:SetScript("OnClick", AddFromInput)
    input:SetScript("OnEnterPressed", AddFromInput)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local box = CreateFrame("Frame", nil, editor)
    box:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    box:SetPoint("BOTTOMRIGHT")
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.4)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local rowWidth = LIST_WIDTH - 34
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(rowWidth, 1)
    scroll:SetScrollChild(content)

    editor.emptyLabel = Label(box, "(empty)", "GameFontDisableSmall")
    editor.emptyLabel:SetPoint("TOPLEFT", 8, -8)

    local function RemoveButton_OnClick(button)
        ns.RemoveEntry(listKey, button:GetParent().index)
        editor:Refresh()
    end

    editor.rows = {}
    function editor:Refresh()
        local list = ns.db[listKey]
        for i, entry in ipairs(list) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(rowWidth, ROW_HEIGHT)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                row.label = Label(row, "", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", 4, 0)
                row.label:SetPoint("RIGHT", -22, 0)
                row.removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                row.removeButton:SetSize(20, 20)
                row.removeButton:SetPoint("RIGHT", 2, 0)
                row.removeButton:SetScript("OnClick", RemoveButton_OnClick)
                self.rows[i] = row
            end
            row.index = i
            row.label:SetText(entry)
            row:Show()
        end
        for i = #list + 1, #self.rows do
            self.rows[i]:Hide()
        end
        content:SetHeight(math.max(1, #list * ROW_HEIGHT))
        self.emptyLabel:SetShown(#list == 0)
    end
    return Register(editor)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function BuildPanel()
    local title = Label(panel, "Oso Party Buffs", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_X, -16)
    local subtitle = Label(panel, "Shows buffs from any source on your party frames.", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- Left column: general options, filter mode, position and layout
    CheckBox(panel, "Enabled", "enabled", LEFT_X, -60)
    CheckBox(panel, "Also show on my player frame", "showOnPlayer", LEFT_X, -84)
    CheckBox(panel, "Show tooltips on hover", "tooltips", LEFT_X, -108)
    CheckBox(panel, "Green border on buffs I cast", "highlightMine", LEFT_X, -132)
    CheckBox(panel, "Show time remaining", "showTimers", LEFT_X, -156)
    CheckBox(panel, "Hide Blizzard's buff pop-up on party frames", "hideBlizzardPopup", LEFT_X, -180)

    RadioGroup(panel, "Which buffs to show", "filterMode", {
        { "all", "All buffs except the deny list" },
        { "allow", "Only buffs in the allow list" },
    }, LEFT_X, -216)

    RadioGroup(panel, "Position", "anchor", {
        { "RIGHT", "To the right of the frame" },
        { "BELOW", "Below the frame" },
    }, LEFT_X, -282)

    local half = 135
    Slider(panel, "Icon size", "iconSize", 10, 48, 1, LEFT_X, -350, half)
    Slider(panel, "Icons per row", "perRow", 1, 16, 1, LEFT_X + half + 16, -350, half)
    Slider(panel, "Max icons", "maxIcons", 1, 32, 1, LEFT_X, -396, half)
    Slider(panel, "Spacing", "spacing", 0, 10, 1, LEFT_X + half + 16, -396, half)
    Slider(panel, "X offset", "offsetX", -200, 200, 1, LEFT_X, -442, half)
    Slider(panel, "Y offset", "offsetY", -200, 200, 1, LEFT_X + half + 16, -442, half)

    local tip = Label(panel, "Settings are saved per character. Scroll a slider for single steps.", "GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", LEFT_X, -486)

    -- Right column: allow and deny lists
    ListEditor(panel, "Allow list",
        "Always shown first, in this order. Buff name (all ranks) or spell ID.",
        "allow", RIGHT_X, -60)
    ListEditor(panel, "Deny list",
        "Never shown. Buff name (all ranks) or spell ID.",
        "deny", RIGHT_X, -296)
end

-- Syncs every control with ns.db; skipped while the panel is closed since OnShow refreshes anyway
function ns.RefreshOptions()
    if not (panel and panel:IsShown()) then return end
    for _, control in ipairs(controls) do
        control:Refresh()
    end
end

-- Registers an empty panel with the game's options UI; called from Core.lua on ADDON_LOADED
function ns.RegisterOptions()
    panel = CreateFrame("Frame")
    panel.name = "Oso Party Buffs"
    panel:Hide()
    panel:SetScript("OnShow", function()
        if not built then
            built = true
            BuildPanel()
        end
        ns.RefreshOptions()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenOptions()
    if ns.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the old options frame doesn't scroll to the addon on the first call
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
