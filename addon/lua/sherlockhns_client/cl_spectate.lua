hook.Add("HUDPaint", "SherlockHNS_SpecHUD", function()
    if not SherlockHNS.UI.GameplayVisible() then return end
    if SherlockHNS.IsMenuOpen and SherlockHNS.IsMenuOpen() then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if lp:GetObserverMode() == OBS_MODE_NONE then return end

    local target = lp:GetObserverTarget()
    local name = (IsValid(target) and target:IsPlayer()) and target:Nick() or "Câmera livre"

    draw.SimpleTextOutlined(SherlockHNS.UI.Fit("Espectando: " .. name, "DermaLarge", ScrW() - 32), "DermaLarge",
        ScrW() / 2, ScrH() - 90,
        color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("Clique: trocar alvo   |   Espaço: modo de câmera", "DermaDefaultBold",
        ScrW() / 2, ScrH() - 60, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

    -- atalho da ficha (só administradores, e só com um jogador sendo espectado)
    local K = SherlockHNS.Keys
    if lp:IsAdmin() and IsValid(target) and target:IsPlayer() and K and K.Get("modfile") > 0 then
        draw.SimpleTextOutlined(("[%s] Ficha / moderar %s"):format(K.Name("modfile"), SherlockHNS.UI.Fit(name, "DermaDefaultBold", ScrW() - 200)),
            "DermaDefaultBold", ScrW() / 2, ScrH() - 40, Color(255, 214, 102),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end)
