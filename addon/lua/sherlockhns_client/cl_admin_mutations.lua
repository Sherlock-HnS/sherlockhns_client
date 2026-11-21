-- Aba "Mutações" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Mutações", SherlockHNS.BuildMutationsTab(sheet), "icon16/lightning.png")

local COL_WARN = Color(200, 90, 0)

local function SendConfig(key, value)
    net.Start("sherlockhns_admin_config")
    net.WriteString(key)
    net.WriteFloat(value)
    net.SendToServer()
end

local function SendAction(action)
    net.Start("sherlockhns_admin_action")
    net.WriteString(action)
    net.SendToServer()
end

local function SendJuggerWeaponSet(classes)
    net.Start("sherlockhns_admin_jugger_weapons")
    net.WriteTable(classes)
    net.SendToServer()
end

local function AddSlider(parent, s)
    local sl = SherlockHNS.UI.Create("DNumSlider", parent)
    sl:Dock(TOP)
    sl:DockMargin(0, 0, 0, 4)
    sl:SetText(s.label)
    sl:SetDark(true)
    sl:SetMin(s.min)
    sl:SetMax(s.max)
    sl:SetDecimals(0)
    sl:SetValue(GetGlobalInt("sherlockhns_cfg_" .. s.key, s.default))

    -- definido depois do SetValue para não enviar na abertura
    sl.OnValueChanged = function(_, v)
        timer.Create("sherlockhns_slider_" .. s.key, 0.4, 1, function()
            SendConfig(s.key, v)
        end)
    end
    return sl
end

function SherlockHNS.BuildMutationsTab(sheet)
    local M = SherlockHNS.Mutation

    local root = SherlockHNS.UI.Create("DPanel", sheet)
    root.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, SherlockHNS.UI.Colors.background) end
    local tabs = SherlockHNS.UI.Create("DPropertySheet", root)
    tabs:Dock(FILL)

    local pnl = SherlockHNS.UI.Create("DPanel", tabs)
    pnl.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, SherlockHNS.UI.Colors.background) end
    pnl:DockPadding(10, 10, 10, 10)

    local status = SherlockHNS.UI.Create("DLabel", pnl)
    status:Dock(TOP)
    status:SetTall(24)
    status:SetFont("DermaDefaultBold")
    status:SetDark(true)
    function status:Think()
        local names = {}
        for _, id in ipairs(M.GetActive()) do names[#names + 1] = M.ById[id].name end
        self:SetText("Mutações ativas: " .. (#names > 0 and table.concat(names, ", ") or "nenhuma"))
    end

    local stop = SherlockHNS.UI.Create("DButton", pnl)
    stop:Dock(BOTTOM)
    stop:DockMargin(0, 6, 0, 0)
    stop:SetTall(28)
    stop:SetText("Encerrar mutações / limpar agendamento")
    stop.DoClick = function() SendAction("mut_stop") end

    local scroll = SherlockHNS.UI.Create("DScrollPanel", pnl)
    scroll:Dock(FILL)
    scroll.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, SherlockHNS.UI.Colors.background) end
    scroll:GetCanvas().Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, SherlockHNS.UI.Colors.background) end

    -- teto de mutações simultâneas no sorteio
    AddSlider(scroll, M.MaxSetting)

    for _, def in ipairs(M.List) do
        local head = SherlockHNS.UI.Create("DLabel", scroll)
        head:Dock(TOP)
        head:DockMargin(0, 14, 0, 2)
        head:SetTall(22)
        head:SetFont("DermaDefaultBold")
        head:SetDark(true)
        head:SetText(def.name .. "  -  " .. def.desc)

        -- indicação de incompatibilidade
        local conflicts = M.ConflictList(def.id)
        if #conflicts > 0 then
            local names = {}
            for _, id in ipairs(conflicts) do names[#names + 1] = M.ById[id].name end

            local warn = SherlockHNS.UI.Create("DLabel", scroll)
            warn:Dock(TOP)
            warn:DockMargin(0, 0, 0, 4)
            warn:SetTall(18)
            warn:SetTextColor(COL_WARN)
            warn:SetText("Incompatível com: " .. table.concat(names, ", "))
        end

        local on = SherlockHNS.UI.Create("DCheckBoxLabel", scroll)
        on:Dock(TOP)
        on:DockMargin(0, 0, 0, 6)
        on:SetText("Habilitada no sorteio")
        on:SetDark(true)
        on:SetValue(GetGlobalBool("sherlockhns_mut_on_" .. def.id, true))
        function on:OnChange(val)
            SendConfig(M.EnabledKey(def.id), val and 1 or 0)
        end

        -- chance individual + sliders próprios
        AddSlider(scroll, def.chanceSetting)
        for _, s in ipairs(def.settings or {}) do AddSlider(scroll, s) end

        local force = SherlockHNS.UI.Create("DButton", scroll)
        force:Dock(TOP)
        force:DockMargin(0, 2, 16, 0)
        force:SetTall(26)
        force.DoClick = function() SendAction("mut_" .. def.id) end

        local lastTxt
        function force:Think()
            local clash = M.FirstConflict(def.id, M.GetActive())
            local txt, enabled

            if M.Is(def.id) then
                txt, enabled = "Já está ativa", false
            elseif clash then
                txt, enabled = "Incompatível com a ativa: " .. M.ById[clash].name, false
            else
                txt, enabled = "Forçar (agora na rodada, ou na próxima)", true
            end

            if txt ~= lastTxt then
                lastTxt = txt
                self:SetText(txt)
            end
            self:SetEnabled(enabled)
        end
    end

    tabs:AddSheet("Mutações", pnl, "icon16/lightning.png")

    local weaponsPanel = SherlockHNS.UI.Create("DPanel", tabs)
    weaponsPanel.Paint = function(_, w, h) draw.RoundedBox(0, 0, 0, w, h, SherlockHNS.UI.Colors.background) end
    weaponsPanel:DockPadding(12, 12, 12, 12)
    local hint = SherlockHNS.UI.Create("DLabel", weaponsPanel)
    hint:Dock(TOP)
    hint:SetTall(36)
    hint:SetWrap(true)
    hint:SetDark(true)
    hint:SetText("Armas entregues aos jogadores vivos enquanto Juggernaut estiver ativo. Selecione as disponíveis e adicione ao loadout.")

    local search = SherlockHNS.UI.Create("DTextEntry", weaponsPanel)
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, 8)
    search:SetTall(28)
    search:SetPlaceholderText("Buscar arma ou classe...")

    local lists = SherlockHNS.UI.Create("DPanel", weaponsPanel)
    lists:Dock(FILL)
    lists:SetPaintBackground(false)
    local available = SherlockHNS.UI.Create("DListView", lists)
    available:Dock(LEFT)
    available:SetWide(420)
    SherlockHNS.UI.Split(lists, available, 420, 760)
    available:DockMargin(0, 0, 8, 0)
    available:SetMultiSelect(true)
    available:AddColumn("Armas e SWEPs disponíveis")
    available:AddColumn("Classe")
    local selected = SherlockHNS.UI.Create("DListView", lists)
    selected:Dock(FILL)
    selected:SetMultiSelect(true)
    selected:AddColumn("Loadout Juggernaut")
    selected:AddColumn("Classe")

    local actions = SherlockHNS.UI.Create("DPanel", weaponsPanel)
    SherlockHNS.UI.Flow(actions)
    actions:Dock(BOTTOM)
    actions:DockMargin(0, 8, 0, 0)
    actions:SetTall(30)
    actions:SetPaintBackground(false)
    local function Button(label, callback)
        local button = SherlockHNS.UI.Create("DButton", actions)
        button:Dock(LEFT)
        button:DockMargin(0, 0, 6, 0)
        button:SetWide(label == "Aplicar alterações" and 170 or 210)
        button:SetText(label)
        button.DoClick = callback
    end

    local catalog = {}
    for _, swep in ipairs(weapons.GetList() or {}) do
        local class = swep.ClassName or swep.Class
        if isstring(class) and class ~= "" then
            catalog[class] = { class = class, name = (swep.PrintName and swep.PrintName ~= "" and swep.PrintName) or class }
        end
    end
    for _, class in ipairs(SherlockHNS.AdminJuggerWeapons or {}) do
        catalog[class] = catalog[class] or { class = class, name = class }
    end
    local ordered = {}
    for _, item in pairs(catalog) do ordered[#ordered + 1] = item end
    table.sort(ordered, function(a, b) return a.name:lower() == b.name:lower() and a.class < b.class or a.name:lower() < b.name:lower() end)

    local current = {}
    for _, class in ipairs(SherlockHNS.AdminJuggerWeapons or {}) do current[class] = true end
    local function RefreshLists()
        if not IsValid(search) or not IsValid(available) or not IsValid(selected) then return end
        local filter = string.lower(search:GetValue() or "")
        available:Clear()
        selected:Clear()
        for _, item in ipairs(ordered) do
            local matches = filter == "" or item.name:lower():find(filter, 1, true) or item.class:lower():find(filter, 1, true)
            if current[item.class] then
                local line = selected:AddLine(item.name, item.class)
                line.weaponClass = item.class
                for _, column in ipairs(line.Columns) do column:SetTextColor(SherlockHNS.UI.Colors.text) end
            elseif matches then
                local line = available:AddLine(item.name, item.class)
                line.weaponClass = item.class
                for _, column in ipairs(line.Columns) do column:SetTextColor(SherlockHNS.UI.Colors.text) end
            end
        end
    end
    local function SelectedClasses(list)
        local out = {}
        for _, line in ipairs(list:GetSelected()) do out[#out + 1] = line.weaponClass end
        return out
    end
    local function UpdateSet(add)
        local source = add and available or selected
        for _, class in ipairs(SelectedClasses(source)) do current[class] = add and true or nil end
        RefreshLists()
    end
    Button("Adicionar selecionadas →", function() UpdateSet(true) end)
    Button("← Remover selecionadas", function() UpdateSet(false) end)
    Button("Aplicar alterações", function()
        local out = {}
        for _, item in ipairs(ordered) do if current[item.class] then out[#out + 1] = item.class end end
        SendJuggerWeaponSet(out)
    end)
    available.DoDoubleClick = function(_, _, line) current[line.weaponClass] = true; RefreshLists() end
    selected.DoDoubleClick = function(_, _, line) current[line.weaponClass] = nil; RefreshLists() end
    search.OnChange = RefreshLists
    RefreshLists()
    local refreshJuggerWeaponLists = function()
        if not IsValid(search) or not IsValid(available) or not IsValid(selected) then return end
        current = {}
        for _, class in ipairs(SherlockHNS.AdminJuggerWeapons or {}) do current[class] = true end
        RefreshLists()
    end
    SherlockHNS.RefreshJuggerWeaponLists = refreshJuggerWeaponLists
    weaponsPanel.OnRemove = function()
        if SherlockHNS.RefreshJuggerWeaponLists == refreshJuggerWeaponLists then
            SherlockHNS.RefreshJuggerWeaponLists = nil
        end
    end
    tabs:AddSheet("Armas Juggernaut", weaponsPanel, "icon16/gun.png")

    return root
end
