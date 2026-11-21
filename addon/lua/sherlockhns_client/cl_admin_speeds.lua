-- Aba "Velocidades" do painel admin (cliente).
-- Chamada por cl_admin.lua: SherlockHNS.BuildSpeedsTab(parent)
-- Protocolo: veja sv_speed.lua (ops 1=set, 2=clear campo, 3=clear pill, 4=clear tudo).

local SP = SherlockHNS.Speed

local OP_SET, OP_CLEAR, OP_CLEAR_PILL, OP_CLEAR_ALL = 1, 2, 3, 4
local MAX_NAMES = 1023

local overrides = {} -- [pill] = { walk, run, ducked, jump, drive = {k=v} }
local panelRef

local function PillTable(name)
    local t = pk_pills and pk_pills.getPillTable and pk_pills.getPillTable(name)
    if t and t.printName then return t end
end

local function AllPills()
    local out = {}
    for name, t in pairs((pk_pills and pk_pills.Forms) or {}) do
        if istable(t) and t.printName and (t.type == "ply" or t.type == "phys") then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

-- Valor de override de um campo na pill (nil se não há)
local function OverrideOf(name, field)
    local ov = overrides[name]
    if not ov then return nil end

    local kind, key = SP.ParseField(field)
    if kind == "move" then return ov[key] end
    if kind == "drive" then return ov.drive and ov.drive[key] end
end

local function Summary(name)
    local ov = overrides[name]
    if not ov then return "" end

    local parts = {}
    for _, f in ipairs(SP.MoveFields) do
        if ov[f.id] then parts[#parts + 1] = f.short .. "=" .. math.Round(ov[f.id], 1) end
    end
    for k, v in SortedPairs(ov.drive or {}) do
        parts[#parts + 1] = k .. "=" .. math.Round(v, 1)
    end
    return table.concat(parts, "  ")
end

-- ===== Envio =====
local function SendBatch(op, field, value, names)
    -- parte em lotes caso passe do limite do UInt(10)
    local i = 1
    repeat
        local n = math.min(MAX_NAMES, #names - i + 1)

        net.Start("sherlockhns_speed_set")
        net.WriteUInt(op, 3)
        if op == OP_SET or op == OP_CLEAR then net.WriteString(field) end
        if op == OP_SET then net.WriteFloat(value) end
        net.WriteUInt(n, 10)
        for j = i, i + n - 1 do net.WriteString(names[j]) end
        net.SendToServer()

        i = i + n
    until i > #names
end

net.Receive("sherlockhns_speed_sync", function()
    overrides = {}
    for _, e in ipairs(util.JSONToTable(net.ReadString()) or {}) do
        if istable(e) and isstring(e.pill) then
            local ov = { walk = e.walk, run = e.run, ducked = e.ducked, jump = e.jump }

            if istable(e.drive) then
                ov.drive = {}
                for k, v in pairs(e.drive) do ov.drive[k] = v end
            end
            overrides[e.pill] = ov
        end
    end

    if IsValid(panelRef) and panelRef.Refresh then panelRef:Refresh() end
end)

-- ===== UI =====
function SherlockHNS.BuildSpeedsTab(parent)
    local root = SherlockHNS.UI.Create("DPanel", parent)
    root:Dock(FILL)
    root.Paint = nil
    panelRef = root

    -- Esquerda: busca + lista de pills (seleção múltipla)
    local left = SherlockHNS.UI.Create("DPanel", root)
    left:Dock(LEFT)
    left:SetWide(320)
    SherlockHNS.UI.Split(root, left, 320, 1000)
    left:DockMargin(0, 0, 6, 0)
    left.Paint = nil

    local search = SherlockHNS.UI.Create("DTextEntry", left)
    search:Dock(TOP)
    search:SetPlaceholderText("Buscar pill…")
    search:SetUpdateOnType(true)

    local list = SherlockHNS.UI.Create("DListView", left)
    list:Dock(FILL)
    list:DockMargin(0, 4, 0, 0)
    list:SetMultiSelect(true)
    list:AddColumn("Pill")
    list:AddColumn("Tipo"):SetFixedWidth(50)
    list:AddColumn("Overrides")

    -- Direita: campos da pill selecionada
    local right = SherlockHNS.UI.Create("DPanel", root)
    right:Dock(FILL)
    right.Paint = nil

    local title = SherlockHNS.UI.Create("DLabel", right)
    title:Dock(TOP)
    title:SetTall(22)
    title:SetText("Selecione uma ou mais pills")
    title:SetFont("DermaDefaultBold")

    local fieldsScroll = SherlockHNS.UI.Form(right)
    fieldsScroll:Dock(FILL)
    local fieldsBox = SherlockHNS.UI.Create("DPanel", fieldsScroll)
    fieldsBox:Dock(TOP)
    fieldsBox.Paint = nil

    local function Selected()
        local out = {}
        for _, line in ipairs(list:GetSelected()) do out[#out + 1] = line.pillName end
        return out
    end

    local function BuildFields()
        fieldsBox:Clear()

        local names = Selected()
        if #names == 0 then
            title:SetText("Selecione uma ou mais pills")
            fieldsBox:SetTall(0)
            return
        end

        local first = PillTable(names[1])
        local fields = SP.Fields(first)

        title:SetText(#names == 1 and (first.printName .. "  (" .. names[1] .. ")")
            or (#names .. " pills selecionadas — campos de " .. names[1]))

        for _, f in ipairs(fields) do
            local row = SherlockHNS.UI.Create("DPanel", fieldsBox)
            SherlockHNS.UI.Flow(row)
            row:Dock(TOP)
            row:SetTall(26)
            row:DockMargin(0, 2, 0, 0)
            row.Paint = nil

            local lbl = SherlockHNS.UI.Create("DLabel", row)
            lbl:Dock(LEFT)
            lbl:SetWide(140)
            lbl:SetText(f.label)

            local orig = SherlockHNS.UI.Create("DLabel", row)
            orig:Dock(LEFT)
            orig:SetWide(90)
            orig:SetText("orig: " .. math.Round(f.orig, 1))

            local cur = OverrideOf(names[1], f.id)

            local entry = SherlockHNS.UI.Create("DTextEntry", row)
            entry:Dock(LEFT)
            entry:SetWide(90)
            entry:SetNumeric(true)
            entry:SetText(tostring(cur or math.Round(f.orig, 1)))

            local apply = SherlockHNS.UI.Create("DButton", row)
            apply:Dock(LEFT)
            apply:SetWide(70)
            apply:DockMargin(4, 0, 0, 0)
            apply:SetText("Aplicar")
            apply.DoClick = function()
                local v = tonumber(entry:GetValue())
                if not v then return end
                SendBatch(OP_SET, f.id, math.Clamp(v, SP.Min, SP.Max), Selected())
            end

            local reset = SherlockHNS.UI.Create("DButton", row)
            reset:Dock(LEFT)
            reset:SetWide(70)
            reset:DockMargin(4, 0, 0, 0)
            reset:SetText("Original")
            reset:SetEnabled(cur ~= nil)
            reset.DoClick = function() SendBatch(OP_CLEAR, f.id, nil, Selected()) end
        end

        local clearPill = SherlockHNS.UI.Create("DButton", fieldsBox)
        clearPill:Dock(TOP)
        clearPill:SetTall(26)
        clearPill:DockMargin(0, 8, 0, 0)
        clearPill:SetText("Restaurar todas as velocidades da(s) pill(s) selecionada(s)")
        clearPill.DoClick = function() SendBatch(OP_CLEAR_PILL, nil, nil, Selected()) end

        -- altura explícita: com filhos docados, SizeToChildren dá 0 antes do primeiro layout
        fieldsBox.Think = function(self) self:SizeToChildren(false, true) end
    end

    local clearAll = SherlockHNS.UI.Create("DButton", right)
    clearAll:Dock(BOTTOM)
    clearAll:SetTall(26)
    clearAll:SetText("Restaurar TODAS as pills (apaga todos os overrides)")
    clearAll.DoClick = function()
        Derma_Query("Apagar todos os overrides de velocidade?", "Confirmar",
            "Sim", function()
                net.Start("sherlockhns_speed_set")
                net.WriteUInt(OP_CLEAR_ALL, 3)
                net.SendToServer()
            end, "Não")
    end

    local pills = AllPills()

    function root:Refresh()
        local keep = {}
        for _, n in ipairs(Selected()) do keep[n] = true end

        list:Clear()
        local q = string.lower(search:GetValue() or "")

        for _, name in ipairs(pills) do
            local t = PillTable(name)
            local hay = string.lower(name .. " " .. (t.printName or ""))
            if q == "" or string.find(hay, q, 1, true) then
                local line = list:AddLine(t.printName or name, t.type, Summary(name))
                line.pillName = name
                if keep[name] then list:SelectItem(line) end
            end
        end
        BuildFields()
    end

    list.OnRowSelected = function()
        timer.Create("HnSSpeedFields", 0, 1, function()
            if IsValid(root) then BuildFields() end
        end)
    end
    search.OnValueChange = function() root:Refresh() end

    root:Refresh()

    net.Start("sherlockhns_speed_request")
    net.SendToServer()

    return root
end
