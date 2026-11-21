-- Force field (cliente): bolha em volta do protegido + barra na HUD.
-- Shared: sh_forcefield.lua | Servidor: sv_forcefield.lua

local SH  = SherlockHNS
local FF  = SH.ForceField
local COL = Color(80, 190, 255)

local function U(v) return SH.UI.Unit(v) end

-- Corpo visível: pill física, puppet da pill costume ou o próprio player
local function BodyOf(ply)
    local ent = pk_pills and pk_pills.getMappedEnt and pk_pills.getMappedEnt(ply)
    if IsValid(ent) then
        if ent:GetClass() == "pill_ent_phys" then return ent end
        if ent.GetPuppet and IsValid(ent:GetPuppet()) then return ent:GetPuppet() end
    end
    return ply
end

hook.Add("PostDrawTranslucentRenderables", "SherlockHNS_ForceFieldDraw", function(depth, sky)
    if depth or sky then return end

    local lp, now = LocalPlayer(), CurTime()
    render.SetColorMaterial()

    for _, ply in ipairs(player.GetAll()) do
        -- na primeira pessoa a bolha ficaria em volta da câmera
        if ply ~= lp and FF.IsProtected(ply) then
            local body = BodyOf(ply)
            local mins, maxs = body:WorldSpaceAABB()
            local center = (mins + maxs) / 2
            local size = maxs - mins
            local radius = math.max(30, math.max(size.x, size.y, size.z) / 2 + 12)

            local left = FF.TimeLeft(ply)
            local blink = left < 1.5 and (0.5 + 0.5 * math.sin(now * 20)) or 1
            local pulse = 0.8 + 0.2 * math.sin(now * 4)
            local col = Color(COL.r, COL.g, COL.b, 45 * blink * pulse)

            render.DrawSphere(center, radius, 24, 24, col)
            render.DrawSphere(center, -radius, 24, 24, col) -- face de dentro
        end
    end
end)

hook.Add("HUDPaint", "SherlockHNS_ForceFieldHUD", function()
    if not SH.UI.GameplayVisible() then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local lp = LocalPlayer()
    if not FF.IsProtected(lp) then return end

    local left = FF.TimeLeft(lp)
    local total = math.max(0.1, lp:GetNWFloat("hns_ff_total", FF.Num("FfTime")))
    local frac = math.Clamp(left / total, 0, 1)

    local cx, y = ScrW() / 2, ScrH() - U(200)
    local bw, bh = math.min(U(260), ScrW() - 32), U(6)

    draw.SimpleTextOutlined(("FORCE FIELD  %.1fs"):format(left), SH.UI.Font(18, 800), cx, y, COL,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawRect(cx - bw / 2 - 2, y + U(14) - 2, bw + 4, bh + 4)
    surface.SetDrawColor(COL)
    surface.DrawRect(cx - bw / 2, y + U(14), bw * frac, bh)
end)
