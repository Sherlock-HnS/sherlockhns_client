-- Aba "Killers" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Killers", SherlockHNS.BuildKillersTab(sheet), "icon16/user_red.png")
-- Sub-abas: Fixados (killer fixo + pill), Fila de partners, Elegibilidade (bloqueados do sorteio).

local K          = SherlockHNS.Killers
local ACT        = K.ACT

local data       = { fixed = {}, blocked = {}, queue = {} }
local refreshers = {}

local function Send(act, fn)
    net.Start("sherlockhns_killers_admin")
    net.WriteUInt(act, 3)
    if fn then fn() end
    net.SendToServer()
end

net.Receive("sherlockhns_killers_sync", function()
    local n      = net.ReadUInt(16)
    local t      = util.JSONToTable(util.Decompress(net.ReadData(n)) or "") or {}

    data.fixed   = t.fixed or {}
    data.blocked = t.blocked or {}
    data.queue   = t.queue or {}

    for _, fn in pairs(refreshers) do fn() end
end)

-- ===== Helpers =====
local function Has(list, id)
    for _, e in ipairs(list) do
        if e.id == id then return true end
    end
    return false
end

local function PillLabel(name)
    if not name or name == "" then return "aleatória" end
    local t = pk_pills and pk_pills.getPillTable and pk_pills.getPillTable(name)
    return t and tostring(t.printName or name) or name
end

local function AllPills()
    local out = {}
    if not (pk_pills and pk_pills.Forms) then return out end

    for name, t in pairs(pk_pills.Forms) do
        if istable(t) and t.printName then out[#out + 1] = { name = name, label = tostring(t.printName) } end
    end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
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

local function Row(parent)
    local r = SherlockHNS.UI.Create("DPanel", parent)
    SherlockHNS.UI.Flow(r)
    r:Dock(BOTTOM)
    r:DockMargin(0, 6, 0, 0)
    r:SetTall(28)
    r:SetPaintBackground(false)
    return r
end

local function Header(parent, text)
    local l = SherlockHNS.UI.Create("DLabel", parent)
    l:Dock(TOP)
    l:DockMargin(0, 4, 0, 2)
    l:SetTall(18)
    l:SetFont("DermaDefaultBold")
    l:SetText(text)
    return l
end

-- Recria as linhas mantendo a seleção (pelo id)
local function Refill(list, rows, cols)
    if not IsValid(list) then return end

    local keep = {}
    for _, l in ipairs(list:GetSelected()) do keep[l.id] = true end

    list:Clear()
    for _, r in ipairs(rows) do
        local line = list:AddLine(unpack(cols(r)))
        line.id = r.id
        if keep[r.id] then list:SelectItem(line) end
    end
end

local function SelectedIds(list)
    local out = {}
    if not IsValid(list) then return out end
    for _, line in ipairs(list:GetSelected()) do
        if line.id then out[#out + 1] = line.id end
    end
    return out
end

-- Lista de jogadores online (sem bots). stateFn(ply, id) -> texto da coluna "Estado".
local function OnlineList(parent, stateFn)
    local list = SherlockHNS.UI.Create("DListView", parent)
    list:SetMultiSelect(true)
    list:AddColumn("Jogador")
    list:AddColumn("Estado"):SetFixedWidth(130)

    local lines = {}

    function list:Sync()
        for p, line in pairs(lines) do
            if not IsValid(p) then
                self:RemoveLine(line:GetID())
                lines[p] = nil
            end
        end

        for _, p in ipairs(player.GetAll()) do
            if not p:IsBot() then
                local id = p:SteamID64()
                local line = lines[p]
                if not line then
                    line = self:AddLine("", "")
                    line.id = id
                    lines[p] = line
                end
                line:SetColumnText(1, p:Nick())
                line:SetColumnText(2, stateFn(p, id) or "")
            end
        end
    end

    local nextSync = 0
    function list:Think()
        if CurTime() < nextSync then return end
        nextSync = CurTime() + 0.5
        self:Sync()
    end

    list:Sync()
    return list
end

-- ============================================================
-- Sub-aba: Fixados
-- ============================================================
local function BuildFixed(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    -- (de baixo para cima)
    local rowId   = Row(pnl)
    local rowBtns = Row(pnl)

    local perm    = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
    perm:Dock(BOTTOM)
    perm:DockMargin(0, 6, 0, 0)
    perm:SetText("Permanente (desmarcado: vale só para a próxima rodada)")
    perm:SetDark(true)
    perm:SetValue(false)

    -- Esquerda: jogadores online + fixados
    local left = SherlockHNS.UI.Create("DPanel", pnl)
    left:Dock(LEFT)
    left:SetWide(430)
    left:SetPaintBackground(false)
    SherlockHNS.UI.Split(pnl, left, 430, 900)
    left:DockMargin(0, 0, 6, 0)

    Header(left, "Jogadores online")
    local online = OnlineList(left, function(_, id) return Has(data.fixed, id) and "Fixado" or "" end)
    online:Dock(TOP)
    online:SetTall(230)

    Header(left, "Killers fixados")
    local fixedList = SherlockHNS.UI.Create("DListView", left)
    fixedList:Dock(FILL)
    fixedList:SetMultiSelect(true)
    fixedList:AddColumn("Jogador")
    fixedList:AddColumn("Pill")
    fixedList:AddColumn("Perm."):SetFixedWidth(45)
    fixedList:AddColumn("Online"):SetFixedWidth(50)

    -- Direita: escolha da pill
    local right = SherlockHNS.UI.Create("DPanel", pnl)
    right:Dock(FILL)
    right:SetPaintBackground(false)

    local pill = ""

    local current = SherlockHNS.UI.Create("DLabel", right)
    current:Dock(TOP)
    current:SetTall(20)
    current:SetFont("DermaDefaultBold")
    current:SetText("Pill: aleatória (sorteada na whitelist)")

    local search = SherlockHNS.UI.Create("DTextEntry", right)
    search:Dock(TOP)
    search:DockMargin(0, 4, 0, 4)
    search:SetPlaceholderText("Buscar pill...")

    local pillList = SherlockHNS.UI.Create("DListView", right)
    pillList:Dock(FILL)
    pillList:SetMultiSelect(false)
    pillList:AddColumn("Pill")
    pillList:AddColumn("ID")

    local pills = AllPills()
    local function PopulatePills()
        local filter = string.lower(search:GetValue() or "")
        pillList:Clear()

        local rnd = pillList:AddLine("(aleatória)", "")
        rnd.pillName = ""

        for _, p in ipairs(pills) do
            if filter == "" or p.label:lower():find(filter, 1, true) or p.name:lower():find(filter, 1, true) then
                local line = pillList:AddLine(p.label, p.name)
                line.pillName = p.name
                if p.name == pill then pillList:SelectItem(line) end
            end
        end
    end

    pillList.OnRowSelected = function(_, _, line)
        pill = line.pillName or ""
        current:SetText("Pill: " .. (pill == "" and "aleatória (sorteada na whitelist)" or PillLabel(pill)))
    end
    search.OnChange = PopulatePills
    PopulatePills()

    -- Ações
    local function Fix(id)
        Send(ACT.FIX, function()
            net.WriteString(id)
            net.WriteString(pill)
            net.WriteBool(perm:GetChecked())
        end)
    end

    Btn(rowBtns, "Fixar selecionados", 150, function()
        for _, id in ipairs(SelectedIds(online)) do Fix(id) end
    end)
    Btn(rowBtns, "Aplicar pill/perm. aos fixados", 190, function()
        for _, id in ipairs(SelectedIds(fixedList)) do Fix(id) end
    end)
    Btn(rowBtns, "Remover fixados", 140, function()
        for _, id in ipairs(SelectedIds(fixedList)) do
            Send(ACT.UNFIX, function() net.WriteString(id) end)
        end
    end)

    -- por SteamID64 (funciona com o jogador offline)
    local entry = SherlockHNS.UI.Create("DTextEntry", rowId)
    entry:Dock(LEFT)
    entry:SetWide(210)
    entry:DockMargin(0, 0, 6, 0)
    entry:SetPlaceholderText("SteamID64 (jogador offline)")

    Btn(rowId, "Fixar SteamID64", 140, function()
        local id = string.Trim(entry:GetValue())
        if not (string.match(id, "^%d+$") and #id >= 15 and #id <= 20) then
            notification.AddLegacy("SteamID64 inválido.", NOTIFY_ERROR, 3)
            return
        end
        Fix(id)
        entry:SetValue("")
    end)

    refreshers.fixed = function()
        Refill(fixedList, data.fixed, function(e)
            return { e.name, PillLabel(e.pill), e.sticky and "Sim" or "Não", e.online and "Sim" or "Não" }
        end)
        if IsValid(online) then online:Sync() end
    end
    refreshers.fixed()

    return pnl
end

-- ============================================================
-- Sub-aba: Fila de partners
-- ============================================================
local function BuildQueue(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local rowBtns = Row(pnl)

    local online = OnlineList(pnl, function(p, id)
        if Has(data.queue, id) then return "Na fila" end
        if SherlockHNS.Partner.IsPartner(p) then return "Partner" end
        return "Não é partner"
    end)
    online:Dock(RIGHT)
    online:SetWide(380)
    online:DockMargin(6, 0, 0, 0)

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(true)
    list:AddColumn("#"):SetFixedWidth(40)
    list:AddColumn("Jogador")
    list:AddColumn("Killer em"):SetFixedWidth(110)

    local function Move(dir)
        local id = SelectedIds(list)[1]
        if not id then return end
        Send(ACT.QMOVE, function()
            net.WriteString(id)
            net.WriteInt(dir, 3)
        end)
    end

    Btn(rowBtns, "Subir", 90, function() Move(-1) end)
    Btn(rowBtns, "Descer", 90, function() Move(1) end)
    Btn(rowBtns, "Remover da fila", 140, function()
        for _, id in ipairs(SelectedIds(list)) do
            Send(ACT.QREMOVE, function() net.WriteString(id) end)
        end
    end)
    Btn(rowBtns, "◀ Adicionar selecionados", 180, function()
        for _, id in ipairs(SelectedIds(online)) do
            Send(ACT.QADD, function() net.WriteString(id) end)
        end
    end)

    refreshers.queue = function()
        local rows = {}
        for i, q in ipairs(data.queue) do
            rows[i] = { id = q.id, name = q.name, wait = q.wait, pos = i }
        end

        Refill(list, rows, function(r)
            local wait = r.wait <= 0 and "-" or (r.wait == 1 and "próxima" or (r.wait .. " partidas"))
            return { r.pos, r.name, wait }
        end)
        if IsValid(online) then online:Sync() end
    end
    refreshers.queue()

    return pnl
end

-- ============================================================
-- Sub-aba: Elegibilidade
-- ============================================================
local function BuildEligibility(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local rowId   = Row(pnl)
    local rowBtns = Row(pnl)

    local hint    = SherlockHNS.UI.Create("DLabel", pnl)
    hint:Dock(TOP)
    hint:DockMargin(0, 0, 0, 6)
    hint:SetWrap(true)
    hint:SetAutoStretchVertical(true)
    hint:SetText("Bloqueados não entram no sorteio aleatório de killer. Killers fixados e a fila de partners " ..
        "continuam valendo. Se todos estiverem bloqueados, o bloqueio é ignorado na rodada.")

    local blockedList = SherlockHNS.UI.Create("DListView", pnl)
    blockedList:Dock(RIGHT)
    blockedList:SetWide(340)
    blockedList:DockMargin(6, 0, 0, 0)
    blockedList:SetMultiSelect(true)
    blockedList:AddColumn("Bloqueados")
    blockedList:AddColumn("SteamID64"):SetFixedWidth(135)

    local online = OnlineList(pnl, function(_, id) return Has(data.blocked, id) and "Bloqueado" or "Elegível" end)
    online:Dock(FILL)

    local function Block(id, state)
        Send(ACT.BLOCK, function()
            net.WriteString(id)
            net.WriteBool(state)
        end)
    end

    Btn(rowBtns, "Bloquear selecionados", 160, function()
        for _, id in ipairs(SelectedIds(online)) do Block(id, true) end
    end)
    Btn(rowBtns, "Liberar selecionados", 160, function()
        local ids = {}
        for _, id in ipairs(SelectedIds(online)) do
            if Has(data.blocked, id) then ids[id] = true end
        end
        for _, id in ipairs(SelectedIds(blockedList)) do ids[id] = true end
        for id in pairs(ids) do Block(id, false) end
    end)

    local entry = SherlockHNS.UI.Create("DTextEntry", rowId)
    entry:Dock(LEFT)
    entry:SetWide(210)
    entry:DockMargin(0, 0, 6, 0)
    entry:SetPlaceholderText("SteamID64 (jogador offline)")

    Btn(rowId, "Bloquear SteamID64", 150, function()
        local id = string.Trim(entry:GetValue())
        if not (string.match(id, "^%d+$") and #id >= 15 and #id <= 20) then
            notification.AddLegacy("SteamID64 inválido.", NOTIFY_ERROR, 3)
            return
        end
        Block(id, true)
        entry:SetValue("")
    end)

    refreshers.eligibility = function()
        Refill(blockedList, data.blocked, function(e) return { e.name, e.id } end)
        if IsValid(online) then online:Sync() end
    end
    refreshers.eligibility()

    return pnl
end

-- ============================================================
-- Aba principal
-- ============================================================
function SherlockHNS.BuildKillersTab(sheet)
    local root = SherlockHNS.UI.Create("DPanel", sheet)
    root:SetPaintBackground(false)
    root:DockPadding(4, 4, 4, 4)

    local sub = SherlockHNS.UI.Create("DPropertySheet", root)
    sub:Dock(FILL)
    sub:AddSheet("Fixados", BuildFixed(sub), "icon16/lock.png")
    sub:AddSheet("Fila de partners", BuildQueue(sub), "icon16/star.png")
    sub:AddSheet("Elegibilidade", BuildEligibility(sub), "icon16/user_delete.png")

    -- atualiza enquanto a aba está visível
    local nextReq = 0
    function root:Think()
        if CurTime() < nextReq then return end
        nextReq = CurTime() + 3
        Send(ACT.REQUEST)
    end

    Send(ACT.REQUEST)
    return root
end
