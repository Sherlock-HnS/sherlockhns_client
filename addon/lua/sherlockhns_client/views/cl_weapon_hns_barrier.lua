function SWEP:PrimaryAttack() self:SetNextPrimaryFire(CurTime() + 0.25) end
function SWEP:SecondaryAttack() self:SetNextSecondaryFire(CurTime() + 0.25) end
function SWEP:Reload() end
function SWEP:Holster() return true end

hook.Add("PostDrawTranslucentRenderables", "SherlockHNS_BarrierTool_Preview", function(_, bSky)
    if bSky then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local wep = lp:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "weapon_hns_barrier" or not wep:GetHasA() then return end

    local mins, maxs = wep:BuildBox(wep:GetCornerA(), wep:GetAimPos())
    local col = Color(255, 220, 60, 40)
    render.SetColorMaterial()
    render.DrawBox(vector_origin, angle_zero, mins, maxs, col)
    render.DrawBox(vector_origin, angle_zero, maxs, mins, col)
    render.DrawWireframeBox(vector_origin, angle_zero, mins, maxs, Color(255, 220, 60, 255), true)
end)

function SWEP:DrawHUD()
    local h = self.HNSHeights[self:GetHeightMode() + 1]
    local hTxt = (h == 0) and "livre" or tostring(h)
    local sw, sh = ScrW(), ScrH()

    draw.SimpleTextOutlined("BARREIRA ANTI-LOOP  |  Altura: " .. hTxt .. "  |  " ..
        (self:GetHasA() and "clique no canto B" or "clique no canto A"),
        "DermaDefaultBold", sw / 2, sh - 110, Color(255, 120, 120),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("M1: canto  |  M2: cancelar / remover na mira  |  R: altura",
        "DermaDefault", sw / 2, sh - 88, Color(200, 200, 200),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

    -- IDs flutuando no centro de cada barreira
    for _, b in ipairs(ents.FindByClass("hns_barrier")) do
        local scr = b:GetPos():ToScreen()
        if scr.visible then
            draw.SimpleTextOutlined("#" .. b:GetBarrierId(), "DermaDefaultBold", scr.x, scr.y,
                Color(255, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        end
    end
end
