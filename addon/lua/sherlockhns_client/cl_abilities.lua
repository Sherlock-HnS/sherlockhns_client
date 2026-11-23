-- HUD própria do Sherlock HnS + cliente da API de Habilidades
-- Documentação: docs/ABILITIES_API.md

SherlockHNS.Ability = SherlockHNS.Ability or {}
SherlockHNS.HUD     = SherlockHNS.HUD or {}
local AB, HUD       = SherlockHNS.Ability, SherlockHNS.HUD

local cvEnable      = CreateClientConVar("hns_hud", "1", true, false, "Mostra a HUD do Sherlock HnS", 0, 1)
local cvScale       = CreateClientConVar("hns_hud_scale", "1", true, false, "Escala da HUD do Sherlock HnS", 0.5, 2)
local cvAliveCount  = CreateClientConVar("hns_alive_counter", "1", true, false, "Mostra a quantidade de jogadores vivos", 0, 1)

-- Esconde a HUD nativa das pills (pk_pill_cl_hidehud) para não clipar com a nossa
HUD.HidePillHUD     = true
HUD.Hidden          = false -- outros módulos podem esconder a HUD inteira

-- ===== Tema (edite aqui para mudar o visual) =====
HUD.Theme           = {
    font       = "Tahoma",
    slotSize   = 64, -- px a 1080p
    gap        = 10,
    bottom     = 56, -- distância da borda inferior
    radius     = 8,
    border     = Color(255, 255, 255, 40),
    bg         = Color(15, 15, 20, 210),
    cooldown   = Color(0, 0, 0, 175),
    text       = Color(255, 255, 255),
    textDim    = Color(190, 190, 190),
    deny       = Color(255, 70, 70),
    ready      = Color(255, 255, 255),
    iconInset  = 8,
    keyFont    = 15,
    cdFont     = 24,
    chargeFont = 16,
    showNames  = false,
}

-- Posição do bloco de habilidades. Substitua para reposicionar.
function HUD.Position(w, h)
    return (ScrW() - w) / 2, ScrH() - h - HUD.U(HUD.Theme.bottom)
end

-- ===== Helpers =====
function HUD.U(v)
    return math.Round(v * cvScale:GetFloat() * SherlockHNS.UI.Scale())
end

local fonts = {}
function HUD.Font(size, weight)
    size, weight = math.max(8, size), weight or 700
    local name = "SherlockHNS_HUD_" .. size .. "_" .. weight
    if not fonts[name] then
        surface.CreateFont(name, {
            font = HUD.Theme.font,
            size = size,
            weight = weight,
            antialias = true,
            extended = true,
        })
        fonts[name] = true
    end
    return name
end

-- ===== Elementos da HUD =====
-- Permite plugar novos widgets depois sem mexer no resto.
local elements, sorted = {}, nil

function HUD.AddElement(id, order, fn)
    elements[id] = { id = id, order = order or 0, fn = fn }
    sorted = nil
end

function HUD.RemoveElement(id)
    elements[id] = nil
    sorted = nil
end

local function GetSorted()
    if not sorted then
        sorted = {}
        for _, e in pairs(elements) do sorted[#sorted + 1] = e end
        table.sort(sorted, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.id < b.id
        end)
    end
    return sorted
end

-- ===== Elemento: contador de jogadores vivos =====
HUD.AddElement("alive_count", 5, function()
    if not cvAliveCount:GetBool() or not SH.GetParticipants then return end

    local alive = 0
    for _, ply in ipairs(SH.GetParticipants()) do
        if IsValid(ply) and not ply:IsBot() and ply:Alive() then
            alive = alive + 1
        end
    end

    local U = HUD.U
    local w, h = U(128), U(48)
    local x = ScrW() - U(24) - w
    local y = SherlockHNS.UI.HUDY("status")
    local accent = SherlockHNS.UI.Colors.accent

    draw.RoundedBox(U(8), x, y, w, h, HUD.Theme.bg)
    surface.SetDrawColor(accent.r, accent.g, accent.b, 230)
    surface.DrawRect(x, y, U(3), h)
    surface.SetDrawColor(255, 255, 255, 45)
    surface.DrawOutlinedRect(x, y, w, h, 1)

    draw.SimpleText("VIVOS", HUD.Font(U(12), 800), x + U(12), y + h / 2,
        HUD.Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(tostring(alive), HUD.Font(U(24), 900), x + w - U(12), y + h / 2,
        HUD.Theme.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end)

-- ===== Estado das habilidades (espelho do servidor) =====
local slots, byId = {}, {}

function AB.GetLocalAll() return slots end

function AB.GetLocal(id) return byId[id] end

function AB.GetLocalRemaining(id)
    local s = byId[id]
    if not s or s.charges > 0 then return 0 end
    return math.max(0, s.rechargeAt - CurTime())
end

net.Receive("sherlockhns_ab_list", function()
    local n = net.ReadUInt(4)
    local newSlots, newById = {}, {}

    for i = 1, n do
        local s                        = {}
        s.id                           = net.ReadString()
        s.name                         = net.ReadString()
        local icon                     = net.ReadString()
        s.keyLabel                     = net.ReadString()
        s.color                        = net.ReadColor(false)
        s.maxCharges                   = net.ReadUInt(7)
        s.passive                      = net.ReadBool()
        s.mat                          = icon ~= "" and Material(icon, "smooth mips") or nil

        -- preserva o estado atual para não piscar quando a lista é reenviada
        local old                      = byId[s.id]
        s.charges                      = old and old.charges or s.maxCharges
        s.rechargeAt                   = old and old.rechargeAt or 0
        s.cdTotal                      = old and old.cdTotal or 0
        s.active                       = old and old.active or false
        s.activeUntil                  = old and old.activeUntil or 0
        s.activeTotal                  = old and old.activeTotal or 0
        s.enabled                      = old == nil or old.enabled
        s.flashAt, s.readyAt, s.denyAt = 0, 0, 0

        newSlots[#newSlots + 1]        = s
        newById[s.id]                  = s
    end

    slots, byId = newSlots, newById
end)

net.Receive("sherlockhns_ab_state", function()
    local id          = net.ReadString()
    local charges     = net.ReadUInt(7)
    local rechargeAt  = net.ReadFloat()
    local cdTotal     = net.ReadFloat()
    local active      = net.ReadBool()
    local activeUntil = net.ReadFloat()
    local activeTotal = net.ReadFloat()
    local enabled     = net.ReadBool()

    local s           = byId[id]
    if not s then return end

    local now = CurTime()
    if active and not s.active then s.flashAt = now end
    if charges > s.charges then s.readyAt = now end

    s.charges, s.rechargeAt, s.cdTotal = charges, rechargeAt, cdTotal
    s.active, s.activeUntil, s.activeTotal = active, activeUntil, activeTotal
    s.enabled = enabled
end)

net.Receive("sherlockhns_ab_deny", function()
    local s = byId[net.ReadString()]
    if not s then return end
    s.denyAt = CurTime()
    surface.PlaySound("buttons/button10.wav")
end)

-- ===== Desenho de um slot =====
local function Outline(x, y, w, h, col, a, thick)
    surface.SetDrawColor(col.r, col.g, col.b, a)
    surface.DrawOutlinedRect(x, y, w, h, thick)
end

local function PaintSlot(s, x, y, size, now)
    local T = HUD.Theme
    local U = HUD.U
    local r, bw = U(T.radius), math.max(1, U(2))

    local onCd = not s.passive and not s.active and s.charges <= 0 and s.rechargeAt > now
    local left = onCd and (s.rechargeAt - now) or 0

    -- moldura (pulsa quando ativa)
    local border = T.border
    if s.active then
        local pulse = 0.65 + 0.35 * math.sin(now * 8)
        border = Color(s.color.r, s.color.g, s.color.b, 255 * pulse)
    end
    draw.RoundedBox(r, x - bw, y - bw, size + bw * 2, size + bw * 2, border)
    draw.RoundedBox(r, x, y, size, size, T.bg)

    -- ícone (ou inicial do nome, se não houver material)
    local inset = U(T.iconInset)
    local dim = onCd or not s.enabled
    if s.mat then
        surface.SetDrawColor(255, 255, 255, dim and 110 or 255)
        surface.SetMaterial(s.mat)
        surface.DrawTexturedRect(x + inset, y + inset, size - inset * 2, size - inset * 2)
    else
        local first = string.upper(string.sub(s.name, 1, (utf8.offset(s.name, 2) or 2) - 1))
        draw.SimpleText(first, HUD.Font(U(30)), x + size / 2, y + size / 2,
            dim and T.textDim or s.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- cooldown: cortina que desce + tempo restante
    if onCd then
        local frac = s.cdTotal > 0 and math.Clamp(left / s.cdTotal, 0, 1) or 1
        surface.SetDrawColor(T.cooldown)
        surface.DrawRect(x, y, size, size * frac)

        local txt = left >= 3 and tostring(math.ceil(left)) or string.format("%.1f", left)
        draw.SimpleTextOutlined(txt, HUD.Font(U(T.cdFont)), x + size / 2, y + size / 2,
            T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end

    -- múltiplas cargas: barra de recarga + contador
    if s.maxCharges > 1 then
        if s.charges > 0 and s.charges < s.maxCharges and s.rechargeAt > now and s.cdTotal > 0 then
            local p = 1 - math.Clamp((s.rechargeAt - now) / s.cdTotal, 0, 1)
            surface.SetDrawColor(s.color.r, s.color.g, s.color.b, 220)
            surface.DrawRect(x, y + size - U(4), size * p, U(4))
        end
        draw.SimpleTextOutlined(tostring(s.charges), HUD.Font(U(T.chargeFont)),
            x + size - U(5), y + size - U(3), T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, color_black)
    end

    -- ativa com duração: barra que esvazia no topo
    if s.active and s.activeUntil > 0 and s.activeTotal > 0 then
        local p = math.Clamp((s.activeUntil - now) / s.activeTotal, 0, 1)
        surface.SetDrawColor(s.color.r, s.color.g, s.color.b, 255)
        surface.DrawRect(x, y, size * p, U(4))
    end

    -- desabilitada
    if not s.enabled then
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(x, y, size, size)
    end

    -- feedbacks: pronta (branco) e negada (vermelho)
    local rp = 1 - (now - s.readyAt) / 0.45
    if rp > 0 then Outline(x - bw, y - bw, size + bw * 2, size + bw * 2, T.ready, 255 * rp, bw) end

    local dp = 1 - (now - s.denyAt) / 0.35
    if dp > 0 then Outline(x - bw, y - bw, size + bw * 2, size + bw * 2, T.deny, 255 * dp, bw + 1) end

    -- tecla e nome
    local ty = y + size + U(4)
    if s.keyLabel ~= "" and not s.passive then
        draw.SimpleText(s.keyLabel, HUD.Font(U(T.keyFont), 800), x + size / 2, ty,
            T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        ty = ty + U(T.keyFont) + U(2)
    end
    if T.showNames then
        draw.SimpleText(s.name, HUD.Font(U(T.keyFont - 2), 600), x + size / 2, ty,
            T.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

-- ===== Elemento: barra de habilidades =====
-- Hook SherlockHNS_PaintAbilitySlot(slot, x, y, size): retorne true para
-- desenhar o slot por conta própria e pular o visual padrão.
HUD.AddElement("abilities", 10, function(now)
    if #slots == 0 then return end

    local T = HUD.Theme
    local size, gap = HUD.U(T.slotSize), HUD.U(T.gap)
    local columns = math.max(1, math.min(#slots, math.floor((ScrW() - 32 + gap) / (size + gap))))
    local rows = math.ceil(#slots / columns)
    local rowHeight = size + HUD.U(T.keyFont + 12 + (T.showNames and T.keyFont or 0))
    local total = columns * size + (columns - 1) * gap
    local x0, y0 = HUD.Position(total, rows * rowHeight)

    for i, s in ipairs(slots) do
        local x = x0 + ((i - 1) % columns) * (size + gap)
        local y = y0 + math.floor((i - 1) / columns) * rowHeight
        if hook.Run("SherlockHNS_PaintAbilitySlot", s, x, y, size) ~= true then
            PaintSlot(s, x, y, size, now)
        end
    end
end)

-- ===== Loop de desenho =====
hook.Add("HUDPaint", "SherlockHNS_HUD", function()
    if not SherlockHNS.UI.GameplayVisible() then return end
    if not cvEnable:GetBool() or HUD.Hidden then return end

    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end
    if hook.Run("SherlockHNS_ShouldDrawHUD") == false then return end

    local now = CurTime()
    for _, e in ipairs(GetSorted()) do
        if not e.failed then
            local ok, err = pcall(e.fn, now)
            if not ok then
                e.failed = true -- evita spam de erro a cada frame
                ErrorNoHalt("[HnS HUD] elemento '" .. e.id .. "' desativado: " .. tostring(err) .. "\n")
            end
        end
    end
end)

-- ===== HUD nativa das pills =====
-- pk_pill_cl_hidehud esconde vida, cloak, mira e nametags das pills.
timer.Create("SherlockHNS_HUD_HidePillHUD", 1, 0, function()
    if not HUD.HidePillHUD then return end
    local cv = pk_pills and pk_pills.convars and pk_pills.convars.cl_hidehud
    if cv and not cv:GetBool() then
        RunConsoleCommand("pk_pill_cl_hidehud", "1")
    end
end)
