local frame
local whitelist = {}
local pillHealth, juggerWeapons = {}, {}
local spawns = { killer = nil, runners = {} }
local spawnInfo

-- Última aba aberta (sobrevive ao fechar o painel e, via convar, a reiniciar o jogo)
local cvLastTab = CreateClientConVar("sherlockhns_admin_lasttab", "Partida", true, false)
local lastTab = cvLastTab:GetString()

-- ===== Envio =====
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

local function SendPills(names, enabled)
    if #names == 0 then return end
    net.Start("sherlockhns_admin_pill")
    net.WriteBool(enabled)
    net.WriteUInt(#names, 16)
    for _, n in ipairs(names) do net.WriteString(n) end
    net.SendToServer()
end

net.Receive("sherlockhns_admin_sync", function()
    whitelist = {}
    for _, name in ipairs(net.ReadTable()) do whitelist[name] = true end
    pillHealth = net.ReadTable() or {}
    juggerWeapons = net.ReadTable() or {}
    SherlockHNS.AdminJuggerWeapons = juggerWeapons
    if SherlockHNS.RefreshJuggerWeaponLists then SherlockHNS.RefreshJuggerWeaponLists() end
    if IsValid(frame) and frame.Refresh then frame:Refresh() end
    if IsValid(frame) and frame.RefreshHealth then frame:RefreshHealth() end
end)

local function SendPillHealth(name, hp)
    net.Start("sherlockhns_admin_pill_health")
    net.WriteString(name)
    net.WriteUInt(math.Clamp(math.floor(tonumber(hp) or 0), 0, 65535), 16)
    net.SendToServer()
end

net.Receive("sherlockhns_admin_spawns", function()
    spawns = net.ReadTable()
    spawns.runners = spawns.runners or {}
    if IsValid(spawnInfo) then
        spawnInfo:SetText(string.format("Killer: %s   |   Runners: %d pontos",
            spawns.killer and "definido" or "não definido", #spawns.runners))
    end
end)

-- ===== Auditoria (Kill API / Abilities API) =====
local audit   = {} -- [pill] = { k, a }
local ST_TEXT = { [0] = "-", "OK", "Não", "Parcial" }
local ST_COL  = { [0] = Color(130, 130, 130), Color(40, 150, 60), Color(200, 50, 50), Color(210, 130, 20) }

net.Receive("sherlockhns_pillaudit_sync", function()
    local n = net.ReadUInt(16)
    local list = util.JSONToTable(util.Decompress(net.ReadData(n)) or "") or {}
    audit = {}
    for _, e in ipairs(list) do audit[e.n] = { k = e.k, a = e.a } end
    if IsValid(frame) and frame.Refresh then frame:Refresh() end
end)

local function Pending(p)
    local a = audit[p.name]
    return a ~= nil and (a.k >= 2 or a.a >= 2)
end

local function AddPillLine(list, p)
    local a = audit[p.name]
    local line = list:AddLine(p.label, p.name, a and ST_TEXT[a.k] or "?", a and ST_TEXT[a.a] or "?")
    line.Columns[3]:SetTextColor(a and ST_COL[a.k] or ST_COL[0])
    line.Columns[4]:SetTextColor(a and ST_COL[a.a] or ST_COL[0])
end

hook.Add("PostDrawTranslucentRenderables", "HNS_DrawSpawns", function()
    if not IsValid(frame) or not frame:IsVisible() then return end

    local function Marker(sp, col)
        local pos = Vector(sp.x, sp.y, sp.z)
        render.DrawWireframeBox(pos, angle_zero, Vector(-16, -16, 0), Vector(16, 16, 72), col, true)
        local top = pos + Vector(0, 0, 36)
        render.DrawLine(top, top + Angle(0, sp.yaw, 0):Forward() * 40, col, true)
    end

    if spawns.killer then Marker(spawns.killer, Color(200, 80, 255)) end
    for _, sp in ipairs(spawns.runners or {}) do Marker(sp, Color(80, 160, 255)) end

    if GetGlobalBool("hns_menucam_set", false) then
        local pos, ang = GetGlobalVector("hns_menucam_pos"), GetGlobalAngle("hns_menucam_ang")
        render.DrawWireframeBox(pos, ang, Vector(-8, -6, -6), Vector(8, 6, 6), Color(255, 200, 40), true)
        render.DrawLine(pos, pos + ang:Forward() * 48, Color(255, 200, 40), true)
    end
end)

hook.Add("HUDPaint", "HNS_DrawSpawnLabels", function()
    if not IsValid(frame) or not frame:IsVisible() then return end

    local function Label(sp, text, col)
        local s = Vector(sp.x, sp.y, sp.z + 80):ToScreen()
        if s.visible then
            draw.SimpleTextOutlined(text, "DermaDefaultBold", s.x, s.y, col,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        end
    end

    if spawns.killer then Label(spawns.killer, "KILLER", Color(200, 80, 255)) end
    for i, sp in ipairs(spawns.runners or {}) do
        Label(sp, "Runner #" .. i, Color(80, 160, 255))
    end
end)

-- ===== Dados =====
local function GetAllPills()
    local out = {}
    if not (pk_pills and pk_pills.Forms) then return out end

    for name, t in pairs(pk_pills.Forms) do
        if t.printName then
            out[#out + 1] = { name = name, label = tostring(t.printName) }
        end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

local function SelectedNames(list)
    local names = {}
    for _, line in ipairs(list:GetSelected()) do
        names[#names + 1] = line:GetColumnText(2)
    end
    return names
end

-- ===== Aba: Partida =====
local function BuildMatchTab(sheet)
    local pnl = SherlockHNS.UI.Form(sheet)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    local status = SherlockHNS.UI.Create("DLabel", pnl)
    status:Dock(TOP)
    status:SetTall(24)
    status:SetFont("DermaDefaultBold")
    status:SetDark(true)
    function status:Think()
        local state = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
        local endAt = GetGlobalFloat("sherlockhns_state_end", 0)
        local txt = "Estado: " .. (SherlockHNS.StateNames[state] or "?")
        if endAt > 0 then
            txt = txt .. " (" .. math.max(0, math.ceil(endAt - CurTime())) .. "s)"
        end
        self:SetText(txt)
    end

    local auto = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    auto:Dock(TOP)
    auto:DockMargin(0, 8, 0, 8)
    auto:SetText("Partida automática")
    auto:SetDark(true)
    auto:SetValue(GetGlobalBool("sherlockhns_auto", true))
    function auto:OnChange(val)
        SendConfig("AutoMatch", val and 1 or 0)
    end

    local sep = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    sep:Dock(TOP)
    sep:DockMargin(0, 0, 0, 8)
    sep:SetText("Separar chat (vivos / mortos / global só admin)")
    sep:SetDark(true)
    sep:SetValue(GetGlobalBool("sherlockhns_chat_sep", true))
    function sep:OnChange(val)
        SendConfig("ChatSeparation", val and 1 or 0)
    end

    local siteAll = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    siteAll:Dock(TOP)
    siteAll:DockMargin(0, 0, 0, 8)
    siteAll:SetText("Chat do site visível para todos (mesmo com a separação ligada)")
    siteAll:SetDark(true)
    siteAll:SetValue(GetGlobalBool("sherlockhns_sitechat_all", false))
    function siteAll:OnChange(val) SendConfig("SiteChatToAll", val and 1 or 0) end

    local ff = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    ff:Dock(TOP)
    ff:DockMargin(0, 0, 0, 8)
    ff:SetText("Friendly fire entre jogadores do mesmo time")
    ff:SetDark(true)
    ff:SetValue(GetGlobalBool("sherlockhns_friendly_fire", false))
    function ff:OnChange(val) SendConfig("FriendlyFire", val and 1 or 0) end

    local occ = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    occ:Dock(TOP)
    occ:DockMargin(0, 0, 0, 8)
    occ:SetText("Voz: oclusão por paredes (trace por par)")
    occ:SetDark(true)
    occ:SetValue(GetGlobalBool("sherlockhns_voice_occ", false))
    function occ:OnChange(val)
        SendConfig("VoiceOcclusion", val and 1 or 0)
    end

    local dyn = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    dyn:Dock(TOP)
    dyn:DockMargin(0, 0, 0, 8)
    dyn:SetText("Killers dinâmicos (1 a cada 10 runners)")
    dyn:SetDark(true)
    dyn:SetValue(GetGlobalBool("sherlockhns_dynkillers", true))

    local ks = SherlockHNS.KillerCountSetting
    local count = SherlockHNS.UI.Create("DNumSlider", pnl)
    count:Dock(TOP)
    count:DockMargin(0, 0, 0, 8)
    count:SetText(ks.label)
    count:SetDark(true)
    count:SetMin(ks.min)
    count:SetMax(ks.max)
    count:SetDecimals(0)
    count:SetValue(GetGlobalInt("sherlockhns_cfg_KillerCount", ks.default))
    count:SetEnabled(not dyn:GetChecked())

    count.OnValueChanged = function(_, v)
        timer.Create("sherlockhns_slider_KillerCount", 0.4, 1, function()
            SendConfig("KillerCount", v)
        end)
    end

    function dyn:OnChange(val)
        count:SetEnabled(not val) -- slider só vale no modo fixo
        SendConfig("DynamicKillers", val and 1 or 0)
    end

    for _, s in ipairs(SherlockHNS.TimeSettings) do
        local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
        sl:Dock(TOP)
        sl:DockMargin(0, 0, 0, 4)
        sl:SetText(s.label)
        sl:SetDark(true)
        sl:SetMin(s.min)
        sl:SetMax(s.max)
        sl:SetDecimals(0)
        sl:SetValue(GetGlobalInt("sherlockhns_cfg_" .. s.key, s.default))

        -- definido depois do SetValue para não disparar envio na abertura
        sl.OnValueChanged = function(_, v)
            timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
                SendConfig(s.key, v)
            end)
        end
    end

    for _, s in ipairs(SherlockHNS.VoiceSettings) do
        local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
        sl:Dock(TOP)
        sl:DockMargin(0, 0, 0, 4)
        sl:SetText(s.label)
        sl:SetDark(true)
        sl:SetMin(s.min)
        sl:SetMax(s.max)
        sl:SetDecimals(0)
        sl:SetValue(GetGlobalInt("sherlockhns_cfg_" .. s.key, s.default))
        sl.OnValueChanged = function(_, v)
            timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
                SendConfig(s.key, v)
            end)
        end
    end

    local FF = SherlockHNS.ForceField
    for _, t in ipairs(FF.Toggles) do
        local c = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
        c:Dock(TOP)
        c:DockMargin(0, 8, 0, 8)
        c:SetText(t.label)
        c:SetDark(true)
        c:SetValue(FF.Toggle(t.key))
        function c:OnChange(val) SendConfig(t.key, val and 1 or 0) end
    end

    for _, s in ipairs(FF.Settings) do
        local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
        sl:Dock(TOP)
        sl:DockMargin(0, 0, 0, 4)
        sl:SetText(s.label)
        sl:SetDark(true)
        sl:SetMin(s.min)
        sl:SetMax(s.max)
        sl:SetDecimals(0)
        sl:SetValue(FF.Num(s.key))
        sl.OnValueChanged = function(_, v)
            timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function() SendConfig(s.key, v) end)
        end
    end

    local CD = SherlockHNS.Cooldown
    for _, t in ipairs(CD.Toggles) do
        local c = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
        c:Dock(TOP)
        c:DockMargin(0, 8, 0, 8)
        c:SetText(t.label)
        c:SetDark(true)
        c:SetValue(CD.Toggle(t.key))
        function c:OnChange(val) SendConfig(t.key, val and 1 or 0) end
    end

    for _, s in ipairs(CD.Settings) do
        local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
        sl:Dock(TOP)
        sl:DockMargin(0, 0, 0, 4)
        sl:SetText(s.label)
        sl:SetDark(true)
        sl:SetMin(s.min)
        sl:SetMax(s.max)
        sl:SetDecimals(0)
        sl:SetValue(CD.Num(s.key))
        sl.OnValueChanged = function(_, v)
            timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function() SendConfig(s.key, v) end)
        end
    end

    local row = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(row)
    row:Dock(TOP)
    row:DockMargin(0, 10, 0, 0)
    row:SetTall(30)
    row:SetPaintBackground(false)

    local function Btn(text, action)
        local b = SherlockHNS.UI.Create("DButton", row)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(160)
        b:SetText(text)
        b.DoClick = function() SendAction(action) end
    end

    Btn("Iniciar rodada", "start")
    Btn("Iniciar sem killer", "startnokiller")
    Btn("Cancelar rodada", "cancel")
    Btn("Resetar último killer", "clearlast")

    return pnl
end

-- ===== Aba: Pills =====
local function MakeList(parent)
    local l = SherlockHNS.UI.Create("DListView", parent)
    l:SetMultiSelect(true)
    l:AddColumn("Pill")
    l:AddColumn("ID")
    l:AddColumn("Kill"):SetFixedWidth(52)
    l:AddColumn("Abil."):SetFixedWidth(52)
    return l
end

local function BuildPillsTab(sheet, owner)
    local pnl = SherlockHNS.UI.Create("DPanel", sheet)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local search = SherlockHNS.UI.Create("DTextEntry", pnl)
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, 6)
    search:SetPlaceholderText("Buscar pill...")

    local only = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    only:Dock(TOP)
    only:DockMargin(0, 0, 0, 6)
    only:SetText("Só pills não convertidas (Kill API / Abilities API)")
    only:SetDark(true)

    local info = SherlockHNS.UI.Create("DLabel", pnl)
    info:Dock(TOP)
    info:DockMargin(0, 0, 0, 6)
    info:SetTall(18)
    info:SetDark(true)

    local bottom = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(bottom)
    bottom:Dock(BOTTOM)
    bottom:DockMargin(0, 6, 0, 0)
    bottom:SetTall(28)
    bottom:SetPaintBackground(false)

    local lists = SherlockHNS.UI.Create("DPanel", pnl)
    lists:Dock(FILL)
    lists:SetPaintBackground(false)

    local left = MakeList(lists)
    left:Dock(LEFT)
    left:SetWide(440)
    SherlockHNS.UI.Split(lists, left, 620, 700)
    left:DockMargin(0, 0, 6, 0)

    local right = MakeList(lists)
    right:Dock(FILL)

    left.DoDoubleClick  = function(_, _, line) SendPills({ line:GetColumnText(2) }, true) end
    right.DoDoubleClick = function(_, _, line) SendPills({ line:GetColumnText(2) }, false) end

    local function Btn(text, fn)
        local b = SherlockHNS.UI.Create("DButton", bottom)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(150)
        b:SetText(text)
        b.DoClick = fn
    end

    Btn("Adicionar ▶", function() SendPills(SelectedNames(left), true) end)
    Btn("◀ Remover", function() SendPills(SelectedNames(right), false) end)
    Btn("Limpar tudo", function() SendAction("clearpills") end)

    local allPills = GetAllPills()
    local killOk, killPend, abOk, abPend = 0, 0, 0, 0

    function info:Think()
        local ghost = GetGlobalBool("sherlockhns_specghost_on", false)
        self:SetText(("Whitelist - Kill API: %d ok / %d pendentes   Abilities: %d ok / %d pendentes   |   Espectador legado: %s")
            :format(killOk, killPend, abOk, abPend, ghost and "ATIVO" or "inativo"))
    end

    function owner:Refresh()
        local filter = string.lower(search:GetValue() or "")
        local pendingOnly = only:GetChecked()
        left:Clear()
        right:Clear()
        killOk, killPend, abOk, abPend = 0, 0, 0, 0

        for _, p in ipairs(allPills) do
            local a = audit[p.name]
            if whitelist[p.name] and a then
                if a.k == 1 then killOk = killOk + 1 elseif a.k >= 2 then killPend = killPend + 1 end
                if a.a == 1 then abOk = abOk + 1 elseif a.a >= 2 then abPend = abPend + 1 end
            end

            if not pendingOnly or Pending(p) then
                if whitelist[p.name] then
                    if filter == "" or p.label:lower():find(filter, 1, true)
                        or p.name:lower():find(filter, 1, true) then
                        AddPillLine(right, p)
                    end
                elseif filter == "" or p.label:lower():find(filter, 1, true)
                    or p.name:lower():find(filter, 1, true) then
                    AddPillLine(left, p)
                end
            end
        end
    end

    search.OnChange = function() owner:Refresh() end
    only.OnChange = function() owner:Refresh() end

    return pnl
end

local function BuildPillsRoot(sheet, owner)
    local pnl = SherlockHNS.UI.Create("DPanel", sheet)
    pnl:SetPaintBackground(false)

    local inner = SherlockHNS.UI.Create("DPropertySheet", pnl)
    inner:Dock(FILL)
    inner:AddSheet("Whitelist", BuildPillsTab(inner, owner), "icon16/pill.png")
    inner:AddSheet("Velocidades", SherlockHNS.BuildSpeedsTab(inner), "icon16/lightning.png")
    inner:AddSheet("Compatibilização", SherlockHNS.BuildSpeedNormTab(inner), "icon16/arrow_join.png")

    local hpPanel = SherlockHNS.UI.Create("DPanel", inner)
    hpPanel:SetPaintBackground(false)
    hpPanel:DockPadding(8, 8, 8, 8)
    local hint = SherlockHNS.UI.Create("DLabel", hpPanel)
    hint:Dock(TOP)
    hint:SetTall(24)
    hint:SetDark(true)
    hint:SetText("Selecione uma pill e defina a vida máxima. Use 0 para voltar ao valor original do pack.")
    local hpList = SherlockHNS.UI.Create("DListView", hpPanel)
    hpList:Dock(FILL)
    hpList:AddColumn("Pill")
    hpList:AddColumn("Vida configurada"):SetFixedWidth(120)
    for _, pill in ipairs(GetAllPills()) do
        local line = hpList:AddLine(pill.label, pillHealth[pill.name] or "padrão")
        line.pillName = pill.name
    end
    function owner:RefreshHealth()
        hpList:Clear()
        for _, pill in ipairs(GetAllPills()) do
            local line = hpList:AddLine(pill.label, pillHealth[pill.name] or "padrão")
            line.pillName = pill.name
        end
    end

    local hpRow = SherlockHNS.UI.Create("DPanel", hpPanel)
    SherlockHNS.UI.Flow(hpRow)
    hpRow:Dock(BOTTOM)
    hpRow:SetTall(30)
    hpRow:SetPaintBackground(false)
    local hpEntry = SherlockHNS.UI.Create("DTextEntry", hpRow)
    hpEntry:Dock(LEFT)
    hpEntry:SetWide(120)
    hpEntry:SetPlaceholderText("Vida (0 = padrão)")
    hpList.OnRowSelected = function(_, _, line)
        hpEntry:SetText(tostring(pillHealth[line.pillName] or 0))
    end
    local hpSave = SherlockHNS.UI.Create("DButton", hpRow)
    hpSave:Dock(LEFT)
    hpSave:SetWide(150)
    hpSave:SetText("Aplicar vida")
    hpSave.DoClick = function()
        local line = hpList:GetSelectedLine()
        local selected = line and hpList:GetLine(line)
        if selected then SendPillHealth(selected.pillName, hpEntry:GetValue()) end
    end
    inner:AddSheet("Vida das pills", hpPanel, "icon16/heart.png")

    return pnl
end

local function BuildSpawnsTab(sheet)
    local pnl = SherlockHNS.UI.Form(sheet)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    spawnInfo = SherlockHNS.UI.Create("DLabel", pnl)
    spawnInfo:Dock(TOP)
    spawnInfo:SetTall(24)
    spawnInfo:SetFont("DermaDefaultBold")
    spawnInfo:SetDark(true)
    spawnInfo:SetText("Mapa: " .. game.GetMap())

    local hint = SherlockHNS.UI.Create("DLabel", pnl)
    hint:Dock(TOP)
    hint:SetTall(36)
    hint:SetWrap(true)
    hint:SetDark(true)
    hint:SetText("O ponto é salvo onde você está e na direção em que olha. " ..
        "Fica gravado para este mapa.")

    local function Btn(text, action, wide)
        local b = SherlockHNS.UI.Create("DButton", pnl)
        b:Dock(TOP)
        b:DockMargin(0, 6, 0, 0)
        b:SetTall(30)
        b:SetText(text)
        b.DoClick = function() SendAction(action) end
        return b
    end

    Btn("Definir spawn do KILLER aqui", "setkiller")
    Btn("Ir ao spawn do killer", "tpkiller")
    Btn("Limpar spawn do killer", "clearkillerspawn")
    Btn("Adicionar spawn de RUNNER aqui", "addrunner")
    Btn("Remover último spawn de runner", "delrunner")
    Btn("Limpar todos os spawns de runners", "clearrunners")
    Btn("Definir CÂMERA do menu aqui", "setmenucam")
    Btn("Ir à câmera do menu", "tpmenucam")
    Btn("Limpar câmera do menu", "clearmenucam")

    return pnl
end

-- ===== Janela (abre com Q, estilo spawn menu) =====
local function ClosePanel()
    SherlockHNS.Creation.Detach()
    if IsValid(frame) then frame:Remove() end
    frame = nil
end

local function OpenPanel()
    ClosePanel()

    frame = SherlockHNS.UI.Create("DFrame")
    frame:SetTitle("Sherlock HnS — Painel de teste")
    SherlockHNS.UI.Window(frame, 1500, 900, 80)
    frame:Center()
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(false) -- só liga quando um campo de texto ganha foco
    frame.hang = false

    local sheet = SherlockHNS.UI.Create("DPropertySheet", frame)
    sheet:Dock(FILL)

    local tabs = {}
    local function Add(name, panel, icon)
        local item = sheet:AddSheet(name, panel, icon)
        tabs[name] = item.Tab
    end

    Add("Partida", BuildMatchTab(sheet), "icon16/clock.png")
    Add("Pills (whitelist)", BuildPillsRoot(sheet, frame), "icon16/pill.png")
    Add("Spawns", BuildSpawnsTab(sheet), "icon16/flag_blue.png")
    Add("Mapas", SherlockHNS.BuildMapsTab(sheet), "icon16/map.png")
    Add("Jogadores", SherlockHNS.BuildPlayersTab(sheet), "icon16/user.png")
    Add("Moderação", SherlockHNS.BuildModerationTab(sheet), "icon16/shield.png")
    Add("Mutações", SherlockHNS.BuildMutationsTab(sheet), "icon16/lightning.png")
    Add("Tags", SherlockHNS.BuildTagsTab(sheet), "icon16/tag_blue.png")
    Add("Partner", SherlockHNS.BuildPartnerTab(sheet), "icon16/star.png")
    Add("Killers", SherlockHNS.BuildKillersTab(sheet), "icon16/user_red.png")
    Add("Enquete", SherlockHNS.BuildPollTab(sheet), "icon16/chart_bar.png")
    Add("Anúncio", SherlockHNS.BuildAnnounceTab(sheet), "icon16/bell.png")
    Add("AFK", SherlockHNS.BuildAfkTab(sheet), "icon16/user_delete.png")
    for _, def in ipairs(SherlockHNS.Creation.Tabs) do
        Add(def.name, SherlockHNS.BuildCreationTab(sheet, def), def.icon)
    end

    -- restaura a última aba usada
    if tabs[lastTab] then
        sheet:SetActiveTab(tabs[lastTab])
    end

    -- guarda sempre que trocar de aba (definido depois do restauro para não sobrescrever à toa)
    sheet.OnActiveTabChanged = function(_, _, newTab)
        for name, tab in pairs(tabs) do
            if tab == newTab then
                lastTab = name
                RunConsoleCommand("sherlockhns_admin_lasttab", name)
                break
            end
        end
    end

    net.Start("sherlockhns_admin_request")
    net.SendToServer()
end

-- Q pressionado
function GM:OnSpawnMenuOpen()
    local lp = LocalPlayer()
    if not (IsValid(lp) and lp:IsAdmin()) then return end

    -- já aberto (travado para digitar): Q de novo fecha
    if IsValid(frame) then
        ClosePanel()
        return
    end

    OpenPanel()
end

-- Q solto
function GM:OnSpawnMenuClose()
    if not IsValid(frame) then return end

    -- se está travado por causa do campo de texto, só destrava
    if frame.hang then
        frame.hang = false
        return
    end

    ClosePanel()
end

-- Campo de texto precisa de teclado: libera e mantém o painel aberto
hook.Add("OnTextEntryGetFocus", "HNS_AdminKeyFocusOn", function(pnl)
    if IsValid(frame) and IsValid(pnl) and pnl:HasParent(frame) then
        frame:SetKeyboardInputEnabled(true)
        frame.hang = true
    end
end)

hook.Add("OnTextEntryLoseFocus", "HNS_AdminKeyFocusOff", function(pnl)
    if IsValid(frame) and IsValid(pnl) and pnl:HasParent(frame) then
        frame:SetKeyboardInputEnabled(false)
    end
end)
