local cvVisible = CreateClientConVar("hns_barrier_visible", "1", true, false,
    "Mostra as barreiras anti-loop (0/1). Quem segura a ferramenta sempre enxerga.")
local cvDist = CreateClientConVar("hns_barrier_distance", "450", true, false,
    "Distância máxima para exibir as barreiras (0 = sempre).", 0, 5000)

local function holdingTool()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end
    local w = lp:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "weapon_hns_barrier"
end

local EPS = 0.3
local v1, v2, v3, v4 = Vector(), Vector(), Vector(), Vector()
local scratch = Color(255, 255, 255, 255)

local function C(r, g, b, a)
    scratch.r, scratch.g, scratch.b, scratch.a = r, g, b, a
    return scratch
end

local function faceQuad(x1, y1, x2, y2, z0, z1, col)
    v1.x, v1.y, v1.z = x1, y1, z0
    v2.x, v2.y, v2.z = x2, y2, z0
    v3.x, v3.y, v3.z = x2, y2, z1
    v4.x, v4.y, v4.z = x1, y1, z1
    render.DrawQuad(v1, v2, v3, v4, col)
    render.DrawQuad(v4, v3, v2, v1, col) -- ambos os lados
end

function ENT:Think()
    -- os bounds chegam por NetworkVar, possivelmente depois do Initialize
    if not self.HNS_PhysReady and self:BoundsReady() then
        self.HNS_PhysReady = self:BuildPhysics()
    end
    self:SetNextClientThink(CurTime() + 0.25)
    return true
end

local FADE_DIST = 450 -- distância (até a caixa) em que a barreira começa a aparecer

function ENT:Draw()
    local editing = holdingTool()
    if not editing and not cvVisible:GetBool() then return end
    if not self:BoundsReady() then return end

    local pos        = self:GetPos()
    local lmin, lmax = self:GetBMins(), self:GetBMaxs()
    local wmin, wmax = pos + lmin, pos + lmax

    local fade       = cvDist:GetFloat()

    -- Distância do jogador até a CAIXA (não até o centro)
    local pp         = LocalPlayer():GetPos()
    local cp         = Vector(math.Clamp(pp.x, wmin.x, wmax.x), math.Clamp(pp.y, wmin.y, wmax.y),
        math.Clamp(pp.z, wmin.z, wmax.z))
    local dist       = pp:Distance(cp)

    if not editing and fade > 0 and dist >= fade then return end

    local near  = fade > 0 and (1 - math.Clamp(dist / fade, 0, 1)) or 1
    local vis   = editing and 1 or (near * near * (3 - 2 * near)) -- multiplica todos os alphas
    local t     = CurTime()
    local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + (pos.x + pos.y) * 0.004)
    local fillA = (22 + 40 * near + 12 * pulse + (editing and 20 or 0)) * vis

    render.SetColorMaterial()

    -- 1) preenchimento
    local fill = C(255, 25, 35, fillA)
    render.DrawBox(pos, angle_zero, lmin, lmax, fill)
    render.DrawBox(pos, angle_zero, lmax, lmin, fill)

    -- 2) arestas
    render.DrawWireframeBox(pos, angle_zero, lmin, lmax,
        C(255, 70, 70, (90 + 120 * near + (editing and 45 or 0)) * vis), false)

    -- 3) faixas de varredura
    local x1, y1, x2, y2 = wmin.x - EPS, wmin.y - EPS, wmax.x + EPS, wmax.y + EPS
    local faces          = {
        { x1, y1, x2, y1 }, { x2, y1, x2, y2 },
        { x2, y2, x1, y2 }, { x1, y2, x1, y1 },
    }
    local H              = wmax.z - wmin.z
    local seed           = (pos.x * 0.37 + pos.y * 0.61) % 100
    local bandZ          = wmin.z + ((t * 70 + seed) % (H + 80)) - 40

    for _, band in ipairs({ { 26, 34 + 30 * near }, { 6, 110 + 60 * near } }) do
        local th, a = band[1], band[2] * vis
        local zA, zB = math.max(bandZ - th / 2, wmin.z), math.min(bandZ + th / 2, wmax.z)
        if zB > zA then
            local col = C(255, 90, 90, a)
            for _, f in ipairs(faces) do faceQuad(f[1], f[2], f[3], f[4], zA, zB, col) end
        end
    end

    -- 4) grade
    if near > 0.05 or editing then
        local gcol = C(255, 60, 60, (16 + 60 * near + (editing and 30 or 0)) * vis)
        for _, f in ipairs(faces) do
            local len = math.sqrt((f[3] - f[1]) ^ 2 + (f[4] - f[2]) ^ 2)
            local n   = math.Clamp(math.floor(len / 128), 1, 8)
            for i = 0, n do
                local k = i / n
                local x, y = Lerp(k, f[1], f[3]), Lerp(k, f[2], f[4])
                v1.x, v1.y, v1.z = x, y, wmin.z
                v2.x, v2.y, v2.z = x, y, wmax.z
                render.DrawLine(v1, v2, gcol, false)
            end
            local nz = math.Clamp(math.floor(H / 128), 1, 8)
            for j = 0, nz do
                local z = Lerp(j / nz, wmin.z, wmax.z)
                v1.x, v1.y, v1.z = f[1], f[2], z
                v2.x, v2.y, v2.z = f[3], f[4], z
                render.DrawLine(v1, v2, gcol, false)
            end
        end
    end
end
