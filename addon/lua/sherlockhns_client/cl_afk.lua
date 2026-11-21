-- AFK (cliente): aviso no menu, HUD/teclas da votação de killer e ping de atividade.
-- Shared: sh_afk.lua | Servidor: sv_afk.lua | Painel: cl_admin_afk.lua

local SH        = SherlockHNS
local AFK       = SH.Afk

local COL_WARN  = Color(255, 170, 60)
local COL_DIM   = Color(190, 190, 190)
local COL_PANEL = Color(15, 15, 20, 235)
local COL_YES   = Color(90, 220, 120)
local COL_NO    = Color(230, 80, 80)

local function U(v) return SH.UI.Unit(v) end

local fonts = {}
local function F(size, weight)
    size, weight = math.max(8, U(size)), weight or 700
    local name = "SherlockHNS_Afk_" .. size .. "_" .. weight
    if not fonts[name] then
        surface.CreateFont(name, { font = "Tahoma", size = size, weight = weight, antialias = true, extended = true })
        fonts[name] = true
    end
    return name
end

-- ============================================================
-- Ping: com o cursor liberado (menu, painéis) o usercmd não vê o mouse
-- ============================================================
local lx, ly, nextPing = 0, 0, 0

hook.Add("Think", "SherlockHNS_AfkPing", function()
    if not vgui.CursorVisible() then return end

    local x, y = input.GetCursorPos()
    if x == lx and y == ly then return end
    lx, ly = x, y

    if CurTime() < nextPing then return end
    nextPing = CurTime() + 3

    net.Start("sherlockhns_afk_ping")
    net.SendToServer()
end)

-- ============================================================
-- Aviso no menu (cl_menu.lua chama AFK.DrawNotice no Paint)
-- ============================================================
function AFK.DrawNotice(x, y, w, h)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local at = lp:GetNWFloat("hns_afk_at", 0)
    if at <= 0 or SH.GetMode(lp) == PMODE_PLAY then return end

    local idle = lp:GetNWInt("hns_afk_idle", 0)
    local away = math.max(0, CurTime() - at)
    local pad  = U(18)

    draw.RoundedBox(U(10), x, y, w, h, COL_PANEL)
    surface.SetDrawColor(COL_WARN.r, COL_WARN.g, COL_WARN.b, 90)
    surface.DrawOutlinedRect(x, y, w, h, 1)
    surface.SetDrawColor(COL_WARN)
    surface.DrawRect(x, y + U(10), U(4), h - U(20))

    draw.SimpleText("VOCÊ FICOU AFK", F(15), x + pad, y + U(8), COL_WARN)

    local l2
    if lp:GetNWBool("hns_afk_by_admin", false) then
        l2 = ("Um admin te moveu ao menu. Está aqui há %s."):format(AFK.Format(away))
    elseif idle <= 0 then
        l2 = ("Você se marcou como AFK. Está no menu há %s."):format(AFK.Format(away))
    else
        l2 = ("Ficou parado por %s e foi movido ao menu. Está aqui há %s."):format(AFK.Format(idle), AFK.Format(away))
    end
    draw.SimpleText(SH.UI.Fit(l2, F(17, 500), w - pad * 2), F(17, 500), x + pad, y + U(28), color_white)

    if lp:GetNWBool("hns_afk_killer", false) then
        draw.SimpleText(SH.UI.Fit("Você era killer: outro jogador assume o seu lugar.", F(15, 500), w - pad * 2),
            F(15, 500), x + pad, y + U(50), COL_DIM)
    else
        draw.SimpleText(SH.UI.Fit("Clique em Jogar para voltar à partida.", F(15, 500), w - pad * 2),
            F(15, 500), x + pad, y + U(50), COL_DIM)
    end
end

-- ============================================================
-- Votação de novo killer
-- ============================================================
local vote -- { name, endAt, total, answer = nil | true | false }

net.Receive("sherlockhns_afk_vote_open", function()
    local secs, name = net.ReadUInt(8), net.ReadString()
    local now = CurTime()
    vote = { name = name, endAt = now + secs, total = secs }
    surface.PlaySound("buttons/blip1.wav")
end)

net.Receive("sherlockhns_afk_vote_close", function() vote = nil end)

local K = SH.Keys

local function Answer(yes)
    if not vote then return end
    vote.answer = yes
    surface.PlaySound("ui/buttonclick.wav")
    net.Start("sherlockhns_afk_vote_answer")
    net.WriteBool(yes)
    net.SendToServer()
end

K.On("afk_yes", function() Answer(true) end)
K.On("afk_no", function() Answer(false) end)

K.On("afk_self", function()
    net.Start("sherlockhns_afk_self")
    net.SendToServer()
end)

hook.Add("HUDPaint", "SherlockHNS_AfkVoteHUD", function()
    if not vote then return end

    local now = CurTime()
    if now >= vote.endAt then
        vote = nil
        return
    end
    if not SH.UI.GameplayVisible() then return end

    local w, h = math.min(U(390), ScrW() - 32), U(112)
    local x, y = ScrW() - w - U(24), math.floor(ScrH() * 0.5 - h / 2)

    draw.RoundedBox(U(10), x, y, w, h, COL_PANEL)
    surface.SetDrawColor(COL_WARN)
    surface.DrawRect(x, y + U(12), U(4), h - U(24))

    local pad = U(20)
    draw.SimpleText("KILLER AFK", F(14), x + pad, y + U(10), COL_WARN)
    draw.SimpleText(SH.UI.Fit(vote.name .. " ficou AFK. Quem quer ser o novo killer?", F(16, 500), w - pad * 2),
        F(16, 500), x + pad, y + U(28), color_white)

    local kYes, kNo = K.Name("afk_yes"), K.Name("afk_no")
    local status, col = "[" .. kYes .. "] Eu quero     [" .. kNo .. "] Não quero", color_white
    if vote.answer == true then
        status, col = "Você se candidatou", COL_YES
    elseif vote.answer == false then
        status, col = "Você recusou", COL_NO
    end
    draw.SimpleText(SH.UI.Fit(status, F(16), w - pad * 2), F(16), x + pad, y + U(56), col)

    local left = math.max(0, vote.endAt - now)
    local frac = math.Clamp(left / math.max(1, vote.total), 0, 1)
    surface.SetDrawColor(255, 255, 255, 25)
    surface.DrawRect(x + pad, y + h - U(18), w - pad * 2, U(4))
    surface.SetDrawColor(COL_WARN)
    surface.DrawRect(x + pad, y + h - U(18), (w - pad * 2) * frac, U(4))
    draw.SimpleText(math.ceil(left) .. "s", F(13), x + w - pad, y + U(10), COL_DIM, TEXT_ALIGN_RIGHT)
end)
