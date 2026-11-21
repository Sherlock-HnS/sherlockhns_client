-- Cooldown do killer (cliente): barra na HUD enquanto o killer está lento.
-- Shared: sh_cooldown.lua | Servidor: sv_cooldown.lua

local SH  = SherlockHNS
local CD  = SH.Cooldown
local COL = Color(255, 170, 60)

local function U(v) return SH.UI.Unit(v) end

hook.Add("HUDPaint", "SherlockHNS_CooldownHUD", function()
    if not SH.UI.GameplayVisible() then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local lp = LocalPlayer()
    if not (IsValid(lp) and lp:Alive() and CD.IsActive(lp)) then return end

    local left = CD.TimeLeft(lp)
    local total = math.max(0.1, lp:GetNWFloat("hns_cd_total", CD.Num("CdTime")))
    local frac = math.Clamp(left / total, 0, 1)

    local cx, y = ScrW() / 2, ScrH() - U(240)
    local bw, bh = math.min(U(260), ScrW() - 32), U(6)

    draw.SimpleTextOutlined(("COOLDOWN  %.1fs"):format(left), SH.UI.Font(18, 800), cx, y, COL,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(cx - bw / 2 - 2, y + U(14) - 2, bw + 4, bh + 4)
    surface.SetDrawColor(COL)
    surface.DrawRect(cx - bw / 2, y + U(14), bw * frac, bh)
end)
