-- Teclas configuráveis (cliente): tabela global de ações -> tecla.
-- Cada ação é um ConVar arquivado (hns_key_<id>), então vale entre sessões.
-- Uso nos módulos:  K.On("id", fn)  |  K.IsDown("id")  |  K.Name("id")

SherlockHNS.Keys = SherlockHNS.Keys or {}
local K = SherlockHNS.Keys

K.List = {
    { id = "menu",          label = "Abrir / fechar o menu",                             default = KEY_F2 },
    { id = "party_accept",  label = "Aceitar convite de party",                          default = KEY_F3 },
    { id = "party_decline", label = "Recusar convite de party",                          default = KEY_F4 },
    { id = "afk_yes",       label = "Votação de killer AFK: eu quero",                   default = KEY_F6 },
    { id = "afk_no",        label = "Votação de killer AFK: não quero",                  default = KEY_F7 },
    { id = "afk_self",      label = "Ficar AFK (ir para o menu)",                        default = 0 }, -- sem tecla por padrão
    { id = "poll",          label = "Enquete: segurar para liberar o mouse",             default = KEY_G, hold = true },
    { id = "modfile",       label = "Admin: abrir ficha do jogador (mira / espectando)", default = KEY_R },
    { id = "outfits",       label = "Abrir Outfits",                                     default = KEY_C },
}

K.ById, K.cv, K.Binders = {}, {}, setmetatable({}, { __mode = "k" })
local handlers, down = {}, {}

for _, def in ipairs(K.List) do
    K.ById[def.id] = def
    K.cv[def.id] = CreateClientConVar("hns_key_" .. def.id, tostring(def.default), true, false,
        "Tecla da ação '" .. def.id .. "' (código KEY_*, 0 = nenhuma)")
end

-- ===== Consulta =====
function K.Get(id)
    local cv = K.cv[id]
    return cv and math.floor(cv:GetInt()) or 0
end

function K.Name(id)
    local k = K.Get(id)
    if k <= 0 then return "NENHUMA" end
    return string.upper(input.GetKeyName(k) or "?")
end

function K.IsDown(id)
    local k = K.Get(id)
    return k > 0 and input.IsButtonDown(k)
end

function K.On(id, fn) handlers[id] = fn end

-- ===== Edição =====
-- Só teclado (sem mouse e sem ESC). Se outra ação usava a tecla, ela fica sem tecla.
function K.Set(id, key)
    local def = K.ById[id]
    key = math.floor(tonumber(key) or -1)
    if not def or key < 0 or key > KEY_LAST or key == KEY_ESCAPE then return false end

    if key > 0 then
        for _, other in ipairs(K.List) do
            if other.id ~= id and K.Get(other.id) == key then
                K.cv[other.id]:SetInt(0)
                notification.AddLegacy(("\"%s\" ficou sem tecla (conflito)."):format(other.label), NOTIFY_HINT, 4)
            end
        end
    end

    K.cv[id]:SetInt(key)
    down[id] = true -- exige soltar a tecla antes de disparar a ação
    return true
end

function K.ResetAll()
    for _, def in ipairs(K.List) do K.cv[def.id]:SetInt(def.default) end
end

-- ===== Detecção =====
local function CanListen()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return false end

    local focus = vgui.GetKeyboardFocus()
    if IsValid(focus) and focus.GetClassName and focus:GetClassName() == "TextEntry" then return false end

    for b in pairs(K.Binders) do
        if IsValid(b) and b.Trapping then return false end -- capturando uma tecla nova
    end
    return true
end

hook.Add("Think", "SherlockHNS_Keys", function()
    local listen

    for _, def in ipairs(K.List) do
        local key = K.Get(def.id)
        local d = key > 0 and input.IsButtonDown(key)
        local pressed = d and not down[def.id]
        down[def.id] = d

        local fn = handlers[def.id]
        if pressed and fn then
            if listen == nil then listen = CanListen() end
            if listen then fn() end
        end
    end
end)

-- Os binds nativos F2/F3/F4 passam a ser tratados só pela tabela acima
local nativeBinds = { gm_showteam = true, gm_showspare1 = true, gm_showspare2 = true }
hook.Add("PlayerBindPress", "SherlockHNS_KeysNative", function(_, bind, pressed)
    if nativeBinds[bind] then return true end
    -- o C padrão do GMod abre o context menu; bloqueia enquanto a tecla de Outfits for C
    if bind == "+menu_context" and K.Get("outfits") == KEY_C then return true end
end)

-- ===== UI (subaba "Teclas" das Configurações) =====
function K.BuildPanel(scroll, ui)
    local UU, F = ui.U, ui.F

    local hint = SherlockHNS.UI.Create("DLabel", scroll)
    hint:Dock(TOP)
    hint:DockMargin(0, 0, UU(16), UU(12))
    hint:SetTall(UU(26))
    hint:SetFont(F(16, 500))
    hint:SetTextColor(ui.dim)
    hint:SetWrap(true)
    hint:SetAutoStretchVertical(true)
    hint:SetText("Clique no botão da tecla e aperte a nova. ESC cancela. Se uma tecla já estiver em uso, " ..
        "a outra ação fica sem tecla.")

    for _, def in ipairs(K.List) do
        local row = SherlockHNS.UI.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(UU(44))
        row:DockMargin(0, 0, UU(16), UU(6))

        function row:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(255, 255, 255, 10))
            draw.SimpleText(def.label, F(18), UU(14), h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local reset = SherlockHNS.UI.Create("DButton", row)
        reset:Dock(RIGHT)
        reset:DockMargin(UU(6), UU(6), UU(6), UU(6))
        reset:SetWide(UU(100))
        reset:SetFont(F(16))
        reset:SetText("Padrão")
        reset.DoClick = function() K.Set(def.id, def.default) end

        local clear = SherlockHNS.UI.Create("DButton", row)
        clear:Dock(RIGHT)
        clear:DockMargin(UU(6), UU(6), 0, UU(6))
        clear:SetWide(UU(90))
        clear:SetFont(F(16))
        clear:SetText("Limpar")
        clear.DoClick = function() K.Set(def.id, 0) end

        local b = SherlockHNS.UI.Create("DBinder", row)
        b:Dock(RIGHT)
        b:DockMargin(UU(6), UU(6), 0, UU(6))
        b:SetWide(UU(160))
        b:SetFont(F(16))
        K.Binders[b] = true

        local loading = true
        b:SetValue(K.Get(def.id))
        loading = false

        b.OnChange = function(_, code)
            if loading then return end
            if not K.Set(def.id, code) then -- mouse / inválida: volta
                loading = true
                b:SetValue(K.Get(def.id))
                loading = false
            end
        end

        -- reflete mudanças vindas de fora (conflito, "Padrão", "Limpar")
        local old = b.Think
        function b:Think()
            if old then old(self) end
            if self.Trapping then return end
            local cur = K.Get(def.id)
            if self:GetValue() ~= cur then
                loading = true
                self:SetValue(cur)
                loading = false
            end
        end
    end

    local all = SherlockHNS.UI.Create("DButton", scroll)
    all:Dock(TOP)
    all:DockMargin(0, UU(10), UU(16), 0)
    all:SetTall(UU(40))
    all:SetFont(F(17))
    all:SetText("Restaurar todas as teclas padrão")
    all.DoClick = K.ResetAll
end
