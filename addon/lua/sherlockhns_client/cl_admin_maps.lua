-- Aba "Mapas" do painel admin (cliente)
-- Usada por cl_admin.lua: sheet:AddSheet("Mapas", SherlockHNS.BuildMapsTab(sheet), "icon16/map.png")

local maps = {}
local list, search

local MODE_NAMES = { [0] = "Desligada", [1] = "Aleatório", [2] = "Votação" }

local function SendConfig(key, value)
    net.Start("sherlockhns_admin_config")
    net.WriteString(key)
    net.WriteFloat(value)
    net.SendToServer()
end

local function SendAction(action)
    net.Start("sherlockhns_admin_action")
    net.WriteString(action)
    net.SendToServer()
end

local function SendToggle(names, enabled)
    if #names == 0 then return end
    net.Start("sherlockhns_map_toggle")
    net.WriteBool(enabled)
    net.WriteUInt(#names, 16)
    for _, n in ipairs(names) do net.WriteString(n) end
    net.SendToServer()
end

local function SendForce(name)
    net.Start("sherlockhns_map_force")
    net.WriteString(name or "")
    net.SendToServer()
end

local function Populate()
    if not IsValid(list) then return end

    local filter = string.lower(search:GetValue() or "")
    list:Clear()

    for _, m in ipairs(maps) do
        if filter == "" or m.name:lower():find(filter, 1, true) then
            local line = list:AddLine(
                m.name,
                m.enabled and "Sim" or "Não",
                string.format("%.1f", m.plays),
                m.chance > 0 and string.format("%.0f%%", m.chance) or "-"
            )
            -- ordenação numérica nas colunas de número
            line:SetSortValue(2, m.enabled and 1 or 0)
            line:SetSortValue(3, m.plays)
            line:SetSortValue(4, m.chance)
        end
    end
end

net.Receive("sherlockhns_map_sync", function()
    maps = {}
    for i = 1, net.ReadUInt(16) do
        maps[i] = {
            name    = net.ReadString(),
            enabled = net.ReadBool(),
            plays   = net.ReadFloat(),
            chance  = net.ReadFloat(),
        }
    end
    Populate()
end)

local function Selected()
    local names = {}
    for _, line in ipairs(list:GetSelected()) do
        names[#names + 1] = line:GetColumnText(1)
    end
    return names
end

function SherlockHNS.BuildMapsTab(sheet)
    local pnl = SherlockHNS.UI.Create("DPanel", sheet)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(10, 10, 10, 10)

    -- Modo de rotação
    local row = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(row)
    row:Dock(TOP)
    row:SetTall(24)
    row:SetPaintBackground(false)

    local lbl = SherlockHNS.UI.Create("DLabel", row)
    lbl:Dock(LEFT)
    lbl:SetWide(130)
    lbl:SetDark(true)
    lbl:SetText("Modo de rotação")

    local combo = SherlockHNS.UI.Create("DComboBox", row)
    combo:Dock(LEFT)
    combo:SetWide(180)
    combo:AddChoice(MODE_NAMES[0], 0)
    combo:AddChoice(MODE_NAMES[1], 1)
    combo:AddChoice(MODE_NAMES[2], 2)
    combo:SetValue(MODE_NAMES[GetGlobalInt("sherlockhns_map_mode", 0)] or MODE_NAMES[0]) -- SetValue não dispara OnSelect
    combo.OnSelect = function(_, _, _, data) SendConfig("MapMode", data) end

    -- Chances
    local dyn = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    dyn:Dock(TOP)
    dyn:DockMargin(0, 8, 0, 8)
    dyn:SetText("Chances dinâmicas (quanto mais um mapa é jogado, mais raro fica)")
    dyn:SetDark(true)
    dyn:SetValue(GetGlobalBool("sherlockhns_map_dynamic", true))
    function dyn:OnChange(val)
        SendConfig("MapDynamic", val and 1 or 0)
    end

    -- Sliders (rodadas por mapa, quantidade de mapas na votação, tempo)
    for _, s in ipairs(SherlockHNS.MapSettings) do
        local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
        sl:Dock(TOP)
        sl:DockMargin(0, 0, 0, 4)
        sl:SetText(s.label)
        sl:SetDark(true)
        sl:SetMin(s.min)
        sl:SetMax(s.max)
        sl:SetDecimals(0)
        sl:SetValue(GetGlobalInt("sherlockhns_cfg_" .. s.key, s.default))

        -- definido depois do SetValue para não enviar na abertura
        sl.OnValueChanged = function(_, v)
            timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
                SendConfig(s.key, v)
            end)
        end
    end

    -- Busca
    search = SherlockHNS.UI.Create("DTextEntry", pnl)
    search:Dock(TOP)
    search:DockMargin(0, 8, 0, 6)
    search:SetPlaceholderText("Buscar mapa...")
    search.OnChange = Populate

    -- Botões
    local bottom = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(bottom)
    bottom:Dock(BOTTOM)
    bottom:DockMargin(0, 6, 0, 0)
    bottom:SetTall(28)
    bottom:SetPaintBackground(false)

    local function Btn(text, wide, fn)
        local b = SherlockHNS.UI.Create("DButton", bottom)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(wide)
        b:SetText(text)
        b.DoClick = fn
        return b
    end

    Btn("Ativar selecionados", 125, function() SendToggle(Selected(), true) end)
    Btn("Desativar selecionados", 135, function() SendToggle(Selected(), false) end)
    Btn("Zerar histórico", 105, function() SendAction("mapresetplays") end)

    Btn("Forçar troca agora", 125, function()
        local sel = Selected()
        if #sel > 1 then
            notification.AddLegacy("Selecione só um mapa (ou nenhum para sortear).", NOTIFY_ERROR, 4)
            return
        end

        local target = sel[1]
        Derma_Query(
            target and ("Trocar agora para " .. target .. "?") or "Trocar agora para um mapa sorteado?",
            "Forçar troca de mapa",
            "Trocar", function() SendForce(target) end,
            "Cancelar")
    end)

    local vote = Btn("", 185, function() SendAction("mapvote") end)
    local lastTxt
    function vote:Think()
        local st = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
        local txt, enabled

        if st == ROUND_MAPVOTE then
            txt, enabled = "Troca em andamento", false
        elseif st == ROUND_WAITING then
            txt, enabled = "Iniciar votação agora", true
        elseif GetGlobalBool("sherlockhns_map_queued", false) then
            txt, enabled = "Cancelar troca na fila", true
        else
            txt, enabled = "Enfileirar p/ fim da rodada", true
        end

        if txt ~= lastTxt then
            lastTxt = txt
            self:SetText(txt)
        end
        self:SetEnabled(enabled)
    end

    -- Lista
    list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(true)
    list:AddColumn("Mapa")
    list:AddColumn("Ativo"):SetFixedWidth(60)
    list:AddColumn("Jogadas"):SetFixedWidth(70)
    list:AddColumn("Chance"):SetFixedWidth(70)

    list.DoDoubleClick = function(_, _, line)
        SendToggle({ line:GetColumnText(1) }, line:GetColumnText(2) ~= "Sim")
    end

    Populate()

    net.Start("sherlockhns_map_request")
    net.SendToServer()

    return pnl
end
