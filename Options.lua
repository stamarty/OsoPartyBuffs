local ADDON_NAME, ns = ...

local panel
local controls = {}

local LEFT_X, RIGHT_X = 16, 330
local LIST_WIDTH, LIST_HEIGHT = 270, 220

local function Label(parent, text, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Register(control)
    controls[#controls + 1] = control
    return control
end

local function CheckBox(parent, text, key, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    cb.label = Label(cb, text, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        ns.RefreshAll()
    end)
    function cb:Refresh()
        self:SetChecked(ns.db[key])
    end
    return Register(cb)
end

-- options = { { value, text }, ... }
local function RadioGroup(parent, title, key, options, x, y)
    local group = CreateFrame("Frame", nil, parent)
    group:SetPoint("TOPLEFT", x, y)
    group:SetSize(290, 18 + #options * 20)
    Label(group, title):SetPoint("TOPLEFT")

    group.buttons = {}
    for i, opt in ipairs(options) do
        local rb = CreateFrame("CheckButton", nil, group, "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", 4, -18 - (i - 1) * 20)
        rb.value = opt[1]
        rb.label = Label(rb, opt[2], "GameFontHighlightSmall")
        rb.label:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        rb:SetScript("OnClick", function(self)
            ns.db[key] = self.value
            group:Refresh()
            ns.RefreshAll()
        end)
        group.buttons[i] = rb
    end

    function group:Refresh()
        for _, rb in ipairs(self.buttons) do
            rb:SetChecked(ns.db[key] == rb.value)
        end
    end
    return Register(group)
end

local function Slider(parent, text, key, minV, maxV, step, x, y, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width, 36)

    holder.label = Label(holder, "", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT")

    local s = CreateFrame("Slider", nil, holder)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 0, -14)
    s:SetPoint("TOPRIGHT", 0, -14)
    s:SetHeight(18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.6)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)

    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:GetThumbTexture():SetSize(32, 32)

    local function Snap(v)
        return math.floor(v / step + 0.5) * step
    end

    s:SetScript("OnValueChanged", function(_, v)
        v = Snap(v)
        holder.label:SetText(text .. ": " .. v)
        if holder.refreshing then return end
        if ns.db[key] ~= v then
            ns.db[key] = v
            ns.RefreshAll()
        end
    end)

    -- Mouse wheel for exact one-step adjustments
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(Snap(self:GetValue()) + delta * step)
    end)

    function holder:Refresh()
        self.refreshing = true
        s:SetValue(ns.db[key])
        self.label:SetText(text .. ": " .. ns.db[key])
        self.refreshing = false
    end
    return Register(holder)
end

local function ListEditor(parent, title, hint, listKey, x, y)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(LIST_WIDTH, LIST_HEIGHT)

    local t = Label(f, title)
    t:SetPoint("TOPLEFT")
    local h = Label(f, hint, "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
    h:SetWidth(LIST_WIDTH)

    local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(LIST_WIDTH - 72, 20)
    input:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 6, -4)
    input:SetAutoFocus(false)

    local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    add:SetSize(60, 22)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    add:SetText("Add")

    local function DoAdd()
        if ns.AddEntry(listKey, input:GetText()) then
            input:SetText("")
        end
        input:ClearFocus()
        f:Refresh()
    end
    add:SetScript("OnClick", DoAdd)
    input:SetScript("OnEnterPressed", DoAdd)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    box:SetPoint("BOTTOMRIGHT")
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local rowWidth = LIST_WIDTH - 34
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(rowWidth, 1)
    scroll:SetScrollChild(child)

    f.empty = Label(box, "(empty)", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", 8, -8)

    f.rows = {}
    function f:Refresh()
        local list = ns.db[listKey]
        for i, entry in ipairs(list) do
            local row = self.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetSize(rowWidth, 18)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
                row.text = Label(row, "", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", 4, 0)
                row.text:SetPoint("RIGHT", -22, 0)
                row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                row.remove:SetSize(20, 20)
                row.remove:SetPoint("RIGHT", 2, 0)
                row.remove:SetScript("OnClick", function(btn)
                    ns.RemoveEntry(listKey, btn:GetParent().index)
                    f:Refresh()
                end)
                self.rows[i] = row
            end
            row.index = i
            row.text:SetText(entry)
            row:Show()
        end
        for i = #list + 1, #self.rows do
            self.rows[i]:Hide()
        end
        child:SetHeight(math.max(1, #list * 18))
        self.empty:SetShown(#list == 0)
    end
    return Register(f)
end

function ns.RefreshOptions()
    for _, c in ipairs(controls) do
        c:Refresh()
    end
end

function ns.CreateOptions()
    panel = CreateFrame("Frame")
    panel.name = "Oso Party Buffs"
    panel:Hide()

    local title = Label(panel, "Oso Party Buffs", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_X, -16)
    local sub = Label(panel, "Shows buffs from any source on your party frames.", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- Left column: general + layout
    CheckBox(panel, "Enabled", "enabled", LEFT_X, -60)
    CheckBox(panel, "Also show on my player frame", "showOnPlayer", LEFT_X, -84)
    CheckBox(panel, "Show tooltips on hover", "tooltips", LEFT_X, -108)
    CheckBox(panel, "Green border on buffs I cast", "highlightMine", LEFT_X, -132)
    CheckBox(panel, "Show time remaining", "showTimers", LEFT_X, -156)

    RadioGroup(panel, "Which buffs to show", "filterMode", {
        { "all", "All buffs except the deny list" },
        { "allow", "Only buffs in the allow list" },
    }, LEFT_X, -192)

    RadioGroup(panel, "Position", "anchor", {
        { "RIGHT", "To the right of the frame" },
        { "BELOW", "Below the frame" },
    }, LEFT_X, -258)

    local half = 135
    Slider(panel, "Icon size", "iconSize", 10, 48, 1, LEFT_X, -326, half)
    Slider(panel, "Icons per row", "perRow", 1, 16, 1, LEFT_X + half + 16, -326, half)
    Slider(panel, "Max icons", "maxIcons", 1, 32, 1, LEFT_X, -372, half)
    Slider(panel, "Spacing", "spacing", 0, 10, 1, LEFT_X + half + 16, -372, half)
    Slider(panel, "X offset", "offsetX", -200, 200, 1, LEFT_X, -418, half)
    Slider(panel, "Y offset", "offsetY", -200, 200, 1, LEFT_X + half + 16, -418, half)

    local tip = Label(panel, "Tip: scroll the mouse wheel over a slider for single steps.", "GameFontDisableSmall")
    tip:SetPoint("TOPLEFT", LEFT_X, -462)

    -- Right column: lists
    ListEditor(panel, "Allow list",
        "Always shown first, in this order. Buff name (all ranks) or spell ID.",
        "allow", RIGHT_X, -60)
    ListEditor(panel, "Deny list",
        "Never shown. Buff name (all ranks) or spell ID.",
        "deny", RIGHT_X, -296)

    panel:SetScript("OnShow", ns.RefreshOptions)

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
