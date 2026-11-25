-- Partner (cliente): aba "Benefícios" do menu (usada por cl_menu.lua via P.BuildTab).
-- Servidor: gamemode/sv_partner.lua | Shared: gamemode/sh_partner.lua

local P       = SherlockHNS.Partner
local ACT     = P.ACT

local COL_OK  = Color(90, 220, 120)
local COL_BAD = Color(230, 80, 80)

local last    = { ok = true, msg = "", at = -100 }

-- ===== Envio =====
local function Send(act, fn)
    net.Start("sherlockhns_partner_action")
    net.WriteUInt(act, 3)
    if fn then fn() end
    net.SendToServer()
end

function P.Redeem(code) Send(ACT.REDEEM, function() net.WriteString(code) end) end

function P.UseRevive() Send(ACT.REVIVE) end

function P.DonateRevives(targetId, amount)
    Send(ACT.DONATE, function()
        net.WriteString(targetId)
        net.WriteUInt(amount, 7)
    end)
end

function P.QueueKiller() Send(ACT.QUEUE) end

function P.LeaveQueue() Send(ACT.UNQUEUE) end

net.Receive("sherlockhns_partner_result", function()
    local ok, msg = net.ReadBool(), net.ReadString()
    last = { ok = ok, msg = msg, at = CurTime() }
    surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
end)

-- ===== Aba =====
-- cl_menu.lua chama P.BuildTab(parent, ui); ui = { U, F, accent, dim }
function P.BuildTab(parent, ui)
    local UU, F = ui.U, ui.F
    local lp = LocalPlayer()

    local scroll = SherlockHNS.UI.Create("DScrollPanel", parent)
    scroll:Dock(FILL)

    local function Section(text)
        local l = SherlockHNS.UI.Create("DLabel", scroll)
        l:Dock(TOP)
        l:DockMargin(0, UU(14), 0, UU(6))
        l:SetTall(UU(24))
        l:SetFont(F(16))
        l:SetTextColor(ui.accent)
        l:SetText(text)
    end

    local function Info(text)
        local l = SherlockHNS.UI.Create("DLabel", scroll)
        l:Dock(TOP)
        l:DockMargin(0, 0, UU(16), UU(6))
        l:SetTall(UU(26))
        l:SetFont(F(17, 500))
        l:SetTextColor(ui.dim)
        l:SetWrap(true)
        l:SetAutoStretchVertical(true)
        l:SetText(text)
    end

    -- texto atualizado a cada frame: getter() -> texto, cor
    local function Live(font, getter)
        local l = SherlockHNS.UI.Create("DLabel", scroll)
        l:Dock(TOP)
        l:DockMargin(0, 0, UU(16), UU(6))
        l:SetTall(UU(26))
        l:SetFont(font)
        l:SetWrap(true)
        l:SetAutoStretchVertical(true)
        function l:Think()
            local txt, col = getter()
            if txt ~= self.txt then
                self.txt = txt
                self:SetText(txt)
            end
            self:SetTextColor(col or color_white)
        end
    end

    local function Btn(textFn, onClick, enabledFn)
        local b = SherlockHNS.UI.Create("DButton", scroll)
        b:Dock(TOP)
        b:DockMargin(0, 0, UU(16), UU(6))
        b:SetTall(UU(42))
        b:SetFont(F(18))
        b.DoClick = onClick
        function b:Think()
            local t = textFn()
            if t ~= self.txt then
                self.txt = t
                self:SetText(t)
            end
            local en = enabledFn == nil or enabledFn()
            if en ~= self:IsEnabled() then self:SetEnabled(en) end
        end
    end

    -- resposta do servidor (código, revive, fila)
    Live(F(18), function()
        if CurTime() - last.at > 8 then return "" end
        return last.msg, last.ok and COL_OK or COL_BAD
    end)

    -- ===== Revives =====
    Section("Revives")
    Live(F(22), function()
        return ("Revives: %d / %d"):format(P.GetRevives(lp), P.MaxRevives)
    end)
    Live(F(17, 500), function()
        if not P.Toggle("PtReviveOn") then return "Os revives estão desativados no momento.", COL_BAD end
        local t = ("Use depois de morrer como runner (até %d por rodada)."):format(P.Num("PtReviveRound"))
        local cd, win = P.Num("PtReviveCd"), P.Num("PtReviveWindow")
        if cd > 0 then t = t .. (" Cooldown de %ds."):format(cd) end
        if win > 0 then t = t .. (" Prazo de %ds após morrer."):format(win) end
        if not P.Toggle("PtReviveLMS") then t = t .. " Não vale no último runner." end
        return t, ui.dim
    end)
    Btn(function() return "Usar revive" end, function() P.UseRevive() end,
        function() return P.GetRevives(lp) > 0 and P.Toggle("PtReviveOn") end)

    -- ===== Doar revives =====
    Section("Doar revives")
    Live(F(17, 500), function()
        if not P.Toggle("PtDonateOn") then return "A doação de revives está desativada no momento.", COL_BAD end
        return "Transfira revives do seu saldo para qualquer jogador online. A doação não pode ser desfeita.", ui.dim
    end)

    local targetId, targetName -- destinatário escolhido
    local amount = 1
    local armed                -- doação aguardando o segundo clique: { key, expires }

    local who = SherlockHNS.UI.Create("DComboBox", scroll)
    who:Dock(TOP)
    who:DockMargin(0, 0, UU(16), UU(6))
    who:SetTall(UU(36))
    who:SetSortItems(false)
    who.OnSelect = function(_, _, name, id) targetId, targetName = id, name end

    -- refaz a lista só quando alguém entra, sai, troca de nick ou vira partner
    local nextScan = 0
    function who:Think()
        if CurTime() < nextScan then return end
        nextScan = CurTime() + 1

        local list, sig = {}, {}
        for _, p in ipairs(player.GetHumans()) do
            if p ~= lp then
                local name = p:Nick() .. (P.IsPartner(p) and " (partner)" or "")
                list[#list + 1] = { id = p:SteamID64(), name = name }
            end
        end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
        for i, r in ipairs(list) do sig[i] = r.id .. r.name end
        sig = table.concat(sig, "\n")
        if sig == self.sig then return end
        self.sig = sig

        local keep = targetId
        targetId, targetName = nil, nil
        self:Clear()
        self:SetValue(#list > 0 and "Escolha o jogador" or "Nenhum outro jogador online")
        for _, r in ipairs(list) do
            local selected = r.id == keep
            self:AddChoice(r.name, r.id, selected)
        end
    end

    local qty = SherlockHNS.UI.Create("DNumSlider", scroll)
    qty:Dock(TOP)
    qty:DockMargin(0, 0, UU(16), UU(6))
    qty:SetTall(UU(32))
    qty:SetText("Quantidade")
    qty:SetMin(1)
    qty:SetMax(math.max(2, P.GetRevives(lp))) -- min == max quebraria o slider
    qty:SetDecimals(0)
    qty:SetValue(1)
    qty.OnValueChanged = function(_, v) amount = math.max(1, math.Round(v)) end

    -- o máximo acompanha o saldo atual
    function qty:Think()
        local have = P.GetRevives(lp)
        if have == self.have then return end
        self.have = have
        self:SetMax(math.max(2, have))
        if amount > math.max(1, have) then self:SetValue(math.max(1, have)) end
    end

    local function ArmKey() return tostring(targetId) .. ":" .. amount end
    local function IsArmed() return armed ~= nil and armed.key == ArmKey() and CurTime() < armed.expires end

    Btn(function()
        if IsArmed() then return ("Confirmar: doar %d para %s"):format(amount, targetName) end
        return "Doar revives"
    end, function()
        if not IsArmed() then
            armed = { key = ArmKey(), expires = CurTime() + 4 }
            return
        end
        armed = nil
        P.DonateRevives(targetId, amount)
    end, function()
        local have = P.GetRevives(lp)
        return P.Toggle("PtDonateOn") and targetId ~= nil and have > 0 and amount <= have
    end)

    -- ===== Código =====
    Section("Código")
    local entry = SherlockHNS.UI.Create("DTextEntry", scroll)
    entry:Dock(TOP)
    entry:DockMargin(0, 0, UU(16), UU(6))
    entry:SetTall(UU(38))
    entry:SetFont(F(18))
    entry:SetPlaceholderText("Digite o código")
    entry:SetMaximumCharCount(P.CodeMaxLen)

    -- o menu desliga o teclado; liga só enquanto o campo tem foco.
    -- Sobe a hierarquia de painéis até o popup raiz para habilitar/desabilitar.
    local function RootPopup()
        return IsValid(ui.root) and ui.root or parent
    end

    function entry:OnGetFocus()
        local r = RootPopup()
        if IsValid(r) then r:SetKeyboardInputEnabled(true) end
        hook.Run("OnTextEntryGetFocus", self)
    end

    function entry:OnLoseFocus()
        local r = RootPopup()
        if IsValid(r) then r:SetKeyboardInputEnabled(false) end
        hook.Run("OnTextEntryLoseFocus", self)
    end

    local function Submit()
        local code = string.Trim(entry:GetValue())
        if code == "" then return end
        P.Redeem(code)
        entry:SetValue("")
        entry:KillFocus()
    end
    entry.OnEnter = Submit
    Btn(function() return "Resgatar código" end, Submit)

    -- ===== Partner =====
    Section("Partner")
    Live(F(20), function()
        if not P.IsPartner(lp) then return "Você não é partner.", ui.dim end

        local exp = lp:GetNWInt("hns_partner_exp", 0)
        if exp > 0 then
            return "Você é partner até " .. os.date("%d/%m/%Y", exp) .. ".", COL_OK
        end
        return "Você é partner.", COL_OK
    end)
    Live(F(17, 500), function()
        local n = P.Num("PtDaily")
        if not P.Toggle("PtDailyOn") or n <= 0 then
            return "Partners podem escolher quando serão o killer.", ui.dim
        end
        return ("Partners ganham %d revives por dia ao entrar no servidor e podem escolher quando serão o killer.")
            :format(n), ui.dim
    end)

    Section("Tag de partner")
    Info("Escolha o texto da sua tag e qual tag aparece quando a exibição de várias tags está desativada.")
    local tagEntry = SherlockHNS.UI.Create("DTextEntry", scroll)
    tagEntry:Dock(TOP)
    tagEntry:DockMargin(0, 0, UU(16), UU(6))
    tagEntry:SetTall(UU(36))
    tagEntry:SetPlaceholderText("Texto da sua tag (vazio para remover)")
    tagEntry:SetMaximumCharCount(SherlockHNS.Tags.MaxText)
    tagEntry:SetValue(lp:GetNWString("hns_partner_tag", ""))
    local tagColor = SherlockHNS.UI.Create("DColorMixer", scroll)
    tagColor:Dock(TOP)
    tagColor:DockMargin(0, 0, UU(16), UU(6))
    tagColor:SetTall(UU(170))
    tagColor:SetPalette(false)
    tagColor:SetAlphaBar(false)
    tagColor:SetWangs(true)
    local initialColor = lp:GetNWVector("hns_partner_tag_color", Vector(1, 200 / 255, 60 / 255))
    tagColor:SetColor(Color(math.floor(initialColor.x * 255), math.floor(initialColor.y * 255), math.floor(initialColor.z * 255)))
    function tagEntry:OnGetFocus()
        local r = RootPopup()
        if IsValid(r) then r:SetKeyboardInputEnabled(true) end
        hook.Run("OnTextEntryGetFocus", self)
    end
    function tagEntry:OnLoseFocus()
        local r = RootPopup()
        if IsValid(r) then r:SetKeyboardInputEnabled(false) end
        hook.Run("OnTextEntryLoseFocus", self)
    end
    local tagChoice = SherlockHNS.UI.Create("DComboBox", scroll)
    tagChoice:Dock(TOP)
    tagChoice:DockMargin(0, 0, UU(16), UU(6))
    tagChoice:SetTall(UU(36))
    local function FillTagChoice()
        if not IsValid(tagChoice) then return end
        tagChoice:Clear()
        local selected = lp:GetNWInt("hns_tag_selected", 0)
        tagChoice:AddChoice("Automática (maior prioridade)", 0, selected == 0)
        for _, tag in ipairs(SherlockHNS.Tags.GetSelectableTags(lp)) do
            tagChoice:AddChoice(tag.text, tag.id, selected == tag.id)
        end
    end
    FillTagChoice()
    hook.Add("SherlockHNS_TagsUpdated", tagChoice, FillTagChoice)
    local chosenTag = lp:GetNWInt("hns_tag_selected", 0)
    tagChoice.OnSelect = function(_, _, _, data) chosenTag = data end
    local displayList = SherlockHNS.UI.Create("DListView", scroll)
    displayList:Dock(TOP)
    displayList:DockMargin(0, 0, UU(16), UU(6))
    displayList:SetTall(UU(120))
    displayList:SetMultiSelect(true)
    displayList:AddColumn("Tags que serão exibidas juntas (Ctrl/⌘ para selecionar várias)")
    local function FillDisplayList()
        if not IsValid(displayList) then return end
        local selected = {}
        for s in string.gmatch(lp:GetNWString("hns_tags_display", ""), "%-?%d+") do selected[tonumber(s)] = true end
        displayList:Clear()
        for _, tag in ipairs(SherlockHNS.Tags.GetSelectableTags(lp)) do
            local line = displayList:AddLine("[" .. tag.text .. "]")
            line.tagId = tag.id
            if selected[tag.id] then displayList:SelectItem(line) end
        end
    end
    FillDisplayList()
    hook.Add("SherlockHNS_TagsUpdated", displayList, FillDisplayList)
    Btn(function() return "Salvar tag" end, function()
        if not P.IsPartner(lp) then return end
        net.Start("sherlockhns_tag_self")
        net.WriteString(tagEntry:GetValue())
        local color = tagColor:GetColor()
        net.WriteUInt(color.r, 8)
        net.WriteUInt(color.g, 8)
        net.WriteUInt(color.b, 8)
        net.WriteInt(chosenTag, 16)
        local ids = {}
        for _, line in ipairs(displayList:GetSelected()) do
            if line.tagId then ids[#ids + 1] = line.tagId end
        end
        net.WriteUInt(math.min(#ids, SherlockHNS.Tags.MaxPerPlayer + 1), 7)
        for i = 1, math.min(#ids, SherlockHNS.Tags.MaxPerPlayer + 1) do net.WriteInt(ids[i], 16) end
        net.SendToServer()
    end, function() return P.IsPartner(lp) end)

    Btn(function()
        if not P.Toggle("PtKillerOn") then return "Fila de killer desativada" end
        if not P.IsPartner(lp) then return "Quero ser killer (só partners)" end
        return P.GetKillerWait(lp) > 0 and "Sair da fila de killer" or "Quero ser killer"
    end, function()
        if P.GetKillerWait(lp) > 0 then P.LeaveQueue() else P.QueueKiller() end
    end, function() return P.IsPartner(lp) and P.Toggle("PtKillerOn") end)

    Live(F(17, 500), function()
        local w = P.GetKillerWait(lp)
        if w <= 0 then return "" end
        if w == 1 then return "Você será o killer na próxima partida.", ui.accent end
        return ("Você será o killer em %d partidas."):format(w), ui.accent
    end)
end
