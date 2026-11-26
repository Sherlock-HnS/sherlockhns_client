-- Shared client UI. Authored for SherlockHNS; no reference implementation is imported.
SherlockHNS.UI = SherlockHNS.UI or {}
local UI = SherlockHNS.UI
UI.Colors = {
    background = Color(20, 20, 23, 248),
    surface = Color(34, 34, 38),
    raised = Color(45, 45, 50),
    border = Color(65, 65, 72),
    accent = Color(210, 168, 40),
    text = Color(235, 235, 238),
    muted = Color(165, 165, 175)
}
local C = UI.Colors

-- Viewport metrics are stable between resize events; HUD code can call Scale()
-- and Unit() repeatedly without querying the screen dimensions every frame.
local scale = math.min(ScrW() / 1920, ScrH() / 1080)

-- Font cache is split by weight and pixel size. Alternate families get an
-- independent two-level cache so they cannot collide with the default Tahoma.
local fontCache = {}
local alternateFontCaches = {}
local fontPrefixes = {
    Tahoma = 'HNS_UI_',
    ['Trebuchet MS'] = 'HNS_UI_Trebuchet_MS_',
}

function UI.Scale() return scale end

function UI.Unit(value) return math.max(1, math.Round(value * scale)) end

local function GetFontCache(font)
    if font == 'Tahoma' then return fontCache end

    local byFamily = alternateFontCaches[font]
    if not byFamily then
        byFamily = {}
        alternateFontCaches[font] = byFamily
    end
    return byFamily
end

-- Accepts logical UI units and applies the shared viewport scale once.
function UI.Font(size, weight, font)
    return UI.FontPixels(UI.Unit(size), weight, font)
end

-- For callers that already calculated their final pixel size (HUD.U, for example).
function UI.FontPixels(size, weight, font)
    weight = weight or 500
    font = font or 'Tahoma'

    local pixels = math.max(12, math.Round(size))
    local cache = GetFontCache(font)
    local byW = cache[weight]
    if not byW then
        byW = {}
        cache[weight] = byW
    end

    local name = byW[pixels]
    if name then return name end

    local prefix = fontPrefixes[font] or ('HNS_UI_' .. font:gsub('[^%w]', '_') .. '_')
    name = prefix .. pixels .. '_' .. weight
    UI.Fonts = UI.Fonts or {}
    if not UI.Fonts[name] then
        surface.CreateFont(name, { font = font, size = pixels, weight = weight, extended = true })
        UI.Fonts[name] = true
    end

    byW[pixels] = name
    return name
end

-- Iterate code points so shortened labels remain valid UTF-8.
function UI.Fit(value, font, width)
    local text = tostring(value or '')
    if not utf8.len(text) then text = text:gsub('[\128-\255]', '?') end
    surface.SetFont(font)
    if surface.GetTextSize(text) <= width then return text end
    local suffix = '…'
    if surface.GetTextSize(suffix) > width then return '' end
    local result = ''
    for _, code in utf8.codes(text) do
        local nextText = result .. utf8.char(code)
        if surface.GetTextSize(nextText .. suffix) > width then break end
        result = nextText
    end
    return result .. suffix
end

function UI.Bounds(w, h)
    local margin = math.min(16, math.floor(math.min(ScrW(), ScrH()) / 20))
    return math.max(1, math.min(w, ScrW() - margin * 2)), math.max(1, math.min(h, ScrH() - margin * 2))
end

local windows = setmetatable({}, { __mode = 'k' })
function UI.HasWindow(minimumPriority, except)
    for panel, size in pairs(windows) do
        if panel ~= except and IsValid(panel) and panel:IsVisible() and size[3] >= (minimumPriority or 70) then return true end
    end
    return false
end

function UI.GameplayVisible()
    return not UI.HasWindow(70) and not (SherlockHNS.IsMenuOpen and SherlockHNS.IsMenuOpen())
end

function UI.Window(panel, width, height, priority)
    windows[panel] = { width, height, priority or 50 }
    panel:SetSize(UI.Bounds(width, height))
    panel:Center()
    panel:SetZPos(priority or 50)
end

hook.Add('OnScreenSizeChanged', 'HNS_UI_Viewport', function()
    scale = math.min(ScrW() / 1920, ScrH() / 1080)
    fontCache = {}
    alternateFontCaches = {}

    for panel, size in pairs(windows) do
        if IsValid(panel) then
            panel:SetSize(UI.Bounds(size[1], size[2])); panel:Center(); panel:InvalidateLayout(true)
        end
    end
end)
-- Explicit flow containers preserve creation order and grow vertically when actions wrap.
function UI.Flow(panel, height)
    panel.PerformLayout = function(self, width)
        local x, y, rowHeight = 0, 0, height or 32
        for _, child in ipairs(self:GetChildren()) do
            if child:IsVisible() then
                child.HNSFlowWidth = child.HNSFlowWidth or child:GetWide()
                local cw = math.min(child.HNSFlowWidth, math.max(1, width))
                if x > 0 and x + cw > width then
                    x = 0; y = y + rowHeight + 6
                end
                child:Dock(NODOCK)
                child:SetPos(x, y); child:SetSize(cw, rowHeight)
                x = x + cw + 6
            end
        end
        local wanted = y + rowHeight
        if self:GetTall() ~= wanted then self:SetTall(wanted) end
    end
end

-- Sidebars become a top pane on narrow displays. The content keeps the remaining space.
function UI.Split(parent, sidebar, preferred, breakpoint)
    local previous = parent.PerformLayout
    parent.PerformLayout = function(self, w, h)
        if previous then previous(self, w, h) end
        if w < (breakpoint or 760) then
            sidebar:Dock(TOP); sidebar:SetTall(math.min(180, math.floor(h * 0.35)))
            sidebar:DockMargin(0, 0, 0, 8)
        else
            sidebar:Dock(LEFT); sidebar:SetWide(math.min(preferred, math.floor(w * 0.38)))
            sidebar:DockMargin(0, 0, 8, 0)
        end
    end
end

function UI.Form(parent)
    local scroll = UI.Create('DScrollPanel', parent)
    scroll.DockPadding = function(self, ...) self:GetCanvas():DockPadding(...) end
    scroll:DockPadding(10, 10, 10, 10)
    return scroll
end

local skin = { PrintName = 'Sherlock HnS', Author = 'SherlockHNS' }
skin.Colours = table.Copy(derma.GetSkinTable().Default.Colours)
skin.Colours.Label.Default = C.text
skin.Colours.Label.Dark = C.text
skin.Colours.Label.Bright = color_white
for _, state in pairs(skin.Colours.Tab) do
    state.Normal = C.text; state.Hover = color_white; state.Down = C.accent; state.Disabled = C.muted
end
skin.Colours.Button.Normal = C.text
skin.Colours.Button.Hover = color_white
skin.Colours.Button.Down = C.accent
skin.Colours.Button.Disabled = C.muted
-- DComboBox choices are DMenuOption buttons, so theme both the closed field
-- and the menu options through the skin used by the whole gamemode.
skin.Colours.ComboBox = skin.Colours.ComboBox or {}
skin.Colours.ComboBox.Default = C.text
skin.Colours.ComboBox.Disabled = C.muted
skin.Colours.Menu = skin.Colours.Menu or {}
skin.Colours.Menu.Normal = C.text
skin.Colours.Menu.Hover = color_white
skin.Colours.Menu.Down = C.accent
skin.Colours.Menu.Disabled = C.muted
function skin:PaintFrame(panel, w, h)
    draw.RoundedBox(8, 0, 0, w, h, C.background)
    draw.RoundedBoxEx(8, 0, 0, w, 28, C.surface, true, true, false, false)
    surface.SetDrawColor(C.accent); surface.DrawRect(0, 28, w, 2)
end

function skin:PaintButton(panel, w, h)
    if not panel:GetPaintBackground() then return end
    draw.RoundedBox(4, 0, 0, w, h, panel:IsDown() and C.border or (panel:IsHovered() and C.raised or C.surface))
    if panel:HasFocus() then
        surface.SetDrawColor(C.accent); surface.DrawOutlinedRect(0, 0, w, h)
    end
end

function skin:PaintComboBox(panel, w, h)
    draw.RoundedBox(4, 0, 0, w, h, panel:IsHovered() and C.raised or C.surface)
    surface.SetDrawColor(panel:HasFocus() and C.accent or C.border)
    surface.DrawOutlinedRect(0, 0, w, h)
end

function skin:PaintMenu(panel, w, h)
    draw.RoundedBox(4, 0, 0, w, h, C.surface)
    surface.SetDrawColor(C.border)
    surface.DrawOutlinedRect(0, 0, w, h)
end

function skin:PaintMenuOption(panel, w, h)
    if panel:IsHovered() or panel:IsDown() then
        draw.RoundedBox(2, 2, 0, w - 4, h, panel:IsDown() and C.border or C.raised)
    end
end

function skin:PaintPropertySheet(panel, w, h) draw.RoundedBox(4, 0, 0, w, h, C.background) end

function skin:PaintTab(panel, w, h)
    draw.RoundedBox(4, 0, 0, w, h, panel:IsActive() and C.raised or C.surface)
    if panel:IsActive() then
        surface.SetDrawColor(C.accent); surface.DrawRect(0, 0, w, 2)
    end
end

function skin:PaintListView(panel, w, h) draw.RoundedBox(4, 0, 0, w, h, C.surface) end

function skin:PaintListViewLine(panel, w, h)
    if panel:IsLineSelected() or panel:IsHovered() then
        surface.SetDrawColor(panel:IsLineSelected() and C.border or C.raised); surface.DrawRect(0, 0, w, h)
    end
end

function skin:PaintVScrollBar(panel, w, h) draw.RoundedBox(4, 2, 0, w - 4, h, C.surface) end

function skin:PaintScrollBarGrip(panel, w, h) draw.RoundedBox(4, 3, 0, w - 6, h, C.accent) end

derma.DefineSkin('SherlockHNS', 'Shared gamemode theme', skin, 'Default')
function UI.Create(class, parent, name)
    local panel = vgui.Create(class, parent, name)
    panel:SetSkin('SherlockHNS')
    if class == 'DButton' or class == 'DLabel' or class == 'DTextEntry' then panel:SetFont(UI.Font(16)) end
    if class == 'DLabel' then panel:SetTextColor(C.text) end
    if class == 'DComboBox' then
        panel:SetFont(UI.Font(16))
        panel:SetTextColor(C.text)
        panel:SetContentAlignment(5)
        panel:SetTextInset(8, 0)
    end
    if class == 'DCheckBoxLabel' then
        panel.Label:SetFont(UI.Font(16))
        panel.Label:SetWrap(true); panel.Label:SetAutoStretchVertical(true)
        panel.PerformLayout = function(self, w)
            self.Label:SetPos(24, 2); self.Label:SetWide(math.max(1, w - 24))
            self.Button:SetPos(0, 4); self.Button:SetSize(16, 16)
            local height = math.max(24, self.Label:GetTall() + 4)
            if self:GetTall() ~= height then self:SetTall(height) end
        end
    end
    if class == 'DNumSlider' then
        panel.Label:SetFont(UI.Font(16)); panel.Label:SetWrap(true)
        panel:SetTall(40)
    end
    if class == 'DScrollPanel' then panel:GetVBar():SetHideButtons(true) end
    if class == 'DTextEntry' then
        panel:SetTextColor(C.text); panel:SetHighlightColor(C.accent); panel:SetCursorColor(C.text)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, C.surface)
            surface.SetDrawColor(self:HasFocus() and C.accent or C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
            if self:GetText() == '' and not self:HasFocus() and self.GetPlaceholderText then
                draw.SimpleText(UI.Fit(self:GetPlaceholderText() or '', self:GetFont(), w - 10), self:GetFont(), 5, h / 2,
                    C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            self:DrawTextEntryText(C.text, C.accent, C.text)
        end
    end
    if class == 'DFrame' then
        timer.Simple(0, function()
            if IsValid(panel) and not windows[panel] then UI.Window(panel, panel:GetWide(), panel:GetTall(), 80) end
        end)
    end
    return panel
end

-- HUD lanes: round 0-100; announcements 110-180; poll 190-230;
-- mutation banners 250+, abilities bottom centre, party left, music bottom left.
function UI.HUDY(lane)
    local position = { round = 20, announce = 160, poll = 245, mutation = 310, status = 100 }
    local minimum = { round = 8, announce = 125, poll = 205, mutation = 255, status = 60 }
    return math.max(minimum[lane] or 8, UI.Unit(position[lane] or 20))
end
