-- Mutações (cliente): banners de anúncio, filtro do Breu, indicador de velocidade
-- do Bhop, contagem da Killer Rotation e HUD da Infecção.
-- Podem existir várias mutações ativas ao mesmo tempo.
-- Definições: gamemode/sh_mutations.lua

local SH         = SherlockHNS
local M          = SH.Mutation

local COL_ACCENT = Color(180, 136, 0)
local COL_DIM    = Color(190, 190, 190)

local function U(v) return SherlockHNS.UI.Unit(v) end

local function F(size, weight)
    return SherlockHNS.UI.Font(size, weight or 700)
end

local function InPlay(lp)
    if not IsValid(lp) or not lp:Alive() or lp:Team() == TEAM_SPECTATOR then return false end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return false end
    return true
end

-- ============================================================
-- BREU: escurece a tela (brilho/saturação) + vinheta nas bordas
-- ============================================================
-- Breu: os lightmaps precisam ser recarregados quando o lightstyle muda
local function RedownloadLightmaps()
    timer.Simple(0.2, function() render.RedownloadAllLightmaps() end)
end

net.Receive("sherlockhns_breu_refresh", RedownloadLightmaps)

-- quem entra com o Breu já ativo
hook.Add("InitPostEntity", "SherlockHNS_Mutation_BreuJoin", function()
    if M.Is("breu") then RedownloadLightmaps() end
end)

-- ============================================================
-- HUD
-- ============================================================
local banners = {} -- [id] = momento em que a mutação apareceu
local shownSpeed = 0
local BANNER_TIME = 5

local infectFlash = -10
local lastTeam

-- Retorna true se desenhou (para empilhar os banners sem buracos)
local function DrawBanner(def, now, slot)
    local t = now - banners[def.id]
    if t > BANNER_TIME then return false end

    local a = math.min(1, t / 0.4) * math.min(1, (BANNER_TIME - t) / 1)
    local x, y = ScrW() / 2, SherlockHNS.UI.HUDY("mutation") + slot * U(140)

    if y + U(125) > ScrH() - U(250) then return false end
    draw.SimpleText("MUTAÇÃO", F(18), x, y, ColorAlpha(COL_ACCENT, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw.SimpleText(SherlockHNS.UI.Fit(def.name, F(64), ScrW() - 32), F(64), x, y + U(22),
        ColorAlpha(color_white, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw.SimpleText(SherlockHNS.UI.Fit(def.desc, F(20, 500), ScrW() - 32), F(20, 500), x, y + U(98),
        ColorAlpha(COL_DIM, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    return true
end

local function DrawBhop(lp)
    if lp:GetMoveType() ~= MOVETYPE_WALK then return end

    local max = math.max(1, M.Cfg("BhopMaxSpeed", 1100))
    shownSpeed = Lerp(math.min(1, FrameTime() * 12), shownSpeed, lp:GetVelocity():Length2D())

    local frac = math.Clamp(shownSpeed / max, 0, 1)
    local col = HSVToColor(120 * (1 - frac), 0.75, 1) -- verde -> vermelho
    local x, y = ScrW() / 2, ScrH() - U(250)

    draw.SimpleTextOutlined(tostring(math.Round(shownSpeed)), F(52), x, y, col,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("u/s", F(16), x, y + U(34), COL_DIM,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

    local bw, bh = U(320), U(8)
    local bx, by = x - bw / 2, y + U(54)
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(bx - 2, by - 2, bw + 4, bh + 4)
    surface.SetDrawColor(col)
    surface.DrawRect(bx, by, bw * frac, bh)
end

local function DrawRotation(now)
    if GetGlobalInt("sherlockhns_state", ROUND_WAITING) ~= ROUND_ACTIVE then return end

    local at = GetGlobalFloat("sherlockhns_mut_rot_at", 0)
    if at <= 0 then return end

    local left = math.max(0, at - now)
    local total = math.max(1, M.Cfg("RotationInterval", 60))
    local warn = left <= 3
    local col = warn and Color(255, 70, 70, 170 + 85 * math.sin(now * 14)) or color_white

    local x, y = ScrW() / 2, SherlockHNS.UI.HUDY("status")
    draw.SimpleTextOutlined(("Troca de killer em %.1fs"):format(left), F(22), x, y, col,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)

    local bw, bh = U(260), U(5)
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(x - bw / 2 - 2, y + U(30) - 2, bw + 4, bh + 4)
    surface.SetDrawColor(warn and 255 or COL_ACCENT.r, warn and 70 or COL_ACCENT.g, warn and 70 or COL_ACCENT.b, 255)
    surface.DrawRect(x - bw / 2, y + U(30), bw * math.Clamp(left / total, 0, 1), bh)
end

local function DrawInfection()
    local n = 0
    for _, p in ipairs(team.GetPlayers(TEAM_HIDERS)) do
        if p:Alive() then n = n + 1 end
    end

    draw.SimpleTextOutlined("Runners restantes: " .. n, F(22), ScrW() / 2, SherlockHNS.UI.HUDY("status") + U(38),
        Color(120, 255, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end

local COL_CHIP_BG = Color(15, 15, 20)

-- Chip fixo no canto: uma linha por mutação ativa
local function DrawChip(def, index, now)
    local p = math.Clamp((now - (banners[def.id] or now)) / 0.35, 0, 1)
    local e = 1 - (1 - p) ^ 3 -- ease-out

    local h, gap, pad = U(34), U(8), U(12)
    local dot = U(8)
    local tagFont, nameFont = F(12), F(18)

    local name = SherlockHNS.UI.Fit(def.name, nameFont, U(220))

    surface.SetFont(tagFont)
    local tagW = surface.GetTextSize("MUTAÇÃO")
    surface.SetFont(nameFont)
    local nameW = surface.GetTextSize(name)

    local w = pad + dot + U(10) + tagW + U(12) + nameW + pad
    local baseX = U(24)
    local x = baseX - (1 - e) * (w + baseX)
    local y = U(24) + (index - 1) * (h + gap)
    local cy = y + h / 2

    -- fundo + borda + barra de destaque
    draw.RoundedBox(U(8), x, y, w, h, ColorAlpha(COL_CHIP_BG, 215 * e))
    surface.SetDrawColor(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 70 * e)
    surface.DrawOutlinedRect(x, y, w, h, 1)
    surface.SetDrawColor(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 255 * e)
    surface.DrawRect(x, y + U(6), U(3), h - U(12))

    -- ponto pulsante
    local pulse = 0.55 + 0.45 * math.sin(now * 4 + index)
    draw.RoundedBox(dot / 2, x + pad, cy - dot / 2, dot, dot,
        ColorAlpha(COL_ACCENT, 255 * pulse * e))

    -- tag + divisor + nome
    local tx = x + pad + dot + U(10)
    draw.SimpleText("MUTAÇÃO", tagFont, tx, cy, ColorAlpha(COL_ACCENT, 255 * e),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    surface.SetDrawColor(255, 255, 255, 40 * e)
    surface.DrawRect(tx + tagW + U(6), y + U(8), 1, h - U(16))

    draw.SimpleText(name, nameFont, tx + tagW + U(12), cy, ColorAlpha(color_white, 255 * e),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaint", "SherlockHNS_Mutation_HUD", function()
    local now = CurTime()
    local lp = LocalPlayer()
    local active = M.GetActive()

    -- detecta mutações novas (anúncio + som), mesmo com o menu aberto
    local isActive, fresh = {}, false
    for _, id in ipairs(active) do
        isActive[id] = true
        if not banners[id] then
            banners[id] = now
            fresh = true
        end
    end
    for id in pairs(banners) do
        if not isActive[id] then banners[id] = nil end
    end
    if fresh then surface.PlaySound("ambient/alarms/warningbell1.wav") end

    -- Infecção: flash verde e som quando o próprio player é infectado
    local myTeam = IsValid(lp) and lp:Team() or nil
    if M.Is("infection") and lastTeam == TEAM_HIDERS and myTeam == TEAM_KILLERS then
        infectFlash = now
        surface.PlaySound("npc/zombie/zombie_pain" .. math.random(1, 6) .. ".wav")
    end
    lastTeam = myTeam

    if #active == 0 or not IsValid(lp) then return end
    if not SherlockHNS.UI.GameplayVisible() then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local slot = 0
    for _, id in ipairs(active) do
        if DrawBanner(M.ById[id], now, slot) then slot = slot + 1 end
    end

    -- etiquetas fixas no canto (uma por mutação)
    for i, id in ipairs(active) do
        DrawChip(M.ById[id], i, now)
    end

    local flash = 1 - (now - infectFlash) / 1.2
    if flash > 0 then
        surface.SetDrawColor(60, 255, 100, 110 * flash)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end

    if not lp:Alive() then return end

    if isActive.bhop then DrawBhop(lp) end
    if isActive.rotation then DrawRotation(now) end
    if isActive.infection then DrawInfection() end
end)
