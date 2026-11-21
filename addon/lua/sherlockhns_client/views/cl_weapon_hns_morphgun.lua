local MODES, TEAMS = SWEP.HNSModes, SWEP.HNSTeams
local TEAM_COUNT = 3

function SWEP:PrimaryAttack() self:SetNextPrimaryFire(CurTime() + 0.4) end
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if IsFirstTimePredicted() then self:OpenMenu() end
end
function SWEP:Reload() end

local frame

local function PillLabel(name)
    local t = pk_pills and pk_pills.getPillTable(name)
    return t and tostring(t.printName or name) or name
end

local function AllPills()
    local out = {}
    if not (pk_pills and pk_pills.Forms) then return out end
    for name, t in pairs(pk_pills.Forms) do
        if t.printName then out[#out + 1] = { name = name, label = tostring(t.printName) } end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

function SWEP:OpenMenu()
    if IsValid(frame) then frame:Remove() end

    local curMode, curPill, curTeam = self:GetMorphMode(), self:GetMorphPill(), self:GetMorphTeam()

    -- ordem escrita = ordem lida em sv_morph.lua: modo, pill, time
    local function Push()
        net.Start("sherlockhns_morph_set")
        net.WriteUInt(curMode, 2)
        net.WriteString(curPill)
        net.WriteUInt(curTeam, 2)
        net.SendToServer()
    end

    frame = vgui.Create("DFrame")
    frame:SetTitle("Morph Gun")
    frame:SetSize(420, 550)
    frame:Center()
    frame:MakePopup()

    local combo = vgui.Create("DComboBox", frame)
    combo:Dock(TOP)
    combo:DockMargin(0, 0, 0, 6)
    for id = 0, 3 do combo:AddChoice(MODES[id], id, id == curMode) end
    combo.OnSelect = function(_, _, _, data)
        curMode = data
        Push()
    end

    -- time aplicado junto com a pill (modos "Pill específica" e "Pill aleatória")
    local teamCombo = vgui.Create("DComboBox", frame)
    teamCombo:Dock(TOP)
    teamCombo:DockMargin(0, 0, 0, 6)
    for id = 0, TEAM_COUNT - 1 do teamCombo:AddChoice("Time: " .. TEAMS[id], id, id == curTeam) end
    teamCombo.OnSelect = function(_, _, _, data)
        curTeam = data
        Push()
    end

    local current = vgui.Create("DLabel", frame)
    current:Dock(TOP)
    current:DockMargin(0, 0, 0, 6)
    current:SetTall(18)
    current:SetFont("DermaDefaultBold")
    current:SetText("Pill escolhida: " .. (curPill ~= "" and PillLabel(curPill) or "nenhuma"))

    local search = vgui.Create("DTextEntry", frame)
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, 6)
    search:SetPlaceholderText("Buscar pill...")

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("Pill")
    list:AddColumn("ID")

    local pills = AllPills()
    local function Populate()
        local filter = string.lower(search:GetValue() or "")
        list:Clear()
        for _, p in ipairs(pills) do
            if filter == "" or p.label:lower():find(filter, 1, true) or p.name:lower():find(filter, 1, true) then
                list:AddLine(p.label, p.name)
            end
        end
    end
    search.OnChange = Populate
    Populate()

    -- escolher uma pill muda o modo para "pill específica"
    list.OnRowSelected = function(_, _, line)
        curPill = line:GetColumnText(2)
        current:SetText("Pill escolhida: " .. PillLabel(curPill))
        combo:ChooseOptionID(1) -- dispara OnSelect -> Push
    end
end

function SWEP:DrawHUD()
    local sw, sh = ScrW(), ScrH()
    local mode, pill, teamSel = self:GetMorphMode(), self:GetMorphPill(), self:GetMorphTeam()

    local txt = "MORPH GUN  |  Modo: " .. (MODES[mode] or "?")
    if mode == 0 then
        txt = txt .. "  |  Pill: " .. (pill ~= "" and PillLabel(pill) or "nenhuma")
    end
    if mode == 0 or mode == 1 then
        txt = txt .. "  |  " .. (TEAMS[teamSel] or "?")
    end

    draw.SimpleTextOutlined(txt, "DermaDefaultBold", sw / 2, sh - 110, Color(120, 200, 255),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("M1: aplicar  |  Shift+M1: em si  |  M2: menu  |  R: modo  |  Shift+R: time",
        "DermaDefault", sw / 2, sh - 88, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end
