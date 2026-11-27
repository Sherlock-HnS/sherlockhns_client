-- Efeitos de câmera/sensação (cliente): FOV dinâmico pela velocidade e batimento cardíaco
-- quando um killer está por perto. Opções em Configurações > Geral (cl_menu.lua).

local SH            = SherlockHNS

local cvFov         = CreateClientConVar("hns_fov_dynamic", "1", true, false,
    "FOV dinâmico conforme a velocidade (0/1).", 0, 1)
local cvReact       = CreateClientConVar("hns_fov_reactivity", "50", true, false,
    "Reatividade do FOV à velocidade (0-100).", 0, 100)
local cvHeart       = CreateClientConVar("hns_heartbeat", "1", true, false,
    "Batimento cardíaco quando um killer está próximo (0/1).", 0, 1)

local HEART_SOUND   = "player/heartbeat1.wav"
local HEART_RADIUS  = 1200 -- unidades
local MAX_EXTRA_FOV = 30   -- graus com reatividade 100

local function U(v) return SH.UI.Unit(v) end

-- ===== Helpers =====
-- Pills físicas movem a entidade da pill, não o player
local function PillEnt(ply)
    local ent = pk_pills and pk_pills.getMappedEnt and pk_pills.getMappedEnt(ply)
    if IsValid(ent) then return ent end
end

local function BodyVelocity(ply)
    local ent = PillEnt(ply)
    if ent and ent:GetClass() == "pill_ent_phys" then return ent:GetVelocity() end
    return ply:GetVelocity()
end

local function BodyPos(ply)
    local ent = PillEnt(ply)
    if ent and ent:GetClass() == "pill_ent_phys" then return ent:GetPos() end
    return ply:GetPos()
end

local function InPlay(lp)
    if not (IsValid(lp) and lp:Alive()) then return false end
    if lp:Team() == TEAM_SPECTATOR or lp:GetObserverMode() ~= OBS_MODE_NONE then return false end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return false end
    return true
end

-- ============================================================
-- FOV dinâmico
-- ============================================================
local extra = 0

-- Velocidade de referência: de andar (extra 0) até o teto (extra máximo).
local function SpeedRange()
    local walk = GetGlobalInt("sherlockhns_cfg_SnBaseWalk", 200)
    local top  = GetGlobalInt("sherlockhns_cfg_SnBaseRun", 400)

    local M    = SH.Mutation
    if M and M.Is and M.Is("bhop") then
        top = math.max(top, M.Cfg("BhopMaxSpeed", 1100))
    end
    return walk, math.max(top, walk + 1)
end

-- Outros hooks de CalcView (câmera de pills etc.) continuam valendo:
-- chamamos todos e só somamos o FOV ao resultado.
local function BaseView(ply, origin, angles, fov, znear, zfar)
    for name, fn in pairs(hook.GetTable().CalcView or {}) do
        if name ~= "SherlockHNS_DynamicFOV" and isfunction(fn) then
            local ok, res
            if isstring(name) then
                ok, res = pcall(fn, ply, origin, angles, fov, znear, zfar)
            elseif IsValid(name) then
                ok, res = pcall(fn, name, ply, origin, angles, fov, znear, zfar)
            end
            if ok and istable(res) then return res end
        end
    end

    if GAMEMODE and GAMEMODE.CalcView then
        local ok, res = pcall(GAMEMODE.CalcView, GAMEMODE, ply, origin, angles, fov, znear, zfar)
        if ok and istable(res) then return res end
    end

    return { origin = origin, angles = angles, fov = fov, znear = znear, zfar = zfar }
end

hook.Add("CalcView", "SherlockHNS_DynamicFOV", function(ply, origin, angles, fov, znear, zfar)
    local lp = LocalPlayer()
    if ply ~= lp then return end

    local react = cvReact:GetFloat() / 100
    local on = cvFov:GetBool() and react > 0 and InPlay(lp) and lp:GetMoveType() ~= MOVETYPE_NOCLIP

    local target = 0
    if on then
        local walk, top = SpeedRange()
        local speed = BodyVelocity(lp):Length2D()
        target = math.Clamp((speed - walk) / (top - walk), 0, 1) * MAX_EXTRA_FOV * react
    end

    -- reatividade maior também acompanha mais rápido
    local rate = 3 + 9 * react
    extra = Lerp(math.min(1, RealFrameTime() * rate), extra, target)

    if extra < 0.05 then return end -- sem efeito: não interfere em mais ninguém

    local view = BaseView(ply, origin, angles, fov, znear, zfar)
    view.fov = (view.fov or fov) + extra
    return view
end)

-- ============================================================
-- Batimento cardíaco
-- ============================================================
local hasSound = file.Exists("sound/" .. HEART_SOUND, "GAME")

local intensity, targetIntensity = 0, 0
local nextScan, nextBeat, lastBeat = 0, 0, -10

local function Scan(lp)
    local eye, best = lp:GetPos(), 0
    local r2 = HEART_RADIUS * HEART_RADIUS

    for _, k in ipairs(team.GetPlayers(TEAM_KILLERS)) do
        if k ~= lp and IsValid(k) and k:Alive() and k:GetObserverMode() == OBS_MODE_NONE then
            local d2 = BodyPos(k):DistToSqr(eye)
            if d2 < r2 then
                best = math.max(best, 1 - math.sqrt(d2) / HEART_RADIUS)
            end
        end
    end
    return best
end

hook.Add("Think", "SherlockHNS_Heartbeat", function()
    local lp = LocalPlayer()
    local now = CurTime()

    local active = cvHeart:GetBool() and IsValid(lp) and InPlay(lp)
        and lp:Team() == TEAM_HIDERS
        and SH.IsLive(GetGlobalInt("sherlockhns_state", ROUND_WAITING))

    if active then
        if now >= nextScan then
            nextScan = now + 0.1
            targetIntensity = Scan(lp)
        end
    else
        targetIntensity = 0
    end

    intensity = Lerp(math.min(1, FrameTime() * 4), intensity, targetIntensity)
    if intensity < 0.02 then return end

    if now >= nextBeat then
        local bpm = Lerp(intensity, 65, 150)
        nextBeat = now + 60 / bpm
        lastBeat = now

        if hasSound and IsValid(lp) then
            lp:EmitSound(HEART_SOUND, 75, math.Round(Lerp(intensity, 90, 125)),
                math.Clamp(0.25 + intensity * 0.75, 0, 1), CHAN_STATIC)
        end
    end
end)

local MAT_L = Material("vgui/gradient-l")
local MAT_R = Material("vgui/gradient-r")
local MAT_U = Material("vgui/gradient-u")
local MAT_D = Material("vgui/gradient-d")

-- Vinheta vermelha que pulsa a cada batida
hook.Add("HUDPaint", "SherlockHNS_HeartbeatVignette", function()
    if intensity < 0.02 or not cvHeart:GetBool() then return end
    if not SH.UI.GameplayVisible() then return end

    local since = CurTime() - lastBeat
    local pulse = math.max(0, 1 - since * 3.5) -- decai rápido depois da batida
    local alpha = (30 + 130 * pulse) * intensity
    if alpha < 1 then return end

    local w, h = ScrW(), ScrH()
    local sx, sy = w * 0.22, h * 0.28

    surface.SetDrawColor(160, 0, 0, alpha)
    surface.SetMaterial(MAT_L); surface.DrawTexturedRect(0, 0, sx, h)
    surface.SetMaterial(MAT_R); surface.DrawTexturedRect(w - sx, 0, sx, h)
    surface.SetMaterial(MAT_U); surface.DrawTexturedRect(0, 0, w, sy)
    surface.SetMaterial(MAT_D); surface.DrawTexturedRect(0, h - sy, w, sy)
end)
