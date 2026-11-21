-- Aba "AFK" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("AFK", SherlockHNS.BuildAfkTab(sheet), "icon16/user_delete.png")

local AFK = SherlockHNS.Afk


local function SendConfig(key, value)
    net.Start("sherlockhns_admin_config")
    net.WriteString(key)
    net.WriteFloat(value)
    net.SendToServer()
end

function SherlockHNS.BuildAfkTab(sheet)
    local pnl = SherlockHNS.UI.Form(sheet)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    local hint = SherlockHNS.UI.Create("DLabel", pnl)
    hint:Dock(TOP)
    hint:SetWrap(true)
    hint:SetAutoStretchVertical(true)
    hint:SetDark(true)
    hint:SetText("Quem fica parado (sem teclas, mouse ou chat) pelo tempo definido vai para o menu e " ..
        "não entra no sorteio de killers. Se um killer ficar AFK na preparação ou na rodada, os runners " ..
        "vivos votam em quem assume (F6 quero / F7 não quero).")

    for _, g in ipairs(AFK.Groups) do
        local head = SherlockHNS.UI.Create("DLabel", pnl)
        head:Dock(TOP)
        head:DockMargin(0, 14, 0, 4)
        head:SetTall(20)
        head:SetFont("DermaDefaultBold")
        head:SetDark(true)
        head:SetText(g.title)

        for _, t in ipairs(AFK.Toggles) do
            if t.group == g.id then
                local c = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
                c:Dock(TOP)
                c:DockMargin(0, 0, 0, 6)
                c:SetText(t.label)
                c:SetDark(true)
                c:SetValue(AFK.Toggle(t.key))
                -- definido depois do SetValue para não enviar na abertura
                function c:OnChange(val) SendConfig(t.key, val and 1 or 0) end
            end
        end

        for _, s in ipairs(AFK.Settings) do
            if s.group == g.id then
                local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
                sl:Dock(TOP)
                sl:DockMargin(0, 0, 16, 4)
                sl:SetText(s.label)
                sl:SetDark(true)
                sl:SetMin(s.min)
                sl:SetMax(s.max)
                sl:SetDecimals(0)
                sl:SetValue(AFK.Num(s.key))

                sl.OnValueChanged = function(_, v)
                    timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
                        SendConfig(s.key, v)
                    end)
                end
            end
        end
    end

    -- ===== Controle manual =====
    local ACT = AFK.ACT

    local head = SherlockHNS.UI.Create("DLabel", pnl)
    head:Dock(TOP)
    head:DockMargin(0, 18, 0, 4)
    head:SetTall(20)
    head:SetFont("DermaDefaultBold")
    head:SetDark(true)
    head:SetText("Controle manual")

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(TOP)
    list:SetTall(260)
    list:SetMultiSelect(true)
    list:AddColumn("Jogador")
    list:AddColumn("Estado"):SetFixedWidth(110)
    list:AddColumn("Isento"):SetFixedWidth(60)

    local function StateText(p)
        local mode = SherlockHNS.GetMode(p)
        if mode == PMODE_PLAY then return "Jogando" end
        if p:GetNWFloat("hns_afk_at", 0) > 0 then return "AFK" end
        if mode == PMODE_SPEC then return "Espectando" end
        return "No menu"
    end

    local lines = {}
    local nextSync = 0
    function list:Think()
        if CurTime() < nextSync then return end
        nextSync = CurTime() + 0.5

        for p, line in pairs(lines) do
            if not IsValid(p) then
                self:RemoveLine(line:GetID())
                lines[p] = nil
            end
        end
        for _, p in ipairs(player.GetHumans()) do
            local line = lines[p]
            if not line then
                line = self:AddLine("", "", "")
                line.ply = p
                lines[p] = line
            end
            line:SetColumnText(1, p:Nick())
            line:SetColumnText(2, StateText(p))
            line:SetColumnText(3, p:GetNWBool("hns_afk_exempt", false) and "Sim" or "")
        end
    end

    local row = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(row)
    row:Dock(TOP)
    row:DockMargin(0, 6, 0, 0)
    row:SetTall(28)
    row:SetPaintBackground(false)

    local function Btn(text, wide, act)
        local b = SherlockHNS.UI.Create("DButton", row)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(wide)
        b:SetText(text)
        b.DoClick = function()
            for _, line in ipairs(list:GetSelected()) do
                if IsValid(line.ply) then
                    net.Start("sherlockhns_afk_admin")
                    net.WriteUInt(act, 2)
                    net.WriteEntity(line.ply)
                    net.SendToServer()
                end
            end
        end
    end

    Btn("Marcar AFK", 130, ACT.FLAG)
    Btn("Devolver à partida", 160, ACT.CLEAR)
    Btn("Alternar isenção", 150, ACT.EXEMPT)

    return pnl
end
