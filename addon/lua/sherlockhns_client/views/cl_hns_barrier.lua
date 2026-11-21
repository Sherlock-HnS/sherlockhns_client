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
local function faceQuad(x1, y1, x2, y2, z0, z1, col)
    local a, b = Vector(x1, y1, z0), Vector(x2, y2, z0)
    local c, d = Vector(x2, y2, z1), Vector(x1, y1, z1)
    render.DrawQuad(a, b, c, d, col)
    render.DrawQuad(d, c, b, a, col) -- ambos os lados
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
    local fill = Color(255, 25, 35, fillA)
    render.DrawBox(pos, angle_zero, lmin, lmax, fill)
    render.DrawBox(pos, angle_zero, lmax, lmin, fill)

    -- 2) arestas
    render.DrawWireframeBox(pos, angle_zero, lmin, lmax,
        Color(255, 70, 70, (90 + 120 * near + (editing and 45 or 0)) * vis), false)

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
            local col = Color(255, 90, 90, a)
            for _, f in ipairs(faces) do faceQuad(f[1], f[2], f[3], f[4], zA, zB, col) end
        end
    end

    -- 4) grade
    if near > 0.05 or editing then
        local gcol = Color(255, 60, 60, (16 + 60 * near + (editing and 30 or 0)) * vis)
        for _, f in ipairs(faces) do
            local len = math.sqrt((f[3] - f[1]) ^ 2 + (f[4] - f[2]) ^ 2)
            local n   = math.Clamp(math.floor(len / 64), 1, 40)
            for i = 0, n do
                local k = i / n
                local x, y = Lerp(k, f[1], f[3]), Lerp(k, f[2], f[4])
                render.DrawLine(Vector(x, y, wmin.z), Vector(x, y, wmax.z), gcol, false)
            end
            local nz = math.Clamp(math.floor(H / 64), 1, 40)
            for j = 0, nz do
                local z = Lerp(j / nz, wmin.z, wmax.z)
                render.DrawLine(Vector(f[1], f[2], z), Vector(f[3], f[4], z), gcol, false)
            end
        end
    end
end
