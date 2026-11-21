-- Aba "Jogadores" do painel admin (cliente)
-- Usada por cl_admin.lua: sheet:AddSheet("Jogadores", SherlockHNS.BuildPlayersTab(sheet), "icon16/user.png")

local ACT_REVIVE, ACT_KILL, ACT_JAIL, ACT_UNJAIL, ACT_GOTO, ACT_BRING, ACT_SETKILLER, ACT_UNSETKILLER = 1, 2, 3, 4, 5, 6,
    7, 8

local function Send(act, target, secs)
    net.Start("sherlockhns_players_action")
    net.WriteUInt(act, 4)
    net.WriteEntity(target)
    net.WriteUInt(secs or 0, 16)
    net.SendToServer()
end

local function StateText(ply)
    local txt = ply:Alive() and "Vivo" or "Morto"
    if ply:GetNWBool("hns_jailed", false) then txt = txt .. " (jail)" end
    return txt
end

local function TeamText(ply)
    if SherlockHNS.IsInMenu(ply) then return "Menu" end
    return team.GetName(ply:Team())
end

function SherlockHNS.BuildPlayersTab(sheet)
    local pnl = SherlockHNS.UI.Create("DPanel", sheet)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    -- Linha de botões (mais embaixo)
    local bottom = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(bottom)
    bottom:Dock(BOTTOM)
    bottom:DockMargin(0, 6, 0, 0)
    bottom:SetTall(28)
    bottom:SetPaintBackground(false)

    -- Duração do jail
    local secs = SherlockHNS.UI.Create("DNumSlider", pnl)
    secs:Dock(BOTTOM)
    secs:DockMargin(0, 6, 0, 0)
    secs:SetText("Duração do jail (s) - 0 = permanente")
    secs:SetDark(true)
    secs:SetMin(0)
    secs:SetMax(600)
    secs:SetDecimals(0)
    secs:SetValue(30)

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(true)
    list:AddColumn("Jogador")
    list:AddColumn("Time"):SetFixedWidth(110)
    list:AddColumn("Estado"):SetFixedWidth(110)

    local lines = {}

    local function Sync()
        for p, line in pairs(lines) do
            if not IsValid(p) then
                list:RemoveLine(line:GetID())
                lines[p] = nil
            end
        end

        for _, p in ipairs(player.GetAll()) do
            local line = lines[p]
            if not line then
                line = list:AddLine("", "", "")
                line.ply = p
                lines[p] = line
            end
            line:SetColumnText(1, p:Nick())
            line:SetColumnText(2, TeamText(p))
            line:SetColumnText(3, StateText(p))
        end
    end

    -- atualiza no lugar para manter a seleção
    local nextSync = 0
    function list:Think()
        if CurTime() < nextSync then return end
        nextSync = CurTime() + 0.5
        Sync()
    end

    Sync()

    local function Selected()
        local out = {}
        for _, line in ipairs(list:GetSelected()) do
            if IsValid(line.ply) then out[#out + 1] = line.ply end
        end
        return out
    end

    local function Btn(text, fn)
        local b = SherlockHNS.UI.Create("DButton", bottom)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(110)
        b:SetText(text)
        b.DoClick = function()
            for _, p in ipairs(Selected()) do fn(p) end
        end
    end

    Btn("Reviver", function(p) Send(ACT_REVIVE, p) end)
    Btn("Matar", function(p) Send(ACT_KILL, p) end)
    Btn("Jail", function(p) Send(ACT_JAIL, p, math.floor(secs:GetValue())) end)
    Btn("Unjail", function(p) Send(ACT_UNJAIL, p) end)
    Btn("Ir a", function(p) Send(ACT_GOTO, p) end)
    Btn("Trazer", function(p) Send(ACT_BRING, p) end)
    Btn("Tornar killer", function(p) Send(ACT_SETKILLER, p) end)
    Btn("Remover killer", function(p) Send(ACT_UNSETKILLER, p) end)

    return pnl
end
