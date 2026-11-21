-- Aba "Partner" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Partner", SherlockHNS.BuildPartnerTab(sheet), "icon16/star.png")
-- Sub-abas: Partners (gerenciar), Códigos (criar/excluir), Limites (toggles e sliders).

local P          = SherlockHNS.Partner
local ADM        = P.ADMIN

local data       = { partners = {}, codes = {} }
local refreshers = {}

local function SendConfig(key, value)
    net.Start("sherlockhns_admin_config")
    net.WriteString(key)
    net.WriteFloat(value)
    net.SendToServer()
end

local function SendAdmin(act, fn)
    net.Start("sherlockhns_partner_admin")
    net.WriteUInt(act, 3)
    if fn then fn() end
    net.SendToServer()
end

net.Receive("sherlockhns_partner_sync", function()
    local n = net.ReadUInt(16)
    local json = util.Decompress(net.ReadData(n)) or ""
    local t = util.JSONToTable(json) or {}

    data.partners = t.partners or {}
    data.codes = t.codes or {}

    for _, fn in pairs(refreshers) do fn() end
end)

local function ValidId(id)
    return string.match(id, "^%d+$") ~= nil and #id >= 15 and #id <= 20
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

local function Row(parent, tall)
    local r = SherlockHNS.UI.Create("DPanel", parent)
    SherlockHNS.UI.Flow(r)
    r:Dock(BOTTOM)
    r:DockMargin(0, 6, 0, 0)
    r:SetTall(tall or 28)
    r:SetPaintBackground(false)
    return r
end

-- ============================================================
-- Sub-aba: Partners
-- ============================================================
local function ExpText(isPartner, exp)
    if not isPartner then return "-" end
    if not exp or exp == 0 then return "Permanente" end

    local left = exp - os.time()
    if left <= 0 then return "Expirado" end
    return ("%dd (até %s)"):format(math.ceil(left / 86400), os.date("%d/%m/%Y", exp))
end

local function BuildPartners(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    -- (criados de baixo para cima)
    local rowId = Row(pnl)
    local rowBtns = Row(pnl)
    local rowPresets = Row(pnl)

    local days = SherlockHNS.UI.Create("DNumSlider", pnl)
    days:Dock(BOTTOM)
    days:DockMargin(0, 6, 0, 0)
    days:SetText("Duração do partner (dias, 0 = permanente)")
    days:SetDark(true)
    days:SetMin(0)
    days:SetMax(P.MaxPartnerDays)
    days:SetDecimals(0)
    days:SetValue(30)

    local qty = SherlockHNS.UI.Create("DNumSlider", pnl)
    qty:Dock(BOTTOM)
    qty:DockMargin(0, 6, 0, 0)
    qty:SetText("Revives a dar (negativo remove)")
    qty:SetDark(true)
    qty:SetMin(-20)
    qty:SetMax(50)
    qty:SetDecimals(0)
    qty:SetValue(3)

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(true)
    list:AddColumn("Jogador")
    list:AddColumn("SteamID64"):SetFixedWidth(135)
    list:AddColumn("Partner"):SetFixedWidth(50)
    list:AddColumn("Expira"):SetFixedWidth(130)
    list:AddColumn("Revives"):SetFixedWidth(55)

    local lines = {}

    local function Refresh()
        if not IsValid(list) then return end

        local rows = {}
        for _, p in ipairs(player.GetAll()) do
            if not p:IsBot() then
                local id = p:SteamID64()
                if id then
                    rows[id] = {
                        name = p:Nick(),
                        partner = P.IsPartner(p),
                        expires = p:GetNWInt("hns_partner_exp", 0),
                        revives = P.GetRevives(p),
                    }
                end
            end
        end
        -- partners offline vêm do servidor
        for _, e in ipairs(data.partners) do
            if not rows[e.id] then
                rows[e.id] = {
                    name = (e.name ~= "" and e.name or "(offline)"),
                    partner = true,
                    expires = e.expires or 0,
                    revives = e.revives,
                }
            end
        end

        for id, line in pairs(lines) do
            if not rows[id] then
                list:RemoveLine(line:GetID())
                lines[id] = nil
            end
        end

        for id, r in pairs(rows) do
            local line = lines[id]
            if not line then
                line = list:AddLine("", id, "", "", "")
                line.id = id
                lines[id] = line
            end
            line:SetColumnText(1, r.name)
            line:SetColumnText(3, r.partner and "Sim" or "Não")
            line:SetColumnText(4, ExpText(r.partner, r.expires))
            line:SetColumnText(5, tostring(r.revives))
            line:SetSortValue(3, r.partner and 1 or 0)
            line:SetSortValue(4, r.partner and (r.expires == 0 and math.huge or r.expires) or -1)
            line:SetSortValue(5, r.revives)
        end
    end

    local nextSync = 0
    function list:Think()
        if CurTime() < nextSync then return end
        nextSync = CurTime() + 0.5
        Refresh()
    end

    refreshers.partners = Refresh

    local function Selected()
        local out = {}
        for _, line in ipairs(list:GetSelected()) do out[#out + 1] = line.id end
        return out
    end

    local function SetPartner(id, state)
        SendAdmin(ADM.SET_PARTNER, function()
            net.WriteString(id)
            net.WriteBool(state)
            net.WriteUInt(state and math.floor(days:GetValue()) or 0, 8)
        end)
    end

    -- atalhos de duração
    for _, preset in ipairs({
        { "15 dias", 15 }, { "30 dias", 30 }, { "60 dias", 60 }, { "90 dias", 90 }, { "Permanente", 0 },
    }) do
        Btn(rowPresets, preset[1], 80, function() days:SetValue(preset[2]) end)
    end

    Btn(rowBtns, "Tornar partner", 130, function()
        for _, id in ipairs(Selected()) do SetPartner(id, true) end
    end)
    Btn(rowBtns, "Remover partner", 130, function()
        for _, id in ipairs(Selected()) do SetPartner(id, false) end
    end)
    Btn(rowBtns, "Aplicar revives", 130, function()
        local n = math.floor(qty:GetValue())
        if n == 0 then return end
        for _, id in ipairs(Selected()) do
            SendAdmin(ADM.GIVE_REVIVES, function()
                net.WriteString(id)
                net.WriteInt(n, 16)
            end)
        end
    end)

    -- por SteamID64 (funciona com o jogador offline)
    local entry = SherlockHNS.UI.Create("DTextEntry", rowId)
    entry:Dock(LEFT)
    entry:SetWide(210)
    entry:DockMargin(0, 0, 6, 0)
    entry:SetPlaceholderText("SteamID64 (jogador offline)")

    local function ById(state)
        local id = string.Trim(entry:GetValue())
        if not ValidId(id) then
            notification.AddLegacy("SteamID64 inválido.", NOTIFY_ERROR, 3)
            return
        end
        SetPartner(id, state)
        entry:SetValue("")
    end

    Btn(rowId, "Adicionar partner", 130, function() ById(true) end)
    Btn(rowId, "Remover partner", 130, function() ById(false) end)

    Refresh()
    return pnl
end

-- ============================================================
-- Sub-aba: Códigos
-- ============================================================
local function BuildCodes(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local rowBtns = Row(pnl)

    -- formulário
    local entry = SherlockHNS.UI.Create("DTextEntry", pnl)
    entry:Dock(TOP)
    entry:SetPlaceholderText("Código (vazio = gerar automaticamente)")
    entry:SetMaximumCharCount(P.CodeMaxLen)

    local function Slider(text, min, max, default)
        local s = SherlockHNS.UI.Create("DNumSlider", pnl)
        s:Dock(TOP)
        s:DockMargin(0, 4, 0, 0)
        s:SetText(text)
        s:SetDark(true)
        s:SetMin(min)
        s:SetMax(max)
        s:SetDecimals(0)
        s:SetValue(default)
        return s
    end

    local rev     = Slider("Revives por resgate", 1, P.MaxRevives, 3)
    local uses    = Slider("Usos totais (0 = ilimitado)", 0, 1000, 1)
    local uperply = Slider("Usos por jogador (quantas vezes cada um pode resgatar)", 1, 10, 1)
    local hours   = Slider("Validade em horas (0 = não expira)", 0, 720, 0)

    local create  = SherlockHNS.UI.Create("DButton", pnl)
    create:Dock(TOP)
    create:DockMargin(0, 6, 0, 6)
    create:SetTall(28)
    create:SetText("Criar código")
    create.DoClick = function()
        SendAdmin(ADM.CREATE_CODE, function()
            net.WriteString(string.Trim(entry:GetValue()))
            net.WriteUInt(math.floor(rev:GetValue()), 8)
            net.WriteUInt(math.floor(uses:GetValue()), 16)
            net.WriteUInt(math.floor(hours:GetValue()), 16)
            net.WriteUInt(math.floor(uperply:GetValue()), 8)
        end)
        entry:SetValue("")
    end

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(FILL)
    list:SetMultiSelect(true)
    list:AddColumn("Código")
    list:AddColumn("Revives"):SetFixedWidth(60)
    list:AddColumn("Usos"):SetFixedWidth(80)
    list:AddColumn("P/ jogador"):SetFixedWidth(80)
    list:AddColumn("Validade"):SetFixedWidth(110)

    local lines = {}

    local function Refresh()
        if not IsValid(list) then return end

        local present = {}
        for _, c in ipairs(data.codes) do
            present[c.code] = true

            local line = lines[c.code]
            if not line then
                line = list:AddLine(c.code, "", "", "")
                line.code = c.code
                lines[c.code] = line
            end

            local validity = "nunca"
            if c.expires and c.expires > 0 then
                validity = (os.time() >= c.expires) and "expirado" or os.date("%d/%m %H:%M", c.expires)
            end

            line:SetColumnText(2, tostring(c.revives))
            line:SetColumnText(3, c.uses .. "/" .. (c.maxUses == 0 and "∞" or c.maxUses))
            line:SetColumnText(4, tostring(c.usesPerPlayer or 1))
            line:SetColumnText(5, validity)
        end

        for code, line in pairs(lines) do
            if not present[code] then
                list:RemoveLine(line:GetID())
                lines[code] = nil
            end
        end
    end

    refreshers.codes = Refresh

    Btn(rowBtns, "Excluir selecionados", 150, function()
        for _, line in ipairs(list:GetSelected()) do
            local code = line.code
            SendAdmin(ADM.DELETE_CODE, function() net.WriteString(code) end)
        end
    end)
    Btn(rowBtns, "Copiar código", 120, function()
        local line = list:GetSelected()[1]
        if line then SetClipboardText(line.code) end
    end)

    Refresh()
    return pnl
end

-- ============================================================
-- Sub-aba: Limites (toggles e sliders)
-- ============================================================
local function BuildLimits(parent)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local scroll = SherlockHNS.UI.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)

    for _, g in ipairs(P.Groups) do
        local head = SherlockHNS.UI.Create("DLabel", scroll)
        head:Dock(TOP)
        head:DockMargin(0, 10, 0, 4)
        head:SetTall(20)
        head:SetFont("DermaDefaultBold")
        head:SetDark(true)
        head:SetText(g.title)

        for _, t in ipairs(P.Toggles) do
            if t.group == g.id then
                local c = SherlockHNS.UI.Create("DCheckBoxLabel", scroll)
                c:Dock(TOP)
                c:DockMargin(0, 0, 0, 6)
                c:SetText(t.label)
                c:SetDark(true)
                c:SetValue(P.Toggle(t.key))
                -- definido depois do SetValue para não enviar na abertura
                function c:OnChange(val)
                    SendConfig(t.key, val and 1 or 0)
                end
            end
        end

        for _, s in ipairs(P.Settings) do
            if s.group == g.id then
                local sl = SherlockHNS.UI.Create("DNumSlider", scroll)
                sl:Dock(TOP)
                sl:DockMargin(0, 0, 16, 4)
                sl:SetText(s.label)
                sl:SetDark(true)
                sl:SetMin(s.min)
                sl:SetMax(s.max)
                sl:SetDecimals(0)
                sl:SetValue(P.Num(s.key))

                sl.OnValueChanged = function(_, v)
                    timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
                        SendConfig(s.key, v)
                    end)
                end
            end
        end
    end

    return pnl
end

-- ============================================================
-- Aba principal
-- ============================================================
function SherlockHNS.BuildPartnerTab(sheet)
    local root = SherlockHNS.UI.Create("DPanel", sheet)
    root:SetPaintBackground(false)
    root:DockPadding(4, 4, 4, 4)

    local sub = SherlockHNS.UI.Create("DPropertySheet", root)
    sub:Dock(FILL)

    if P.CanManage(LocalPlayer()) then
        sub:AddSheet("Partners", BuildPartners(sub), "icon16/user_gray.png")
        sub:AddSheet("Códigos", BuildCodes(sub), "icon16/key.png")

        -- atualiza a lista enquanto a aba está visível
        local nextReq = 0
        function root:Think()
            if CurTime() < nextReq then return end
            nextReq = CurTime() + 3
            SendAdmin(ADM.REQUEST)
        end
    else
        local denied = SherlockHNS.UI.Create("DLabel", sub)
        denied:SetDark(true)
        denied:SetContentAlignment(5)
        denied:SetText("Apenas superadmins gerenciam partners e códigos.")
        sub:AddSheet("Partners", denied, "icon16/lock.png")
    end

    sub:AddSheet("Limites", BuildLimits(sub), "icon16/cog.png")

    return root
end
