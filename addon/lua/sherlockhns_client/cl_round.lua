-- Timer da rodada (cliente): painel no topo com estado, tempo e barra de progresso.
-- Posição: SherlockHNS.UI.HUDY("round"). Cores/fontes: cl_ui.lua.

local SH       = SherlockHNS
local UI       = SH.UI
local C        = UI.Colors

local COL_WARN = Color(255, 80, 70)
local COL_LMS  = Color(255, 200, 60)
local COL_BG   = Color(15, 15, 20, 225)

-- Maiúsculas escritas à mão (string.upper não trata acentos)
local labels   = {
    [ROUND_WAITING]  = "AGUARDANDO JOGADORES",
    [ROUND_PREP]     = "PREPARAÇÃO",
    [ROUND_ACTIVE]   = "EM ANDAMENTO",
    [ROUND_END]      = "FIM DA RODADA",
    [ROUND_LMS]      = "ÚLTIMO RUNNER",
    [ROUND_ROULETTE] = "SORTEIO",
}

-- Duração total de cada estado (para a barra). Fallback: o que restar.
local function TotalFor(state, left)
    local key = ({
        [ROUND_PREP]     = "PrepTime",
        [ROUND_ACTIVE]   = "ActiveTime",
        [ROUND_END]      = "EndTime",
        [ROUND_ROULETTE] = "RouletteTime",
    })[state]

    if key then return math.max(left, GetGlobalInt("sherlockhns_cfg_" .. key, 0)) end
    if state == ROUND_LMS then return math.max(left, SH.LMSTime) end
    return math.max(left, 1)
end

local function Pill(x, y, w, h, border)
    draw.RoundedBox(UI.Unit(10), x, y, w, h, COL_BG)
    surface.SetDrawColor(border.r, border.g, border.b, 90)
    surface.DrawOutlinedRect(x, y, w, h, 1)
end

hook.Add("HUDPaint", "SherlockHnS_RoundHUD", function()
    if not UI.GameplayVisible() then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local U     = UI.Unit
    local now   = CurTime()
    local state = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
    local endAt = GetGlobalFloat("sherlockhns_state_end", 0)
    local left  = math.max(0, endAt - now)
    local total = TotalFor(state, left)
    local label = labels[state] or "?"

    -- espera pós troca de mapa
    local grace = math.max(0, GetGlobalFloat("sherlockhns_grace_end", 0) - now)
    if state == ROUND_WAITING and grace > 0 then
        label, endAt, left = "AGUARDANDO TODOS CARREGAREM", 1, grace
        total = math.max(grace, GetGlobalInt("sherlockhns_cfg_MapChangeDelay", 60))
    end

    local hasTimer = endAt > 0
    local accent   = (state == ROUND_LMS) and COL_LMS or C.accent
    local warn     = hasTimer and left <= 10 and (state == ROUND_ACTIVE or state == ROUND_LMS or state == ROUND_PREP)
    local timeCol  = warn and ColorAlpha(COL_WARN, 190 + 65 * math.sin(now * 10)) or color_white

    local cx       = ScrW() / 2
    local y        = UI.HUDY("round")
    local w        = math.min(U(300), ScrW() - 32)
    local h        = hasTimer and U(70) or U(40)
    local x        = cx - w / 2

    Pill(x, y, w, h, warn and COL_WARN or accent)

    local fLabel = UI.Font(hasTimer and 14 or 18, 800)
    draw.SimpleText(UI.Fit(label, fLabel, w - U(24)), fLabel, cx,
        hasTimer and (y + U(8)) or (y + h / 2), accent,
        TEXT_ALIGN_CENTER, hasTimer and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)

    if hasTimer then
        local secs = math.ceil(left)
        draw.SimpleText(string.format("%d:%02d", math.floor(secs / 60), secs % 60),
            UI.Font(32, 800), cx, y + U(22), timeCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        -- barra de progresso (esvazia conforme o tempo passa)
        local bx, by, bw, bh = x + U(14), y + h - U(10), w - U(28), U(4)
        surface.SetDrawColor(255, 255, 255, 25)
        surface.DrawRect(bx, by, bw, bh)

        local frac = math.Clamp(left / total, 0, 1)
        local bc = warn and COL_WARN or accent
        surface.SetDrawColor(bc.r, bc.g, bc.b, 255)
        surface.DrawRect(bx, by, bw * frac, bh)
    end

    -- linha extra: vencedor ou último runner
    local extra, extraCol
    if state == ROUND_END then
        local win = GetGlobalInt("sherlockhns_winner", 0)
        if win ~= 0 then
            extra, extraCol = "VITÓRIA: " .. string.upper(team.GetName(win)), team.GetColor(win)
        end
    elseif state == ROUND_LMS then
        local last = GetGlobalEntity("sherlockhns_lms_runner")
        if IsValid(last) then extra, extraCol = last:Nick(), COL_LMS end
    end

    if extra then
        local ew, eh = math.min(U(300), ScrW() - 32), U(32)
        local ey = y + h + U(6)
        Pill(cx - ew / 2, ey, ew, eh, extraCol)

        local f = UI.Font(18, 800)
        draw.SimpleText(UI.Fit(extra, f, ew - U(24)), f, cx, ey + eh / 2,
            extraCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Killers' health is visible to runners as a shared status bar.
    if (state == ROUND_ACTIVE or state == ROUND_LMS) and LocalPlayer():Team() == TEAM_HIDERS then
        local killers = team.GetPlayers(TEAM_KILLERS)
        local shown, totalHealth, totalMax = 0, 0, 0
        for _, killer in ipairs(killers) do
            if IsValid(killer) and killer:Alive() then
                shown = shown + 1
                totalHealth = totalHealth + math.max(0, killer:Health())
                totalMax = totalMax + math.max(1, killer:GetMaxHealth())
            end
        end
        if shown > 0 then
            local bw, bh = math.min(U(280), ScrW() - 32), U(26)
            local bx, by = cx - bw / 2, y + h + U(extra and 44 or 6)
            local col = GetGlobalEntity("sherlockhns_juggernaut")
            local isJugger = IsValid(col) and col:Team() == TEAM_KILLERS and col:Alive()
            local accentCol = isJugger and COL_WARN or Color(210, 65, 65)
            Pill(bx, by, bw, bh, accentCol)
            local frac = math.Clamp(totalHealth / totalMax, 0, 1)
            surface.SetDrawColor(accentCol.r, accentCol.g, accentCol.b, 230)
            surface.DrawRect(bx + U(4), by + U(4), (bw - U(8)) * frac, bh - U(8))
            local label = isJugger and "JUGGERNAUT" or (shown == 1 and "VIDA DO KILLER" or "VIDA DOS KILLERS")
            draw.SimpleText(label .. "  " .. math.floor(frac * 100) .. "%", UI.Font(13, 800), cx, by + bh / 2,
                color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)
