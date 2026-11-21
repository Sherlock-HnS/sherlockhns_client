-- Abas do spawnmenu nativo (Props, Veículos, Armas, Pills) dentro do painel Q.
-- Usa spawnmenu.GetCreationTabs(): as mesmas abas que o sandbox usa.
-- Os painéis são criados 1x e reaproveitados (reparent) a cada abertura do Q.

SherlockHNS.Creation = SherlockHNS.Creation or {}
local C = SherlockHNS.Creation

C.Tabs = {
    { name = "Props",    icon = "icon16/box.png",  keys = { "#spawnmenu.content_tab", "#spawnmenu.category.props" } },
    { name = "Veículos", icon = "icon16/car.png",  keys = { "#spawnmenu.category.vehicles" } },
    { name = "Armas",    icon = "icon16/gun.png",  keys = { "#spawnmenu.category.weapons" } },
    { name = "Pills",    icon = "icon16/pill.png", keys = { "Pills" },                                              pillBar = true },
}

local cache = {}

-- O conteúdo do sandbox referencia g_SpawnMenu (criado pelo spawnmenu.lua, que não usamos).
-- Stub inerte: qualquer método/campo vira no-op e devolve o próprio stub.
local function MakeStub()
    local stub = {}
    setmetatable(stub, {
        __index = function(_, k)
            if k == "IsValid" or k == "IsVisible" then return function() return false end end
            return stub
        end,
        __call = function() return stub end,
    })
    return stub
end

local function EnsureSpawnMenuStub()
    if g_SpawnMenu == nil then g_SpawnMenu = MakeStub() end
end

local function FindTab(def)
    local tabs = spawnmenu.GetCreationTabs()
    for _, k in ipairs(def.keys) do
        if tabs[k] then return tabs[k] end
    end

    print("[HnS] Aba '" .. def.name .. "' não encontrada. Abas disponíveis:")
    for k in pairs(tabs) do print("   " .. tostring(k)) end
end

local function Message(body, text)
    local l = SherlockHNS.UI.Create("DLabel", body)
    l:Dock(FILL)
    l:SetDark(true)
    l:SetContentAlignment(5)
    l:SetText(text)
end

local function Attach(def, body)
    EnsureSpawnMenuStub()

    local p = cache[def.name]

    if not IsValid(p) then
        local tab = FindTab(def)
        if not tab then return Message(body, "Aba indisponível (veja o console).") end

        local ok, res = pcall(tab.Function)
        if not ok or not IsValid(res) then
            ErrorNoHalt("[HnS] Falha ao criar a aba '" .. def.name .. "': " .. tostring(res) .. "\n")
            return Message(body, "Erro ao criar a aba (veja o console).")
        end

        p = res
        cache[def.name] = p
    end

    p:SetParent(body)
    p:SetVisible(true)
    p:Dock(FILL)
end

-- Chame ANTES de remover o frame: tira os painéis de dentro dele para não serem destruídos
function C.Detach()
    for _, p in pairs(cache) do
        if IsValid(p) then
            p:SetVisible(false)
            p:SetParent(nil)
        end
    end
end

function SherlockHNS.BuildCreationTab(sheet, def)
    local holder = SherlockHNS.UI.Create("DPanel", sheet)
    holder:SetPaintBackground(false)
    holder:DockPadding(4, 4, 4, 4)

    -- barra extra só da aba Pills
    if def.pillBar then
        local bar = SherlockHNS.UI.Create("DPanel", holder)
        SherlockHNS.UI.Flow(bar)
        bar:Dock(TOP)
        bar:SetTall(32)
        bar:DockMargin(0, 0, 0, 4)
        bar:SetPaintBackground(false)

        local function Btn(text, wide, cmd)
            local b = SherlockHNS.UI.Create("DButton", bar)
            b:Dock(LEFT)
            b:DockMargin(0, 0, 6, 0)
            b:SetWide(wide)
            b:SetText(text)
            b.DoClick = function() RunConsoleCommand(cmd) end
        end

        Btn("Remover pill", 150, "hns_pill_remove")
        Btn("Voltar a runner", 150, "hns_runner")
    end

    local body = SherlockHNS.UI.Create("DPanel", holder)
    body:Dock(FILL)
    body:SetPaintBackground(false)

    -- cria só quando a aba aparece pela primeira vez (props demora um pouco)
    local built = false
    function holder:Paint()
        if built then return end
        built = true
        timer.Simple(0, function()
            if IsValid(body) then Attach(def, body) end
        end)
    end

    return holder
end
