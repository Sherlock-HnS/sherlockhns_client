-- Sistema de Party (cliente): toasts de convite, HUD da party, aura dos amigos
-- e a aba "Party" do menu (usada por cl_menu.lua).
-- Servidor: gamemode/sv_party.lua | Shared: gamemode/sh_party.lua

local SH          = SherlockHNS
local P           = SH.Party
local ACT         = P.ACT

local COL_ACCENT  = Color(180, 136, 0)
local COL_DIM     = Color(190, 190, 190)
local COL_PANEL   = Color(15, 15, 20, 235)
local COL_ALIVE   = Color(90, 220, 120)
local COL_DEAD    = Color(230, 80, 80)
local COL_AURA    = Color(90, 255, 140)

local cvPartyAura = CreateClientConVar("hns_party_aura", "1", true, false,
    "Mostra a aura dos amigos da party (0/1).", 0, 1)

local function U(v) return SherlockHNS.UI.Unit(v) end

local function Font(size, weight)
    return SherlockHNS.UI.Font(size, weight or 700)
end

-- ===== Envio =====
local function Send(act, fn)
    net.Start("sherlockhns_party_action")
    net.WriteUInt(act, 4)
    if fn then fn() end
    net.SendToServer()
end

function P.Create(public) Send(ACT.CREATE, function() net.WriteBool(public) end) end

function P.Leave() Send(ACT.LEAVE) end

function P.Join(id) Send(ACT.JOIN, function() net.WriteUInt(id, 16) end) end

function P.Invite(ply) Send(ACT.INVITE, function() net.WriteEntity(ply) end) end

function P.Kick(ply) Send(ACT.KICK, function() net.WriteEntity(ply) end) end

function P.SetPublic(v) Send(ACT.PUBLIC, function() net.WriteBool(v) end) end

-- ===== Consulta =====
-- Texto e cor do estado de um membro
function P.Status(p)
    if not IsValid(p) then return "?", COL_DIM end
    if SH.IsInMenu(p) then return "No menu", COL_DIM end
    if SH.GetMode(p) == PMODE_SPEC or p:Team() == TEAM_SPECTATOR then return "Espectando", COL_DIM end
    if p:Alive() then return "Vivo", COL_ALIVE end
    return "Morto", COL_DEAD
end

-- Parties públicas: { { id, name, count } }
function P.PublicParties()
    local counts, out = {}, {}
    for _, p in ipairs(player.GetAll()) do
        local id = P.GetId(p)
        if id > 0 then counts[id] = (counts[id] or 0) + 1 end
    end
    for _, p in ipairs(player.GetAll()) do
        local id = P.GetId(p)
        if id > 0 and p:GetNWBool("hns_party_leader", false) and p:GetNWBool("hns_party_public", false) then
            out[#out + 1] = { id = id, name = p:Nick(), count = counts[id] or 1 }
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- ============================================================
-- NOTIFICAÇÃO DE CONVITE
-- Desenhada em DrawOverlay (depois de todos os painéis), então aparece
-- por cima do menu (F2) e do jogo. Aceita com F3, recusa com F4.
-- ============================================================
local toasts = {} -- { from, name, id, public, born, expires, total }
P.Invites = toasts

function P.AcceptInvite(t)
    table.RemoveByValue(toasts, t)
    Send(ACT.ACCEPT, function() net.WriteUInt(t.id, 16) end)
end

function P.DeclineInvite(t)
    table.RemoveByValue(toasts, t)
    Send(ACT.DECLINE, function() net.WriteUInt(t.id, 16) end)
end

net.Receive("sherlockhns_party_invite", function()
    local from   = net.ReadEntity()
    local id     = net.ReadUInt(16)
    local public = net.ReadBool()
    local secs   = net.ReadUInt(8)

    -- convite repetido da mesma party só renova o tempo
    for i = #toasts, 1, -1 do
        if toasts[i].id == id then table.remove(toasts, i) end
    end

    local now = CurTime()
    toasts[#toasts + 1] = {
        from    = from,
        name    = IsValid(from) and from:Nick() or "Alguém",
        id      = id,
        public  = public,
        born    = now,
        expires = now + secs,
        total   = secs,
    }
    surface.PlaySound("friends/message.wav")
end)

local K = SherlockHNS.Keys
K.On("party_accept", function() if toasts[1] then P.AcceptInvite(toasts[1]) end end)
K.On("party_decline", function() if toasts[1] then P.DeclineInvite(toasts[1]) end end)

hook.Add("DrawOverlay", "SherlockHNS_PartyToasts", function()
    if #toasts == 0 then return end

    local now = CurTime()
    for i = #toasts, 1, -1 do
        if toasts[i].expires <= now then table.remove(toasts, i) end
    end

    local w, h, gap = U(350), U(100), U(10)
    local kAccept, kDecline = K.Name("party_accept"), K.Name("party_decline")

    for i, t in ipairs(toasts) do
        -- entra deslizando da direita (ease-out)
        local p = math.min(1, (now - t.born) / 0.3)
        local e = 1 - (1 - p) ^ 3
        local x = ScrW() - w - U(24) + (1 - e) * (w + U(40))
        local y = U(120) + (i - 1) * (h + gap)

        draw.RoundedBox(U(10), x, y, w, h, COL_PANEL)
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(x, y + U(12), U(4), h - U(24))

        draw.SimpleText("CONVITE DE PARTY", Font(14), x + U(20), y + U(12), COL_ACCENT)
        draw.SimpleText(t.name, Font(24), x + U(20), y + U(30), color_white)
        draw.SimpleText(t.public and "Party pública" or "Party privada", Font(15, 500),
            x + U(20), y + U(58), COL_DIM)
        draw.SimpleText("[" .. kAccept .. "] Aceitar     [" .. kDecline .. "] Recusar", Font(15),
            x + w - U(16), y + U(58), color_white, TEXT_ALIGN_RIGHT)

        -- barra do tempo restante
        local frac = math.Clamp((t.expires - now) / t.total, 0, 1)
        surface.SetDrawColor(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 210)
        surface.DrawRect(x + U(12), y + h - U(8), (w - U(24)) * frac, U(3))
    end
end)



-- Para quem quiser outras teclas: bind <tecla> hns_party_accept
concommand.Add("hns_party_accept", function() if toasts[1] then P.AcceptInvite(toasts[1]) end end)
concommand.Add("hns_party_decline", function() if toasts[1] then P.DeclineInvite(toasts[1]) end end)

-- ============================================================
-- HUD da party (vivo/morto dos amigos)
-- ============================================================
hook.Add("HUDPaint", "SherlockHNS_PartyHUD", function()
    if not SherlockHNS.UI.GameplayVisible() then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local lp = LocalPlayer()
    local id = P.GetId(lp)
    if id == 0 then return end

    local others = {}
    for _, m in ipairs(P.GetMembers(id)) do
        if m ~= lp then others[#others + 1] = m end
    end
    if #others == 0 then return end

    local x, y = U(24), math.floor(ScrH() * 0.32)
    local w, rh = U(220), U(30)

    draw.SimpleText("PARTY", Font(14), x, y, COL_ACCENT)
    y = y + U(20)

    local limit = math.max(1, math.floor((ScrH() - y - U(240)) / rh))
    for index, m in ipairs(others) do
        if index > limit then break end
        local txt, col = P.Status(m)
        draw.RoundedBox(U(6), x, y, w, rh - U(4), Color(15, 15, 20, 200))
        draw.RoundedBox(U(4), x + U(8), y + (rh - U(4)) / 2 - U(4), U(8), U(8), col)

        local name = m:Nick()
        if utf8.len(name) and utf8.len(name) > 14 then
            name = string.sub(name, 1, utf8.offset(name, 15) - 1) .. "…"
        end
        surface.SetFont(Font(14))
        local statusWidth = surface.GetTextSize(txt)
        name = SherlockHNS.UI.Fit(name, Font(16), w - U(44) - statusWidth)
        draw.SimpleText(name, Font(16), x + U(24), y + (rh - U(4)) / 2, color_white,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(txt, Font(14), x + w - U(10), y + (rh - U(4)) / 2, col,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        y = y + rh
    end
end)

-- ============================================================
-- Aura dos amigos: só entre runners, vivos, durante a rodada.
-- (killers não ganham aura entre si, para não desbalancear)
-- Se a aura geral estiver ligada, ela já mostra todo mundo.
-- ============================================================
hook.Add("PreDrawHalos", "SherlockHNS_PartyAura", function()
    if not cvPartyAura:GetBool() then return end
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:Team() ~= TEAM_HIDERS then return end
    if P.GetId(lp) == 0 then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local state = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
    if state ~= ROUND_PREP and not SH.IsLive(state) then return end
    if SH.AuraActive and SH.AuraActive() then return end

    local list = {}
    for _, m in ipairs(P.GetMembers(P.GetId(lp))) do
        if m ~= lp and m:Alive() and m:Team() == TEAM_HIDERS and SH.BodyEnts then
            SH.BodyEnts(m, list)
        end
    end

    if #list > 0 then halo.Add(list, COL_AURA, 2, 2, 2, true, true) end
end)

-- ============================================================
-- Aba "Party" do menu: cl_menu.lua chama P.BuildTab(parent, ui)
-- ui = { U = fn, F = fn(size, weight), accent = Color, dim = Color }
-- ============================================================
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
        l:DockMargin(0, 0, 0, UU(6))
        l:SetTall(UU(26))
        l:SetFont(F(17, 500))
        l:SetTextColor(ui.dim)
        l:SetText(text)
    end

    local function Btn(text, fn)
        local b = SherlockHNS.UI.Create("DButton", scroll)
        b:Dock(TOP)
        b:DockMargin(0, 0, UU(16), UU(6))
        b:SetTall(UU(42))
        b:SetFont(F(18))
        b:SetText(text)
        b.DoClick = fn
    end

    -- leftFn() -> texto, estado (opcional), cor do estado
    -- buttons = { { label, fn, enabled } }  (o primeiro fica mais à direita)
    local function Row(leftFn, buttons)
        local row = SherlockHNS.UI.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(UU(44))
        row:DockMargin(0, 0, UU(16), UU(6))

        local bw = UU(116)
        for _, def in ipairs(buttons or {}) do
            local b = SherlockHNS.UI.Create("DButton", row)
            b:Dock(RIGHT)
            b:DockMargin(UU(6), UU(6), UU(6), UU(6))
            b:SetWide(bw)
            b:SetFont(F(16))
            b:SetText(def[1])
            b:SetEnabled(def[3] ~= false)
            b.DoClick = def[2]
        end
        local used = #(buttons or {}) * (bw + UU(12))

        function row:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(255, 255, 255, 10))
            local left, right, col = leftFn()
            draw.SimpleText(left, F(18), UU(14), h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if right then
                draw.SimpleText(right, F(16), w - used - UU(14), h / 2, col or ui.dim,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    local function Rebuild()
        scroll:Clear()
        local id = P.GetId(lp)

        if id == 0 then
            Section("Sua party")
            Info("Você não está em uma party.")
            Btn("Criar party pública", function() P.Create(true) end)
            Btn("Criar party privada", function() P.Create(false) end)

            if #toasts > 0 then
                Section("Convites recebidos")
                for _, t in ipairs(toasts) do
                    Row(function() return t.name, t.public and "pública" or "privada" end, {
                        { "Aceitar", function() P.AcceptInvite(t) end },
                        { "Recusar", function() P.DeclineInvite(t) end },
                    })
                end
            end

            Section("Parties públicas")
            local list = P.PublicParties()
            if #list == 0 then Info("Nenhuma party pública no momento.") end
            for _, e in ipairs(list) do
                Row(function() return "Party de " .. e.name, e.count .. "/" .. P.MaxMembers end, {
                    { "Entrar", function() P.Join(e.id) end, e.count < P.MaxMembers },
                })
            end
            return
        end

        local members   = P.GetMembers(id)
        local leader    = members[1]
        local iAmLeader = lp:GetNWBool("hns_party_leader", false)
        local public    = lp:GetNWBool("hns_party_public", false)
        local full      = #members >= P.MaxMembers

        Section(("Party de %s  -  %d/%d  -  %s"):format(
            IsValid(leader) and leader:Nick() or "?", #members, P.MaxMembers,
            public and "pública" or "privada"))

        for _, m in ipairs(members) do
            Row(function()
                if not IsValid(m) then return "?" end
                local txt, col = P.Status(m)
                return (m == leader and "★ " or "") .. m:Nick() .. (m == lp and "  (você)" or ""), txt, col
            end, (iAmLeader and m ~= lp) and { { "Expulsar", function() P.Kick(m) end } } or nil)
        end

        if iAmLeader then
            Btn(public and "Tornar a party privada" or "Tornar a party pública", function()
                P.SetPublic(not public)
            end)
        end

        Section("Convidar jogadores")
        if iAmLeader or public then
            local any = false
            local players = player.GetAll()
            table.sort(players, function(a, b) return a:Nick():lower() < b:Nick():lower() end)
            for _, p in ipairs(players) do
                if p ~= lp and P.GetId(p) == 0 then
                    any = true
                    Row(function() return IsValid(p) and p:Nick() or "?" end, {
                        { "Convidar", function() P.Invite(p) end, not full },
                    })
                end
            end
            if not any then Info("Ninguém disponível para convidar.") end
        else
            Info("Em party privada só o líder convida.")
        end

        Section("")
        Btn("Sair da party", function() P.Leave() end)
    end

    -- Reconstrói só quando algo muda (party de alguém, convites, jogadores)
    local function Signature()
        local parts = { #toasts }
        for _, t in ipairs(toasts) do parts[#parts + 1] = t.id end
        for _, p in ipairs(player.GetAll()) do
            parts[#parts + 1] = p:UserID() .. ":" .. P.GetId(p)
                .. (p:GetNWBool("hns_party_leader", false) and "L" or "")
                .. (p:GetNWBool("hns_party_public", false) and "P" or "")
        end
        return table.concat(parts, "|")
    end

    local lastSig, nextCheck = nil, 0
    function scroll:Think()
        if CurTime() < nextCheck then return end
        nextCheck = CurTime() + 0.4

        local sig = Signature()
        if sig ~= lastSig then
            lastSig = sig
            Rebuild()
        end
    end
end
