-- Aba "Moderação" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Moderação", SherlockHNS.BuildModerationTab(sheet), "icon16/shield.png")
-- Sub-abas: Jogadores (online e offline: aplicar e ver histórico) e Bans ativos.

local MOD  = SherlockHNS.Mod
local K    = MOD.KIND
local ACT  = MOD.ACT
local SYNC = MOD.SYNC

local data       = { players = {}, history = {}, historyId = nil, bans = {}, recent = {} }
local refreshers = {}

local function Send(act, fn)
    net.Start("sherlockhns_mod_action")
    net.WriteUInt(act, 4)
    if fn then fn() end
    net.SendToServer()
end

net.Receive("sherlockhns_mod_sync", function()
    local what   = net.ReadUInt(3)
    local target = net.ReadString()
    local n      = net.ReadUInt(16)
    local list   = util.JSONToTable(util.Decompress(net.ReadData(n)) or "") or {}

    if what == SYNC.PLAYERS then
        data.players = list
    elseif what == SYNC.HISTORY then
        data.history, data.historyId = list, target
    elseif what == SYNC.BANS then
        data.bans = list
    elseif what == SYNC.RECENT then
        data.recent = list
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
-- Histórico reutilizável (aba Jogadores e janela de ficha)
-- ============================================================
local function HistList(parent)
    local hist = SherlockHNS.UI.Create("DListView", parent)
    hist:Dock(FILL)
    hist:DockMargin(0, 6, 0, 0)
    hist:SetMultiSelect(false)
    hist:AddColumn("#"):SetFixedWidth(40)
    hist:AddColumn("Tipo"):SetFixedWidth(50)
    hist:AddColumn("Data"):SetFixedWidth(110)
    hist:AddColumn("Admin"):SetFixedWidth(100)
    hist:AddColumn("Motivo")
    hist:AddColumn("Duração"):SetFixedWidth(85)
    hist:AddColumn("Status"):SetFixedWidth(95)
    hist:AddColumn("Prova"):SetFixedWidth(40)
    hist.DoDoubleClick = function(_, _, line) OpenEvidence(line.rec and line.rec.e) end
    return hist
end

local function FillHistList(hist, records)
    hist:Clear()
    for _, r in ipairs(records or {}) do
        local dur = r.k == K.BAN and ((r.ip and "[IP] " or "") .. Expires(r.x)) or ""
        local status = r.v and ("Rev. por " .. r.v) or STATUS[r.s] or ""
        if r.ed then status = (status ~= "" and (status .. " ") or "") .. "(editado)" end
        local line = hist:AddLine(r.i, MOD.KindName[r.k] or "?", When(r.c), r.a, r.r, dur, status,
            (r.e and r.e ~= "") and "Sim" or "")
        line.rec = r
    end
end

-- Minutos que o ban tinha no total (para pré-selecionar no editor)
local function TotalMinutes(r)
    if not r.x or r.x == 0 then return 0 end
    return math.max(1, math.floor((r.x - (r.c or os.time())) / 60 + 0.5))
end

local function EditRecord(r)
    local isBan = r.k == K.BAN
    local frame = vgui.Create("DFrame")
    frame:SetTitle(("Editar %s #%d"):format(MOD.KindName[r.k] or "?", r.i))
    frame:SetSize(460, isBan and 280 or 200)
    frame:Center()
    frame:MakePopup()

    local function Entry(ph, val, max)
        local e = vgui.Create("DTextEntry", frame)
        e:Dock(TOP)
        e:DockMargin(0, 6, 0, 0)
        e:SetPlaceholderText(ph)
        e:SetMaximumCharCount(max)
        e:SetValue(val or "")
        return e
    end

    local reason   = Entry("Motivo (obrigatório)", r.r, MOD.MaxReason)
    local evidence = Entry("Prova: link do Discord (opcional)", r.e, MOD.MaxEvidence)

    local duration, fromNow
    if isBan then
        local row = vgui.Create("DPanel", frame)
        row:Dock(TOP)
        row:DockMargin(0, 6, 0, 0)
        row:SetTall(24)
        row:SetPaintBackground(false)

        duration = vgui.Create("DComboBox", row)
        duration:Dock(LEFT)
        duration:SetWide(210)
        duration:AddChoice("Manter duração atual", false, true)
        for _, d in ipairs(DURATIONS) do duration:AddChoice("Nova duração: " .. d[1], d[2]) end

        local info = vgui.Create("DLabel", frame)
        info:Dock(TOP)
        info:DockMargin(0, 6, 0, 0)
        info:SetTall(36)
        info:SetWrap(true)
        info:SetText(("Duração atual: %s (total ~%s). Por padrão a nova duração conta a partir de quando o ban foi " ..
            "aplicado (%s)."):format(Expires(r.x), r.x == 0 and "permanente" or MOD.FormatDuration(TotalMinutes(r) * 60),
            When(r.c)))

        fromNow = vgui.Create("DCheckBoxLabel", frame)
        fromNow:Dock(TOP)
        fromNow:DockMargin(0, 4, 0, 0)
        fromNow:SetText("Contar a nova duração a partir de agora")
        fromNow:SetTextColor(color_white)
    end

    local ok = vgui.Create("DButton", frame)
    ok:Dock(BOTTOM)
    ok:SetTall(28)
    ok:SetText("Salvar")
    ok.DoClick = function()
        local why = string.Trim(reason:GetValue())
        if (utf8.len(why) or 0) < 3 then
            notification.AddLegacy("Informe o motivo.", NOTIFY_ERROR, 3)
            return
        end
        local ev = string.Trim(evidence:GetValue())
        local okEv, errEv = MOD.ValidEvidence(ev)
        if not okEv then
            notification.AddLegacy(errEv, NOTIFY_ERROR, 4)
            return
        end

        local minutes
        if duration then _, minutes = duration:GetSelected() end
        local hasTime = isBan and minutes ~= nil and minutes ~= false
        local now = hasTime and fromNow:GetChecked() or false

        Send(ACT.EDIT, function()
            net.WriteUInt(r.i, 32)
            net.WriteString(why)
            net.WriteString(ev)
            net.WriteBool(hasTime)
            if hasTime then
                net.WriteUInt(minutes, 20)
                net.WriteBool(now)
            end
        end)
        frame:Close()
    end
end

local function HistButtons(parent, hist)
    local function Sel()
        local line = hist:GetSelected()[1]
        return line and line.rec
    end

    Btn(parent, "Abrir prova", 100, function()
        local r = Sel()
        if r then OpenEvidence(r.e) end
    end)
    Btn(parent, "Revogar / Desbanir", 130, function()
        local r = Sel()
        if not r then return end
        if r.s ~= 0 then
            notification.AddLegacy("Esse registro já não está ativo.", NOTIFY_HINT, 3)
            return
        end
        Derma_Query("Revogar o registro #" .. r.i .. "?", "Confirmar", "Revogar", function()
            Send(ACT.REVOKE, function() net.WriteUInt(r.i, 32) end)
        end, "Cancelar")
    end)
    Btn(parent, "Editar", 80, function()
        local r = Sel()
        if r then EditRecord(r) end
    end)
    if LocalPlayer():IsSuperAdmin() then
        Btn(parent, "Excluir", 80, function()
            local r = Sel()
            if not r then return end
            Derma_Query(("EXCLUIR o registro #%d de vez? Ele some do histórico (para só desfazer, use Revogar)."):format(r.i),
                "Confirmar", "Excluir", function()
                    Send(ACT.DELETE, function() net.WriteUInt(r.i, 32) end)
                end, "Cancelar")
        end)
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

    local hist = HistList(right)

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

    HistButtons(histBtns, hist)

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
        FillHistList(hist, data.history)
    end

    list.OnRowSelected = function(_, _, line)
        if selected == line.id then return end
        selected, selectedName = line.id, line.pname
        title:SetText(selectedName .. "  (" .. selected .. ")")
        data.history = {}
        FillHistory()
        Send(ACT.HISTORY, function() net.WriteString(selected) end)
    end

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
-- Ficha em janela própria (aba Recentes, tecla R na mira / espectando)
-- ============================================================
local fileWin

function SherlockHNS.Mod.OpenFile(id, name)
    if not (IsValid(LocalPlayer()) and LocalPlayer():IsAdmin()) then return end
    if not MOD.ValidId(id) then
        notification.AddLegacy("Esse jogador não tem SteamID64 válido.", NOTIFY_ERROR, 3)
        return
    end
    if IsValid(fileWin) then fileWin:Remove() end

    local frame = vgui.Create("DFrame")
    fileWin = frame
    frame:SetTitle(("Ficha: %s (%s)"):format(name or "?", id))
    frame:SetSize(math.min(ScrW() - 40, 860), math.min(ScrH() - 40, 520))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame:MakePopup()

    local btns = Row(frame)
    local actions = Row(frame, BOTTOM)

    local reason = vgui.Create("DTextEntry", frame)
    reason:Dock(BOTTOM)
    reason:DockMargin(0, 6, 0, 0)
    reason:SetPlaceholderText("Motivo (obrigatório para warn / kick / ban)")
    reason:SetMaximumCharCount(MOD.MaxReason)

    local evidence = vgui.Create("DTextEntry", frame)
    evidence:Dock(BOTTOM)
    evidence:DockMargin(0, 6, 0, 0)
    evidence:SetPlaceholderText("Prova: link do Discord (opcional)")
    evidence:SetMaximumCharCount(MOD.MaxEvidence)

    local hist = HistList(frame)
    HistButtons(btns, hist)
    Btn(btns, "Copiar ID", 80, function()
        SetClipboardText(id)
        notification.AddLegacy("SteamID64 copiado.", NOTIFY_GENERIC, 2)
    end)

    local duration = vgui.Create("DComboBox", actions)
    duration:Dock(LEFT)
    duration:SetWide(130)
    duration:DockMargin(0, 0, 8, 0)
    for _, d in ipairs(DURATIONS) do duration:AddChoice(d[1], d[2], d[2] == 1440) end

    local function Apply(kind)
        local why = string.Trim(reason:GetValue())
        if (utf8.len(why) or 0) < 3 then
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

        local function Go()
            Send(ACT.APPLY, function()
                net.WriteUInt(kind, 3)
                net.WriteString(id)
                net.WriteString(why)
                net.WriteString(ev)
                net.WriteUInt(minutes, 20)
                net.WriteBool(false)
            end)
            reason:SetValue("")
            evidence:SetValue("")
        end

        if kind == K.BAN or kind == K.KICK then
            Derma_Query((kind == K.BAN and "Banir " or "Kickar ") .. (name or id) .. "?", "Confirmar", "Confirmar", Go,
                "Cancelar")
        else
            Go()
        end
    end

    Btn(actions, "Warn", 80, function() Apply(K.WARN) end)
    Btn(actions, "Nota", 80, function() Apply(K.NOTE) end)
    Btn(actions, "Kick", 80, function() Apply(K.KICK) end)
    Btn(actions, "Banir", 80, function() Apply(K.BAN) end)

    frame.Refresh = function(_, what)
        if what == SYNC.HISTORY and data.historyId == id and IsValid(hist) then FillHistList(hist, data.history) end
    end
    refreshers.file = function(what) if IsValid(frame) then frame:Refresh(what) end end

    data.history, data.historyId = {}, nil
    Send(ACT.HISTORY, function() net.WriteString(id) end)
end

-- ============================================================
-- Sub-aba: Recentes (quem saiu por último)
-- ============================================================
local function BuildRecent(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local btns = Row(pnl)

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(false)
    list:AddColumn("Jogador")
    list:AddColumn("SteamID64"):SetFixedWidth(135)
    list:AddColumn("Saiu há"):SetFixedWidth(90)
    list:AddColumn("Warns"):SetFixedWidth(50)
    list:AddColumn("Estado"):SetFixedWidth(70)

    local function Selected()
        local line = list:GetSelected()[1]
        return line and line.rec
    end

    local function Query() Send(ACT.RECENT) end

    Btn(btns, "Atualizar", 90, Query)
    Btn(btns, "Abrir ficha", 100, function()
        local r = Selected()
        if r then SherlockHNS.Mod.OpenFile(r.t, r.n) end
    end)
    Btn(btns, "Copiar ID", 90, function()
        local r = Selected()
        if r then
            SetClipboardText(r.t)
            notification.AddLegacy("SteamID64 copiado.", NOTIFY_GENERIC, 2)
        end
    end)

    list.DoDoubleClick = function(_, _, line) SherlockHNS.Mod.OpenFile(line.rec.t, line.rec.n) end

    refreshers.recent = function(what)
        if what ~= SYNC.RECENT or not IsValid(list) then return end

        local keep = Selected() and Selected().t
        list:Clear()
        for _, r in ipairs(data.recent) do
            local line = list:AddLine(r.n, r.t, MOD.FormatDuration(os.time() - (r.l or 0)),
                r.w > 0 and r.w or "", r.b == 1 and "BANIDO" or "")
            line.rec = r
            if r.t == keep then list:SelectItem(line) end
        end
    end

    local nextPoll = 0
    function pnl:Think()
        if CurTime() < nextPoll then return end
        nextPoll = CurTime() + 8
        Query()
    end

    Query()
    return pnl
end

-- Atalho: R na mira (nameplate) ou espectando um jogador abre a ficha dele
local function ModFileTarget()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    if lp:GetObserverMode() ~= OBS_MODE_NONE then
        local t = lp:GetObserverTarget()
        if IsValid(t) and t:IsPlayer() then return t end
    end
    local np = SherlockHNS.Nameplate
    return np and np.GetAimed and np.GetAimed() or nil
end

function SherlockHNS.Mod.FileTarget() return ModFileTarget() end

if SherlockHNS.Keys then
    SherlockHNS.Keys.On("modfile", function()
        local lp = LocalPlayer()
        if not (IsValid(lp) and lp:IsAdmin()) then return end

        local t = ModFileTarget()
        if not IsValid(t) then return end
        if t:IsBot() then
            notification.AddLegacy("Bots não têm ficha.", NOTIFY_HINT, 3)
            return
        end
        SherlockHNS.Mod.OpenFile(t:SteamID64(), t:Nick())
    end)
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
    sub:AddSheet("Recentes", BuildRecent(sub), "icon16/door_out.png")

    return root
end
