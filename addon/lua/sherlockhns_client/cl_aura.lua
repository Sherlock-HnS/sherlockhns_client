-- Aura: outline visível através de paredes em killers e runners.
-- Liga quando faltam SherlockHNS.AuraTime segundos na rodada ou no LMS.
--
-- Dois modos (ConVar do jogador hns_aura_entity):
--   1 = entidade (padrão): caixa desenhada nas hns_aura (sv_aura.lua). Leve, vale de qualquer lugar.
--   0 = halo: o outline original. Mais bonito, mais pesado.

local SH = SherlockHNS

local cvEntity = CreateClientConVar("hns_aura_entity", "1", true, false,
    "Aura por entidade (1, mais leve) ou halo (0).", 0, 1)

local COL_KILLER = Color(255, 60, 60)
local COL_RUNNER = Color(80, 190, 255)

local wasOn = false

-- ===== Condição =====
local function AuraActive()
    local state = GetGlobalInt("sherlockhns_state", ROUND_WAITING)
    if state == ROUND_LMS then return true end
    if state ~= ROUND_ACTIVE then return false end

    local endAt = GetGlobalFloat("sherlockhns_state_end", 0)
    if endAt == 0 then return false end

    return (endAt - CurTime()) <= SH.AuraTime
end

-- ===== Entidades que representam o player (modo halo) =====
local function BodyEnts(ply, out)
    local ent = pk_pills and pk_pills.getMappedEnt and pk_pills.getMappedEnt(ply)
    local body = ply

    if IsValid(ent) then
        if ent:GetClass() == "pill_ent_phys" then
            body = ent
        elseif ent.GetPuppet and IsValid(ent:GetPuppet()) then
            body = ent:GetPuppet()
        end
    end

    out[#out + 1] = body
    for _, child in ipairs(body:GetChildren()) do
        if IsValid(child) then out[#out + 1] = child end
    end
end

SH.AuraActive = AuraActive
SH.BodyEnts   = BodyEnts

-- Aura do killer: dura KillerAuraTime s desde que a aura ligou (0 = permanente)
local function KillerAuraOn()
    local dur = GetGlobalInt("sherlockhns_cfg_KillerAuraTime", 15)
    if dur <= 0 then return true end

    local start = GetGlobalFloat("sherlockhns_aura_start", 0)
    return start <= 0 or (CurTime() - start) < dur
end

SH.KillerAuraOn = KillerAuraOn

-- Pode desenhar agora? (comum aos dois modos)
local function CanDraw()
    local lp = LocalPlayer()
    if not IsValid(lp) or not AuraActive() then return false end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return false end
    return hook.Run("SherlockHNS_ShouldDrawAura") ~= false
end

-- Som ao ligar (independe do modo)
hook.Add("Think", "SherlockHNS_AuraSound", function()
    local on = AuraActive()
    if on ~= wasOn then
        wasOn = on
        if on then surface.PlaySound("buttons/blip1.wav") end
    end
end)

-- ===== Modo halo =====
hook.Add("PreDrawHalos", "SherlockHNS_Aura", function()
    if cvEntity:GetBool() or not CanDraw() then return end

    local lp = LocalPlayer()
    local killers, runners = {}, {}

    for _, ply in ipairs(player.GetAll()) do
        if ply ~= lp and ply:Alive() then
            local t = ply:Team()
            if t == TEAM_KILLERS then
                if KillerAuraOn() then BodyEnts(ply, killers) end
            elseif t == TEAM_HIDERS then
                BodyEnts(ply, runners)
            end
        end
    end

    -- halo.Add(ents, color, blurX, blurY, passes, additive, ignoreZ)
    if #runners > 0 then halo.Add(runners, COL_RUNNER, 2, 2, 2, true, true) end
    if #killers > 0 then halo.Add(killers, COL_KILLER, 2, 2, 2, true, true) end
end)

-- ===== Modo entidade =====
-- Desenhado num hook (não no ENT:Draw): a engine não chama o Draw de entidades
-- fora da visibilidade, e a ideia é ver de qualquer lugar.
hook.Add("PostDrawTranslucentRenderables", "SherlockHNS_AuraEntity", function(depth, sky)
    if depth or sky then return end
    if not cvEntity:GetBool() or not CanDraw() then return end

    local lp = LocalPlayer()
    local list = ents.FindByClass("hns_aura")
    if #list == 0 then return end

    cam.IgnoreZ(true)
    render.SetColorMaterialIgnoreZ()

    for _, e in ipairs(list) do
        local owner = e:GetTarget()
        if IsValid(owner) and owner ~= lp and owner:Alive()
            and (owner:Team() ~= TEAM_KILLERS or KillerAuraOn()) then
            local base = owner:Team() == TEAM_KILLERS and COL_KILLER or COL_RUNNER
            local pos, mins, maxs = e:GetPos(), e:GetBMins(), e:GetBMaxs()

            -- preenchimento leve (as duas faces, para ver por dentro também)
            local fill = Color(base.r, base.g, base.b, 28)
            render.DrawBox(pos, angle_zero, mins, maxs, fill)
            render.DrawBox(pos, angle_zero, maxs, mins, fill)

            -- arestas
            local wmin, wmax = pos + mins, pos + maxs
            local c = Color(base.r, base.g, base.b, 255)
            local x1, y1, z1, x2, y2, z2 = wmin.x, wmin.y, wmin.z, wmax.x, wmax.y, wmax.z

            local a, b, cc, d = Vector(x1, y1, z1), Vector(x2, y1, z1), Vector(x2, y2, z1), Vector(x1, y2, z1)
            local e1, f, g, h = Vector(x1, y1, z2), Vector(x2, y1, z2), Vector(x2, y2, z2), Vector(x1, y2, z2)

            render.DrawLine(a, b, c, false); render.DrawLine(b, cc, c, false)
            render.DrawLine(cc, d, c, false); render.DrawLine(d, a, c, false)
            render.DrawLine(e1, f, c, false); render.DrawLine(f, g, c, false)
            render.DrawLine(g, h, c, false); render.DrawLine(h, e1, c, false)
            render.DrawLine(a, e1, c, false); render.DrawLine(b, f, c, false)
            render.DrawLine(cc, g, c, false); render.DrawLine(d, h, c, false)
        end
    end

    cam.IgnoreZ(false)
end)
