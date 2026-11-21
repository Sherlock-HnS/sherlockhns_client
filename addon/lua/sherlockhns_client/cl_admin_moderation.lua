-- Aba "Moderação" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Moderação", SherlockHNS.BuildModerationTab(sheet), "icon16/shield.png")
-- Sub-abas: Jogadores (online e offline: aplicar e ver histórico) e Bans ativos.

local MOD  = SherlockHNS.Mod
local K    = MOD.KIND
local ACT  = MOD.ACT
local SYNC = MOD.SYNC

local data       = { players = {}, history = {}, historyId = nil, bans = {} }
local refreshers = {}

local function Send(act, fn)
    net.Start("sherlockhns_mod_action")
    net.WriteUInt(act, 3)
    if fn then fn() end
    net.SendToServer()
end

net.Receive("sherlockhns_mod_sync", function()
    local what   = net.ReadUInt(2)
    local target = net.ReadString()
    local n      = net.ReadUInt(16)
    local list   = util.JSONToTable(util.Decompress(net.ReadData(n)) or "") or {}

    if what == SYNC.PLAYERS then
        data.players = list
    elseif what == SYNC.HISTORY then
        data.history, data.historyId = list, target
    elseif what == SYNC.BANS then
        data.bans = list
    end

    for _, fn in pairs(refreshers) do fn(what) end
end)

local DURATIONS = {
    { "15 minutos", 15 }, { "1 hora", 60 }, { "6 horas", 360 }, { "1 dia", 1440 },
    { "3 dias", 4320 }, { "7 dias", 10080 }, { "30 dias", 43200 }, { "Permanente", 0 },
}

local STATUS = { [0] = "", "Revogado", "Expirado" }

local function When(t) return t and t > 0 and os.date("%d/%m/%Y %H:%M", t) or "-" end

local function Expires(x)
    if not x or x == 0 then return "Permanente" end
    if x <= os.time() then return "Expirado" end
    return MOD.FormatDuration(x - os.time())
end

local function Btn(parent, text, wide, fn)
    local b = SherlockHNS.UI.Create("DButton", parent)
    b:Dock(LEFT)
    b:DockMargin(0, 0, 6, 0)
    b:SetWide(wide)
    b:SetText(text)
    b.DoClick = fn
    return b
end

local function Row(parent, dock)
    local r = SherlockHNS.UI.Create("DPanel", parent)
    SherlockHNS.UI.Flow(r)
    r:Dock(dock or BOTTOM)
    r:DockMargin(0, 6, 0, 0)
    r:SetTall(28)
    r:SetPaintBackground(false)
    return r
end

local function OpenEvidence(url)
    if isstring(url) and url ~= "" then
        gui.OpenURL(url)
    else
        notification.AddLegacy("Esse registro não tem prova.", NOTIFY_HINT, 3)
    end
end

-- ============================================================
-- Sub-aba: Jogadores
-- ============================================================
local function BuildPlayers(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local selected, selectedName -- SteamID64 e nome do alvo

    -- ===== Esquerda: busca + lista =====
    local left = SherlockHNS.UI.Create("DPanel", pnl)
    left:Dock(LEFT)
    left:SetWide(340)
    left:SetPaintBackground(false)
    SherlockHNS.UI.Split(pnl, left, 340, 900)
    left:DockMargin(0, 0, 6, 0)

    local search = SherlockHNS.UI.Create("DTextEntry", left)
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, 4)
    search:SetPlaceholderText("Buscar por nick ou SteamID64 (online e offline)")

    local list = SherlockHNS.UI.Create("DListView", left)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("Jogador")
    list:AddColumn("Estado"):SetFixedWidth(60)
    list:AddColumn("Pun."):SetFixedWidth(55)

    -- ===== Direita =====
    local right = SherlockHNS.UI.Create("DPanel", pnl)
    right:Dock(FILL)
    right:SetPaintBackground(false)

    -- histórico (de baixo para cima)
    local histBtns = Row(right)

    local title = SherlockHNS.UI.Create("DLabel", right)
    title:Dock(TOP)
    title:SetTall(22)
    title:SetFont("DermaDefaultBold")
    title:SetText("Selecione um jogador")

    local reason = SherlockHNS.UI.Create("DTextEntry", right)
    reason:Dock(TOP)
    reason:DockMargin(0, 4, 0, 0)
    reason:SetPlaceholderText("Motivo (obrigatório)")
    reason:SetMaximumCharCount(MOD.MaxReason)

    local evidence = SherlockHNS.UI.Create("DTextEntry", right)
    evidence:Dock(TOP)
    evidence:DockMargin(0, 4, 0, 0)
    evidence:SetPlaceholderText("Prova: link da mensagem/canal do Discord (opcional)")
    evidence:SetMaximumCharCount(MOD.MaxEvidence)

    local opts = Row(right, TOP)
    local duration = SherlockHNS.UI.Create("DComboBox", opts)
    duration:Dock(LEFT)
    duration:SetWide(150)
    duration:DockMargin(0, 0, 8, 0)
    for _, d in ipairs(DURATIONS) do duration:AddChoice(d[1], d[2], d[2] == 1440) end

    local ipBan = SherlockHNS.UI.Create("DCheckBoxLabel", opts)
    ipBan:Dock(LEFT)
    ipBan:SetWide(330)
    ipBan:SetText("Banir também o IP (superadmin; pode atingir inocentes)")
    ipBan:SetDark(true)
    ipBan:SetEnabled(LocalPlayer():IsSuperAdmin())

    local actions = Row(right, TOP)

    local hist = SherlockHNS.UI.Create("DListView", right)
    hist:Dock(FILL)
    hist:DockMargin(0, 6, 0, 0)
    hist:SetMultiSelect(false)
    hist:AddColumn("#"):SetFixedWidth(40)
    hist:AddColumn("Tipo"):SetFixedWidth(50)
    hist:AddColumn("Data"):SetFixedWidth(110)
    hist:AddColumn("Admin"):SetFixedWidth(100)
    hist:AddColumn("Motivo")
    hist:AddColumn("Duração"):SetFixedWidth(85)
    hist:AddColumn("Status"):SetFixedWidth(70)
    hist:AddColumn("Prova"):SetFixedWidth(40)

    -- ===== Ações =====
    local function Apply(kind)
        if not selected then
            notification.AddLegacy("Selecione um jogador.", NOTIFY_ERROR, 3)
            return
        end

        local why = string.Trim(reason:GetValue())
        if utf8.len(why) == nil or utf8.len(why) < 3 then
            notification.AddLegacy("Informe o motivo.", NOTIFY_ERROR, 3)
            return
        end

        local ev = string.Trim(evidence:GetValue())
        local okEv, errEv = MOD.ValidEvidence(ev)
        if not okEv then
            notification.AddLegacy(errEv, NOTIFY_ERROR, 4)
            return
        end

        local _, minutes = duration:GetSelected()
        minutes = kind == K.BAN and (minutes or 0) or 0
        local ip = kind == K.BAN and ipBan:GetChecked()
        local id = selected

        local function Go()
            Send(ACT.APPLY, function()
                net.WriteUInt(kind, 3)
                net.WriteString(id)
                net.WriteString(why)
                net.WriteString(ev)
                net.WriteUInt(minutes, 20)
                net.WriteBool(ip)
            end)
            reason:SetValue("")
            evidence:SetValue("")
            timer.Simple(0.5, function() Send(ACT.SEARCH, function() net.WriteString(search:GetValue()) end) end)
        end

        if kind == K.BAN or kind == K.KICK then
            local txt = kind == K.BAN and ("Banir " .. selectedName .. (minutes == 0 and " PERMANENTEMENTE?" or "?"))
                or ("Kickar " .. selectedName .. "?")
            Derma_Query(txt, "Confirmar", "Confirmar", Go, "Cancelar")
        else
            Go()
        end
    end

    Btn(actions, "Warn", 90, function() Apply(K.WARN) end)
    Btn(actions, "Nota", 90, function() Apply(K.NOTE) end)
    Btn(actions, "Kick", 90, function() Apply(K.KICK) end)
    Btn(actions, "Banir", 90, function() Apply(K.BAN) end)

    local function SelectedRecord()
        local line = hist:GetSelected()[1]
        return line and line.rec
    end

    Btn(histBtns, "Abrir prova", 110, function()
        local r = SelectedRecord()
        if r then OpenEvidence(r.e) end
    end)
    Btn(histBtns, "Revogar / Desbanir", 140, function()
        local r = SelectedRecord()
        if not r then return end
        if r.s ~= 0 then
            notification.AddLegacy("Esse registro já não está ativo.", NOTIFY_HINT, 3)
            return
        end
        Derma_Query("Revogar o registro #" .. r.i .. "?", "Confirmar", "Revogar", function()
            Send(ACT.REVOKE, function() net.WriteUInt(r.i, 32) end)
        end, "Cancelar")
    end)

    -- ===== Preenchimento =====
    local function FillPlayers()
        if not IsValid(list) then return end

        list:Clear()
        for _, p in ipairs(data.players) do
            local mark = p.banned and "BAN" or (p.warns > 0 and (p.warns .. "w") or "")
            local line = list:AddLine(p.name, p.online and "Online" or "Offline", mark)
            line.id, line.pname = p.id, p.name
            if p.id == selected then list:SelectItem(line) end
        end
    end

    local function FillHistory()
        if not IsValid(hist) then return end

        hist:Clear()
        if data.historyId ~= selected then return end

        for _, r in ipairs(data.history) do
            local dur = r.k == K.BAN and ((r.ip and "[IP] " or "") .. Expires(r.x)) or ""
            local line = hist:AddLine(r.i, MOD.KindName[r.k] or "?", When(r.c), r.a, r.r, dur,
                r.v and ("Rev. por " .. r.v) or STATUS[r.s] or "", (r.e and r.e ~= "") and "Sim" or "")
            line.rec = r
        end
    end

    list.OnRowSelected = function(_, _, line)
        if selected == line.id then return end
        selected, selectedName = line.id, line.pname
        title:SetText(selectedName .. "  (" .. selected .. ")")
        data.history = {}
        FillHistory()
        Send(ACT.HISTORY, function() net.WriteString(selected) end)
    end

    hist.DoDoubleClick = function(_, _, line) OpenEvidence(line.rec and line.rec.e) end

    local function Query() Send(ACT.SEARCH, function() net.WriteString(search:GetValue()) end) end

    search.OnChange = function()
        timer.Create("sherlockhns_mod_search", 0.35, 1, function()
            if IsValid(search) then Query() end
        end)
    end

    refreshers.players = function(what)
        if what == SYNC.PLAYERS then FillPlayers() elseif what == SYNC.HISTORY then FillHistory() end
    end

    -- atualiza enquanto a aba está visível (online/offline muda)
    local nextPoll = 0
    function pnl:Think()
        if CurTime() < nextPoll then return end
        nextPoll = CurTime() + 8
        Query()
    end

    Query()
    return pnl
end

-- ============================================================
-- Sub-aba: Bans ativos
-- ============================================================
local function BuildBans(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local btns = Row(pnl)

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("#"):SetFixedWidth(40)
    list:AddColumn("Jogador")
    list:AddColumn("SteamID64"):SetFixedWidth(135)
    list:AddColumn("Admin"):SetFixedWidth(100)
    list:AddColumn("Motivo")
    list:AddColumn("Expira"):SetFixedWidth(95)
    list:AddColumn("IP"):SetFixedWidth(35)
    list:AddColumn("Prova"):SetFixedWidth(40)

    local function Selected()
        local line = list:GetSelected()[1]
        return line and line.rec
    end

    Btn(btns, "Atualizar", 100, function() Send(ACT.BANS) end)
    Btn(btns, "Abrir prova", 110, function()
        local r = Selected()
        if r then OpenEvidence(r.e) end
    end)
    Btn(btns, "Desbanir", 110, function()
        local r = Selected()
        if not r then return end
        Derma_Query("Desbanir " .. r.n .. "?", "Confirmar", "Desbanir", function()
            Send(ACT.REVOKE, function() net.WriteUInt(r.i, 32) end)
        end, "Cancelar")
    end)

    list.DoDoubleClick = function(_, _, line) OpenEvidence(line.rec and line.rec.e) end

    refreshers.bans = function(what)
        if what ~= SYNC.BANS or not IsValid(list) then return end

        local keep = Selected() and Selected().i
        list:Clear()
        for _, r in ipairs(data.bans) do
            local line = list:AddLine(r.i, r.n, r.t, r.a, r.r, Expires(r.x), r.ip and "Sim" or "",
                (r.e and r.e ~= "") and "Sim" or "")
            line.rec = r
            if r.i == keep then list:SelectItem(line) end
        end
    end

    local nextPoll = 0
    function pnl:Think()
        if CurTime() < nextPoll then return end
        nextPoll = CurTime() + 8
        Send(ACT.BANS)
    end

    Send(ACT.BANS)
    return pnl
end

-- ============================================================
-- Aba principal
-- ============================================================
function SherlockHNS.BuildModerationTab(sheet)
    local root = SherlockHNS.UI.Create("DPanel", sheet)
    root:SetPaintBackground(false)
    root:DockPadding(4, 4, 4, 4)

    local sub = SherlockHNS.UI.Create("DPropertySheet", root)
    sub:Dock(FILL)
    sub:AddSheet("Jogadores", BuildPlayers(sub), "icon16/user_edit.png")
    sub:AddSheet("Bans ativos", BuildBans(sub), "icon16/delete.png")

    return root
end
