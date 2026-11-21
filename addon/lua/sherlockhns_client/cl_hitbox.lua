-- Mostra a hitbox do Juggernaut para admins: hns_hitbox_debug 1
local cv = CreateClientConVar("hns_hitbox_debug", "0", false, false,
    "Desenha a hitbox custom do Juggernaut (só admin).", 0, 1)

hook.Add("PostDrawTranslucentRenderables", "SherlockHNS_HitboxDebug", function(depth, sky)
    if depth or sky or not cv:GetBool() then return end

    local lp = LocalPlayer()
    if not (IsValid(lp) and lp:IsAdmin()) then return end

    local j = GetGlobalEntity("sherlockhns_juggernaut")
    if not (IsValid(j) and j:Alive()) then return end

    local mins, maxs = j:GetNWVector("hns_hb_mins"), j:GetNWVector("hns_hb_maxs")
    if mins == maxs then return end

    render.DrawWireframeBox(j:GetPos(), angle_zero, mins, maxs, Color(255, 160, 40), true)
end)
