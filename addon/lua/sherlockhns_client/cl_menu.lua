-- Tela inicial (cliente): menu sem janela, fundo por câmera do mapa ou imagem.
-- Servidor: gamemode/sv_menu.lua | Shared: gamemode/sh_menu.lua

local SH          = SherlockHNS

local panel, content
local activeTab
local rankData, rankBody
local closedUntil = 0

local COL_ACCENT  = Color(180, 136, 0)
local COL_DIM     = Color(190, 190, 190)
local COL_PANEL   = Color(15, 15, 20, 245)

-- Escurecimento (0-255)
local DIM_FULL    = 225 -- fundo = mundo (câmera do mapa) e overlay do F2
local DIM_IMAGE   = 110 -- fundo = imagem (menu_bg.png)
local SHADE_ALPHA = 200 -- sombra extra na lateral esquerda, atrás dos botões

-- ===== Helpers =====
local function U(v)
    return SherlockHNS.UI.Unit(v)
end

local function F(size, weight)
    return SherlockHNS.UI.Font(size, weight or 700)
end

function SH.IsMenuOpen()
    return IsValid(panel)
end

local function SendAction(act)
    net.Start("sherlockhns_menu_action")
    net.WriteUInt(act, 2)
    net.SendToServer()
end

local function CloseMenu()
    if IsValid(panel) then panel:Remove() end
    panel, content, rankBody, activeTab = nil, nil, nil, nil
end

-- Fecha e não deixa o watcher reabrir enquanto o servidor confirma o novo modo
local function CloseAfterAction()
    closedUntil = CurTime() + 3
    CloseMenu()
end

-- Integração opcional com o addon Sherlock Outfitter.
-- O painel principal é criado dentro do container de conteúdo do menu.
local function OpenOutfitter(parent)
    local addon = rawget(_G, "outfitter")
    if not istable(addon) or not isfunction(addon.GUIOpen) then
        notification.AddLegacy("Outfitter não está carregado.", NOTIFY_ERROR, 5)
        surface.PlaySound("common/warning.wav")
        return
    end

    local gui = addon.GUIOpen(parent)
    if not IsValid(gui) then return end

    gui.hns_onclose = function()
        activeTab = nil
        if IsValid(content) then content:SetVisible(false) end
    end
end

-- ===== Ranking =====
net.Receive("sherlockhns_rank_sync", function()
    local data = { rows = {} }
    for i = 1, net.ReadUInt(8) do
        data.rows[i] = {
            name   = net.ReadString(),
            score  = net.ReadUInt(32),
            wins   = net.ReadUInt(32),
            kills  = net.ReadUInt(32),
            rounds = net.ReadUInt(32),
            me     = net.ReadBool(),
        }
    end
    data.myPos   = net.ReadUInt(16)
    data.myScore = net.ReadUInt(32)

    rankData     = data
    if IsValid(rankBody) and rankBody.Fill then rankBody:Fill() end
end)

local function RankCols(w)
    local colw = math.min(U(125), w * 0.14)
    local rounds = w - U(8)
    return { rounds = rounds, kills = rounds - colw, wins = rounds - colw * 2, pts = rounds - colw * 3 }
end

local function BuildRank(parent)
    local info = SherlockHNS.UI.Create("DLabel", parent)
    info:Dock(TOP)
    info:SetTall(U(26))
    info:DockMargin(0, 0, 0, U(14))
    info:SetFont(F(18))
    info:SetTextColor(COL_DIM)
    info:SetText("Carregando...")

    local header = SherlockHNS.UI.Create("DPanel", parent)
    header:Dock(TOP)
    header:SetTall(U(30))
    header:DockMargin(0, 0, U(16), U(6))
    function header:Paint(w, h)
        local c = RankCols(w)
        draw.SimpleText("#", F(15), U(14), h / 2, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Jogador", F(15), U(80), h / 2, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Pontos", F(15), c.pts, h / 2, COL_ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Vitórias", F(15), c.wins, h / 2, COL_ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Kills", F(15), c.kills, h / 2, COL_ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Rodadas", F(15), c.rounds, h / 2, COL_ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local scroll = SherlockHNS.UI.Create("DScrollPanel", parent)
    scroll:Dock(FILL)
    rankBody = scroll

    function scroll:Fill()
        self:Clear()

        local d = rankData
        if not d then return end

        if d.myPos > 0 then
            info:SetText(("Sua posição: #%d  -  %d pontos   (vitória x10, sobrevivência x5, kill x2)")
                :format(d.myPos, d.myScore))
        else
            info:SetText("Você ainda não está no ranking. Jogue uma rodada!")
        end

        if #d.rows == 0 then
            local empty = SherlockHNS.UI.Create("DLabel", self)
            empty:Dock(TOP)
            empty:SetTall(U(40))
            empty:SetFont(F(18))
            empty:SetTextColor(COL_DIM)
            empty:SetText("Ninguém pontuou ainda.")
            return
        end

        for i, r in ipairs(d.rows) do
            local name = r.name
            local len = utf8.len(name)
            if len and len > 24 then
                name = string.sub(name, 1, utf8.offset(name, 25) - 1) .. "…"
            end

            local bg = r.me and Color(180, 136, 0, 90)
                or (i % 2 == 0 and Color(255, 255, 255, 10) or Color(255, 255, 255, 4))
            local posCol = (i == 1 and Color(255, 210, 70))
                or (i == 2 and Color(210, 210, 225))
                or (i == 3 and Color(210, 140, 80))
                or color_white

            local row = SherlockHNS.UI.Create("DPanel", self)
            row:Dock(TOP)
            row:SetTall(U(38))
            row:DockMargin(0, 0, 0, U(4))
            function row:Paint(w, h)
                local c = RankCols(w)
                draw.RoundedBox(6, 0, 0, w, h, bg)
                draw.SimpleText("#" .. i, F(18), U(14), h / 2, posCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(SherlockHNS.UI.Fit(name, F(18), c.pts - U(80) - math.min(U(125), w * 0.14)), F(18), U(80),
                    h / 2, r.me and COL_ACCENT or color_white,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(r.score, F(18), c.pts, h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText(r.wins, F(18), c.wins, h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText(r.kills, F(18), c.kills, h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                draw.SimpleText(r.rounds, F(18), c.rounds, h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    net.Start("sherlockhns_rank_request")
    net.SendToServer()

    if rankData then scroll:Fill() end -- mostra o cache enquanto atualiza
end

-- ===== Configurações =====
local function BuildGeneral(scroll)
    local function Check(text, cvar)
        local c = SherlockHNS.UI.Create("DCheckBoxLabel", scroll)
        c:Dock(TOP)
        c:DockMargin(0, 0, U(16), U(14))
        c:SetTall(U(24))
        c:SetFont(F(18))
        c:SetText(text)
        c:SetConVar(cvar)
    end

    local function Slider(text, cvar, min, max, decimals)
        local s = SherlockHNS.UI.Create("DNumSlider", scroll)
        s:Dock(TOP)
        s:DockMargin(0, 0, U(16), U(14))
        s:SetTall(U(30))
        s:SetText(text)
        s:SetMinMax(min, max)
        s:SetDecimals(decimals)
        s:SetConVar(cvar)
    end

    Check("Mostrar a HUD do Sherlock HnS", "hns_hud")
    Check("Mostrar a quantidade de jogadores vivos", "hns_alive_counter")
    Slider("Escala da HUD", "hns_hud_scale", 0.5, 2, 2)
    Check("Mostrar as barreiras anti-loop", "hns_barrier_visible")
    Slider("Distância de exibição das barreiras (0 = sempre)", "hns_barrier_distance", 0, 5000, 0)
    Check("Mostrar nameplates", "hns_nameplate")
    Slider("Volume da música do LMS", "hns_lms_volume", 0, 1, 2)
    Check("Aura por entidade (menos lag; desmarque para usar halo)", "hns_aura_mode_entity")
    Check("Aura dos amigos da party", "hns_party_aura")

    local hint = SherlockHNS.UI.Create("DLabel", scroll)
    hint:Dock(TOP)
    hint:DockMargin(0, U(10), 0, 0)
    hint:SetTall(U(24))
    hint:SetFont(F(16))
    hint:SetTextColor(COL_DIM)
    hint:SetText("As opções são salvas automaticamente. F2 abre este menu durante a partida.")
end

local function BuildSettings(parent)
    local ui = { U = U, F = F, accent = COL_ACCENT, dim = COL_DIM }

    local bar = SherlockHNS.UI.Create("DPanel", parent)
    bar:Dock(TOP)
    bar:SetTall(U(40))
    bar:DockMargin(0, 0, 0, U(12))
    bar.Paint = nil

    local general = SherlockHNS.UI.Create("DScrollPanel", parent)
    general:Dock(FILL)
    BuildGeneral(general)

    local keys = SherlockHNS.UI.Create("DScrollPanel", parent)
    keys:Dock(FILL)
    keys:SetVisible(false)
    SherlockHNS.Keys.BuildPanel(keys, ui)

    local active = general
    local function Switch(panel)
        active = panel
        general:SetVisible(panel == general)
        keys:SetVisible(panel == keys)
    end

    for i, def in ipairs({ { "Geral", general }, { "Teclas", keys } }) do
        local b = SherlockHNS.UI.Create("DButton", bar)
        b:Dock(LEFT)
        b:DockMargin(0, 0, U(8), 0)
        b:SetWide(U(140))
        b:SetFont(F(18))
        b:SetText(def[1])
        b.DoClick = function() Switch(def[2]) end
        function b:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(255, 255, 255, active == def[2] and 25 or 8))
            if active == def[2] then
                surface.SetDrawColor(COL_ACCENT)
                surface.DrawRect(0, h - U(3), w, U(3))
            end
            return false
        end
    end
end

-- ===== Créditos =====
local function BuildCredits(parent)
    local p = SherlockHNS.UI.Create("DPanel", parent)
    p:Dock(FILL)

    function p:Paint(w, h)
        local y = 0
        for _, group in ipairs(SH.Credits or {}) do
            draw.SimpleText(group.title, F(16), 0, y, COL_ACCENT)
            y = y + U(26)
            for _, n in ipairs(group.names) do
                draw.SimpleText(n, F(26), 0, y, color_white)
                y = y + U(36)
            end
            y = y + U(18)
        end

        local site = GAMEMODE and GAMEMODE.Website or ""
        if site ~= "" then
            draw.SimpleText(site, F(16), 0, h - U(24), COL_DIM)
        end
    end
end

-- ===== Regras =====
local function BuildRules(parent)
    local scroll = SherlockHNS.UI.Create("DScrollPanel", parent)
    scroll:Dock(FILL)

    local rules = SH.Rules or {}
    if #rules == 0 then
        local empty = SherlockHNS.UI.Create("DLabel", scroll)
        empty:Dock(TOP)
        empty:SetTall(U(40))
        empty:SetFont(F(18))
        empty:SetTextColor(COL_DIM)
        empty:SetText("Nenhuma regra cadastrada.")
        return
    end

    for i, rule in ipairs(rules) do
        local t = SherlockHNS.UI.Create("DLabel", scroll)
        t:Dock(TOP)
        t:DockMargin(0, i > 1 and U(26) or 0, 0, U(6))
        t:SetTall(U(28))
        t:SetFont(F(22))
        t:SetTextColor(COL_ACCENT)
        t:SetText(i .. ". " .. tostring(rule.title or ""))

        local d = SherlockHNS.UI.Create("DLabel", scroll)
        d:Dock(TOP)
        d:DockMargin(0, 0, U(16), 0)
        d:SetTall(U(24))
        d:SetFont(F(18, 500))
        d:SetTextColor(color_white)
        d:SetWrap(true)
        d:SetAutoStretchVertical(true)
        d:SetText(tostring(rule.text or ""))
    end
end

local TABS = {
    rank     = { title = "Ranking", build = BuildRank },
    rules    = { title = "Regras", build = BuildRules },
    settings = { title = "Configurações", build = BuildSettings },
    credits  = { title = "Créditos", build = BuildCredits },
    party    = {
        title = "Party",
        build = function(p)
            SherlockHNS.Party.BuildTab(p, { U = U, F = F, accent = COL_ACCENT, dim = COL_DIM })
        end
    },
    outfits  = { title = "Outfits", build = OpenOutfitter },
    benefits = {
        title = "Benefícios",
        build = function(p)
            SherlockHNS.Partner.BuildTab(p, { U = U, F = F, accent = COL_ACCENT, dim = COL_DIM, root = panel })
        end
    },
}

local function ShowTab(id)
    if not IsValid(content) then return end

    local same = activeTab == id
    activeTab = (not same) and id or nil
    rankBody = nil
    content:Clear()

    -- Outfitter tem seu próprio título e frame. Remove o espaço reservado
    -- ao cabeçalho do menu para que o DFrame encaixe no container inteiro.
    -- Ao sair da aba, restaura o padding usado pelas demais telas.
    if id == "outfits" then
        content:DockPadding(U(6), U(6), U(6), U(6))
    else
        content:DockPadding(U(40), U(112), U(40), U(36))
    end

    if same then
        content:SetVisible(false)
        return
    end

    local tab = TABS[id]
    content.title = tab.title
    content:SetVisible(true)
    tab.build(content)

    content:SetAlpha(0)
    content:AlphaTo(255, 0.2, 0)
end

-- ===== Menu =====
local bgMat, logoMat

local function DrawShade(h)
    local width = U(820)
    local block = 4 -- colunas inteiras e sem sobreposição (sobrepor gera listras)
    for x = 0, width - 1, block do
        local k = (x + block / 2) / width
        surface.SetDrawColor(5, 5, 10, SHADE_ALPHA * (1 - k) ^ 1.5)
        surface.DrawRect(x, 0, block, h)
    end
end

local function DrawBackground(w, h)
    if GetGlobalBool("hns_menucam_set", false) then return end -- o fundo é o mundo (CalcView)

    if bgMat and not bgMat:IsError() then
        local mw, mh = bgMat:Width(), bgMat:Height()
        local scale = math.max(w / mw, h / mh)
        local dw, dh = mw * scale, mh * scale
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(bgMat)
        surface.DrawTexturedRect((w - dw) / 2, (h - dh) / 2, dw, dh)
    else
        surface.SetDrawColor(10, 10, 16, 255)
        surface.DrawRect(0, 0, w, h)
    end
end

local function OpenMenu()
    if IsValid(panel) then panel:Remove() end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local mode = SH.GetMode(lp)
    local overlay = mode ~= PMODE_MENU

    bgMat = SH.MenuBackground and Material(SH.MenuBackground, "smooth") or nil
    logoMat = SH.MenuLogo and Material(SH.MenuLogo, "smooth mips") or nil
    activeTab, rankBody = nil, nil

    panel = SherlockHNS.UI.Create("EditablePanel")
    panel.hnsOverlay = overlay
    panel:SetPos(0, 0)
    panel:SetSize(ScrW(), ScrH())
    panel:MakePopup()
    panel:SetKeyboardInputEnabled(false) -- mouse livre; as teclas do jogo continuam funcionando

    function panel:Paint(w, h)
        local hasCam = GetGlobalBool("hns_menucam_set", false)
        if not overlay then DrawBackground(w, h) end

        -- o mesmo escurecimento na primeira abertura e no F2
        surface.SetDrawColor(0, 0, 0, (overlay or hasCam) and DIM_FULL or DIM_IMAGE)
        surface.DrawRect(0, 0, w, h)
        DrawShade(h)

        local x = U(90)
        if logoMat and not logoMat:IsError() then
            local lh = U(120)
            local lw = lh * logoMat:Width() / logoMat:Height()
            local maxw = U(460)
            if lw > maxw then
                lh = lh * maxw / lw
                lw = maxw
            end
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(logoMat)
            surface.DrawTexturedRect(x, U(96) + (U(120) - lh) / 2, lw, lh)
        else
            draw.SimpleText("SHERLOCK HNS", F(76), x, U(130), color_white)
        end
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(x, U(222), U(120), U(4))
        draw.SimpleText("HIDE AND SEEK  -  " .. game.GetMap(), F(20), x, U(238), COL_DIM)

        local state = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
        draw.SimpleText((SH.StateNames[state] or "?") .. "  -  " .. #SH.GetParticipants() .. " na partida",
            F(18), x, h - U(74), COL_DIM)
        draw.SimpleText(SH.Keys.Name("menu") .. " abre este menu", F(15), x, h - U(48), COL_DIM)
        if SH.Afk and SH.Afk.DrawNotice then
            local cx = U(620)
            SH.Afk.DrawNotice(cx, U(16), math.min(U(980), ScrW() - cx - U(90)), U(72))
        end
    end

    -- área de conteúdo (rank / configurações / créditos)
    local cx = U(620)
    local cw = math.min(U(980), ScrW() - cx - U(90))
    content = SherlockHNS.UI.Create("DPanel", panel)
    content:SetPos(cx, U(96))
    content:SetSize(cw, ScrH() - U(192))
    content:DockPadding(U(40), U(112), U(40), U(36))
    content:SetVisible(false)
    function content:Paint(w, h)
        draw.RoundedBox(U(12), 0, 0, w, h, COL_PANEL)
        draw.SimpleText(self.title or "", F(34), U(40), U(34), color_white)
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(U(40), U(86), U(60), U(3))
    end

    -- botões
    local items = {}
    local function Add(id, label, fn) items[#items + 1] = { id = id, label = label, fn = fn } end

    if overlay then Add("close", "Continuar", CloseMenu) end
    if mode ~= PMODE_PLAY then
        Add("play", "Jogar", function()
            SendAction(1)
            CloseAfterAction()
        end)
    end
    if mode ~= PMODE_SPEC then
        Add("spec", "Espectar", function()
            SendAction(2)
            CloseAfterAction()
        end)
    end
    Add("rank", "Rank", function() ShowTab("rank") end)
    Add("party", "Party", function() ShowTab("party") end)
    Add("outfits", "Outfits", function() ShowTab("outfits") end)
    Add("benefits", "Benefícios", function() ShowTab("benefits") end)
    Add("rules", "Regras", function() ShowTab("rules") end)
    Add("settings", "Configurações", function() ShowTab("settings") end)
    Add("credits", "Créditos", function() ShowTab("credits") end)
    Add("quit", "Sair do servidor", function() RunConsoleCommand("disconnect") end)

    local bx, by = U(90), U(330)
    local bw, gap = U(460), U(4)
    local bh = math.min(U(56), math.floor((ScrH() - by - U(110)) / #items) - gap)

    for i, it in ipairs(items) do
        local btn = SherlockHNS.UI.Create("DButton", panel)
        btn:SetPos(bx, by + (i - 1) * (bh + gap))
        btn:SetSize(bw, bh)
        btn:SetText("")
        btn.hover = 0

        function btn:Paint(w, h)
            local on = self:IsHovered() or activeTab == it.id
            self.hover = Lerp(FrameTime() * 12, self.hover, on and 1 or 0)
            local a = self.hover

            surface.SetDrawColor(255, 255, 255, 18 * a)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 255 * a)
            surface.DrawRect(0, 0, U(4), h)

            draw.SimpleText(it.label, F(30), U(22) + U(14) * a, h / 2,
                Color(255, 255, 255, 185 + 70 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return true
        end

        function btn:DoClick()
            surface.PlaySound("ui/buttonclickrelease.wav")
            it.fn()
        end
    end
    -- Atalho para a comunidade no Discord.
    local discordSize = U(56)
    local discord = SherlockHNS.UI.Create("DButton", panel)
    discord:SetSize(discordSize, discordSize)
    discord:SetPos(math.max(U(20), ScrW() - discordSize - U(36)), U(36))
    discord:SetText("")
    discord:SetTooltip("Entrar no Discord do Sherlock HnS")
    discord.hover = 0

    local logoScale = discordSize / 32
    function discord:Paint(w, h)
        self.hover = Lerp(FrameTime() * 12, self.hover, self:IsHovered() and 1 or 0)
        local blurple = Color(88, 101, 242)

        draw.RoundedBox(h / 2, 0, 0, w, h, blurple)
        if self.hover > 0 then
            draw.RoundedBox(h / 2, 0, 0, w, h, Color(255, 255, 255, 28 * self.hover))
        end

        -- Silhueta simplificada do símbolo do Discord, sem dependência de fontes externas.
        local cx, cy, s = w / 2, h / 2, logoScale
        draw.RoundedBox(7 * s, cx - 10 * s, cy - 7 * s, 20 * s, 15 * s, color_white)
        draw.RoundedBox(4 * s, cx - 14 * s, cy - 2 * s, 7 * s, 9 * s, color_white)
        draw.RoundedBox(4 * s, cx + 7 * s, cy - 2 * s, 7 * s, 9 * s, color_white)
        draw.RoundedBox(3 * s, cx - 8 * s, cy - 10 * s, 5 * s, 6 * s, color_white)
        draw.RoundedBox(3 * s, cx + 3 * s, cy - 10 * s, 5 * s, 6 * s, color_white)
        draw.RoundedBox(2 * s, cx - 5 * s, cy - 2 * s, 3 * s, 4 * s, blurple)
        draw.RoundedBox(2 * s, cx + 2 * s, cy - 2 * s, 3 * s, 4 * s, blurple)
    end

    function discord:DoClick()
        surface.PlaySound("ui/buttonclickrelease.wav")
        gui.OpenURL("https://discord.gg/EHXbAmpbse")
    end
end

hook.Add("OnScreenSizeChanged", "HNS_MenuViewport", function()
    if not IsValid(panel) then return end
    local selected = activeTab
    OpenMenu()
    if selected then ShowTab(selected) end
end)

-- F2 (servidor manda): abre ou fecha o overlay. Quem está no menu não consegue fechar.
local function ToggleMenu()
    if IsValid(panel) then
        if not SH.IsInMenu(LocalPlayer()) then CloseMenu() end
    else
        OpenMenu()
    end
end

SherlockHNS.Keys.On("menu", ToggleMenu)

-- Atalho de Outfits (padrão: C): abre o menu direto na aba Outfits.
-- Com a aba já aberta, a mesma tecla fecha o overlay (quem está no menu inicial não consegue fechar).
SherlockHNS.Keys.On("outfits", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    if IsValid(panel) then
        if activeTab ~= "outfits" then
            ShowTab("outfits")
        elseif not SH.IsInMenu(lp) then
            CloseMenu()
        end
        return
    end

    -- evita abrir o menu à toa quando o servidor bloqueia troca de outfit
    local addon = rawget(_G, "outfitter")
    if addon and isfunction(addon.IsOutfitChangeBlocked) and addon.IsOutfitChangeBlocked(lp) then
        notification.AddLegacy("Você não pode trocar de outfit durante a partida.", NOTIFY_ERROR, 4)
        surface.PlaySound("common/warning.wav")
        return
    end

    OpenMenu()
    ShowTab("outfits")
end)

net.Receive("sherlockhns_menu_open", ToggleMenu)

-- Para quem quiser outra tecla: bind <tecla> hns_menu
concommand.Add("hns_menu", ToggleMenu)

-- Abre sozinho ao entrar (e reabre se o painel sumir, ex.: refresh de Lua)
timer.Create("SherlockHNS_MenuWatch", 0.5, 0, function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    -- na votação de mapa o menu sai da frente
    if GetGlobalInt("sherlockhns_state", ROUND_WAITING) == ROUND_MAPVOTE then
        if IsValid(panel) then CloseMenu() end
        return
    end

    if IsValid(panel) and not panel.hnsOverlay and not SH.IsInMenu(lp) then
        CloseMenu()
        return
    end
    if IsValid(panel) or CurTime() < closedUntil then return end
    if SH.IsInMenu(lp) then OpenMenu() end
end)

-- Quem está no menu, ou espectando com o overlay aberto, vê a câmera do mapa
local function InMenuView(ply)
    if not IsValid(panel) then return false end
    return SH.IsInMenu(ply) or SH.GetMode(ply) == PMODE_SPEC
end

hook.Add("CalcView", "SherlockHNS_MenuView", function(ply, origin, angles, fov)
    if not InMenuView(ply) then return end
    if not GetGlobalBool("hns_menucam_set", false) then return end

    local t = CurTime()
    local ang = GetGlobalAngle("hns_menucam_ang") + Angle(math.sin(t * 0.3) * 0.6, math.sin(t * 0.21) * 1.2, 0)

    return {
        origin     = GetGlobalVector("hns_menucam_pos"),
        angles     = ang,
        fov        = 75,
        drawviewer = false,
    }
end)

-- Espectador com o overlay aberto não anda nem troca de alvo atrás do painel
hook.Add("StartCommand", "SherlockHNS_MenuSpecLock", function(ply, cmd)
    if ply ~= LocalPlayer() then return end
    if not IsValid(panel) or SH.GetMode(ply) ~= PMODE_SPEC then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
end)

-- ===== Esconde o resto da HUD enquanto o menu está aberto =====
hook.Add("HUDShouldDraw", "SherlockHNS_MenuHideHUD", function(name)
    -- CHudGMod é quem chama o HUDPaint; o chat continua visível
    if IsValid(panel) and name ~= "CHudGMod" and name ~= "CHudChat" then return false end
end)

hook.Add("SherlockHNS_ShouldDrawHUD", "SherlockHNS_MenuHideAbilityHUD", function()
    if IsValid(panel) then return false end
end)

hook.Add("OnTextEntryGetFocus", "HNS_MenuKeyFocusOn", function(pnl)
    if IsValid(panel) and IsValid(pnl) and pnl:HasParent(panel) then
        panel:SetKeyboardInputEnabled(true)
    end
end)

hook.Add("OnTextEntryLoseFocus", "HNS_MenuKeyFocusOff", function(pnl)
    if IsValid(panel) and IsValid(pnl) and pnl:HasParent(panel) then
        panel:SetKeyboardInputEnabled(false)
    end
end)
