-- Nameplates (cliente): placa flutuante que aparece só quando a MIRA está em
-- cima de outro jogador. Substitui o target ID nativo do Garry's Mod
-- (nome + vida) por uma placa com nome e a tag principal (sh_tags.lua).
-- Adaptado do cl_nameplates.lua do pill-legacy.
--
-- A vida do alvo NÃO é mostrada de propósito (hide and seek: não entrega
-- quem está ferido). A cor também é neutra para não revelar o killer.

local SH         = SherlockHNS
local T          = SH.Tags

SH.Nameplate     = SH.Nameplate or {}
local NP         = SH.Nameplate

local cvEnabled  = CreateClientConVar("hns_nameplate", "1", true, false,
    "Mostra a nameplate ao mirar em outro jogador.", 0, 1)
local cvDistance = CreateClientConVar("hns_nameplate_distance", "450", true, false,
    "Distância máxima (unidades) para a nameplate aparecer.", 50, 3000)

local COL_BG     = Color(14, 14, 18)
local COL_NAME   = Color(255, 255, 255)

local function U(v) return SherlockHNS.UI.Unit(v) end

local function F(size, weight)
    return SherlockHNS.UI.Font(size, weight or 700, "Trebuchet MS")
end

-- ===== Esconde o target ID nativo (nome + vida) =====
function GM:HUDDrawTargetID() end

-- ===== Alvo =====
-- Com pill física o player fica invisível e a mira acerta a pill_ent_phys;
-- com costume acerta o puppet. Os dois têm GetPillUser, então resolvemos o dono.
local function OwnerOf(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end
    if ent.GetPillUser then
        local u = ent:GetPillUser()
        if IsValid(u) and u:IsPlayer() then return u end
    end
end

local function FindTarget(lp)
    local s = lp:GetShootPos()
    local tr = util.TraceLine({
        start  = s,
        endpos = s + lp:GetAimVector() * cvDistance:GetFloat(),
        mask   = MASK_SHOT,
        filter = function(e)
            if e == lp or e.HNS_IsBarrier then return false end
            if e.GetPillUser and e:GetPillUser() == lp then return false end
            return true
        end,
    })

    local ply = OwnerOf(tr.Entity)
    if not ply or ply == lp or not ply:Alive() then return nil end
    if ply:Team() == TEAM_SPECTATOR or SH.IsInMenu(ply) or SH.IsBystander and SH.IsBystander(ply) then return nil end
    return ply
end

-- Entidade que representa o corpo visível (mesma lógica da aura)
local function BodyOf(ply)
    local ent = pk_pills and pk_pills.getMappedEnt and pk_pills.getMappedEnt(ply)
    if IsValid(ent) then
        if ent:GetClass() == "pill_ent_phys" then return ent end
        if ent.GetPuppet and IsValid(ent:GetPuppet()) then return ent:GetPuppet() end
    end
    return ply
end

-- Ponto logo acima da cabeça do corpo visível
local function AnchorPos(ply)
    local body = BodyOf(ply)
    local mins, maxs = body:WorldSpaceAABB()
    return Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, maxs.z + 8)
end

-- ===== Desenho =====
local alpha, last = 0, nil
local nextScan, cachedTarget = 0, nil

-- Jogador sob a mira agora (usado pelo atalho de ficha dos admins; ver cl_admin_moderation.lua)
function NP.GetAimed()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() or alpha <= 1 then return nil end
    return IsValid(NP.Current) and NP.Current or nil
end

hook.Add("HUDPaint", "SherlockHNS_Nameplate", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local show = SherlockHNS.UI.GameplayVisible() and cvEnabled:GetBool() and lp:Alive() and lp:Team() ~= TEAM_SPECTATOR
    if show and SH.IsMenuOpen and SH.IsMenuOpen() then show = false end
    if show and hook.Run("SherlockHNS_ShouldDrawHUD") == false then show = false end
    if show and SH.HUD and SH.HUD.Hidden then show = false end

    local now = CurTime()
    local target
    if show then
        if now >= nextScan then
            nextScan = now + 0.1
            cachedTarget = FindTarget(lp)
        end
        target = cachedTarget
    else
        nextScan = 0
        cachedTarget = nil
    end
    NP.Current = target
    if target then last = target end

    local dt = FrameTime()
    alpha = math.Approach(alpha, target and 255 or 0, dt * (target and 900 or 700))
    if alpha <= 1 or not IsValid(last) then return end

    local ply = last
    local scr = AnchorPos(ply):ToScreen()
    if not scr.visible then return end

    local nick = ply:Nick()
    if utf8.len(nick) and utf8.len(nick) > 28 then
        nick = string.sub(nick, 1, utf8.offset(nick, 29) - 1) .. "..."
    end

    local tag = T and T.GetTop and T.GetTop(ply) or nil
    local maxWidth = math.min(ScrW() - U(48), U(360))
    nick = SherlockHNS.UI.Fit(nick, F(18, 800), maxWidth)
    local tagLabel = tag and SherlockHNS.UI.Fit("[" .. tag.text .. "]", F(14), maxWidth) or nil

    surface.SetFont(F(18, 800))
    local nameW, nameH = surface.GetTextSize(nick)

    local tagW, tagH = 0, 0
    if tagLabel then
        surface.SetFont(F(14))
        tagW, tagH = surface.GetTextSize(tagLabel)
    end

    local padX, padY = U(12), U(6)
    local boxW = math.max(nameW, tagW) + padX * 2
    local boxH = nameH + (tagLabel and (tagH + U(2)) or 0) + padY * 2
    local x = math.Clamp(scr.x - boxW / 2, 4, math.max(4, ScrW() - boxW - 4))
    local centerX = x + boxW / 2
    local y = math.Clamp(scr.y - boxH - U(6), 4, math.max(4, ScrH() - boxH - 4))

    local a = alpha / 255
    local accent = tag and Color(tag.color.r, tag.color.g, tag.color.b) or COL_NAME

    draw.RoundedBox(U(6), x, y, boxW, boxH, ColorAlpha(COL_BG, 190 * a))
    surface.SetDrawColor(accent.r, accent.g, accent.b, 90 * a)
    surface.DrawOutlinedRect(x, y, boxW, boxH, 1)

    draw.SimpleText(nick, F(18, 800), centerX, y + padY,
        ColorAlpha(COL_NAME, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    if tagLabel then
        draw.SimpleText(tagLabel, F(14), centerX, y + padY + nameH + U(2),
            ColorAlpha(accent, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end

    -- dica só para administradores
    if lp:IsAdmin() and SH.Keys and SH.Keys.Get("modfile") > 0 and IsValid(NP.Current) then
        draw.SimpleText("[" .. SH.Keys.Name("modfile") .. "] Ficha", F(13), centerX, y + boxH + U(2),
            ColorAlpha(Color(255, 214, 102), 230 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)
