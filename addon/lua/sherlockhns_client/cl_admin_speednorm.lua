-- Aba "Compatibilização" do painel admin (cliente): Pills > Compatibilização.
-- Usada por cl_admin.lua: inner:AddSheet("Compatibilização", SherlockHNS.BuildSpeedNormTab(inner), ...)
-- Shared: sh_speednorm.lua | Servidor: sv_speednorm.lua

local SN = SherlockHNS.SpeedNorm
local SP = SherlockHNS.Speed

local function SendConfig(key, value)
    net.Start("sherlockhns_admin_config")
    net.WriteString(key)
    net.WriteFloat(value)
    net.SendToServer()
end

local function FmtPly(s) return ("%d / %d"):format(math.Round(s.walk), math.Round(s.run)) end

function SherlockHNS.BuildSpeedNormTab(parent)
    local pnl = SherlockHNS.UI.Form(parent)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    local SECTIONS = {
        { "1. Velocidade base do player (runners sem pill)",  nil,                       { "SnBaseWalk", "SnBaseRun", "SnBaseCrouch", "SnBaseJump" } },
        { "2. Pills",                                         { "SnOn", "SnOverrides" }, { "SnRef", "SnCrouchPct", "SnBhopPhys" } },
        { "3. Equilíbrio runners x killers (só afeta pills)", nil,                       { "SnBias", "SnSwing" } },
    }

    for _, sec in ipairs(SECTIONS) do
        local head = SherlockHNS.UI.Create("DLabel", pnl)
        head:Dock(TOP); head:DockMargin(0, 14, 0, 4); head:SetTall(20)
        head:SetFont("DermaDefaultBold"); head:SetDark(true); head:SetText(sec[1])

        for _, key in ipairs(sec[2] or {}) do
            local t = SN.ToggleByKey[key]
            local c = SherlockHNS.UI.Create("DCheckBoxLabel", pnl)
            c:Dock(TOP); c:DockMargin(0, 0, 0, 6)
            c:SetText(t.label); c:SetDark(true); c:SetValue(SN.Toggle(key))
            function c:OnChange(val) SendConfig(key, val and 1 or 0) end
        end

        for _, key in ipairs(sec[3]) do
            local s = SN.SettingByKey[key]
            local sl = SherlockHNS.UI.Create("DNumSlider", pnl)
            sl:Dock(TOP); sl:DockMargin(0, 0, 16, 4)
            sl:SetText(s.label); sl:SetDark(true)
            sl:SetMin(s.min); sl:SetMax(s.max); sl:SetDecimals(0); sl:SetValue(SN.Num(key))
            sl.OnValueChanged = function(_, v)
                timer.Create("sherlockhns_slider_" .. key, 0.4, 1, function() SendConfig(key, v) end)
            end
        end
    end

    -- resumo: o que cada lado vai ter de teto
    local sum = SherlockHNS.UI.Create("DLabel", pnl)
    sum:Dock(TOP); sum:DockMargin(0, 10, 0, 0); sum:SetTall(20); sum:SetDark(true)
    function sum:Think()
        local ref = SN.Reference("ply")
        self:SetText(("Teto de pill normalizada: runner %d | killer %d   (runner sem pill: %d / %d)")
            :format(ref * SN.TeamFactor(TEAM_HIDERS), ref * SN.TeamFactor(TEAM_KILLERS),
                SN.Num("SnBaseWalk"), SN.Num("SnBaseRun")))
    end

    -- ===== Prévia =====
    local head = SherlockHNS.UI.Create("DLabel", pnl)
    head:Dock(TOP)
    head:DockMargin(0, 14, 0, 4)
    head:SetTall(20)
    head:SetFont("DermaDefaultBold")
    head:SetDark(true)

    local note = SherlockHNS.UI.Create("DLabel", pnl)
    note:Dock(TOP)
    note:DockMargin(0, 0, 0, 4)
    note:SetWrap(true)
    note:SetAutoStretchVertical(true)
    note:SetDark(true)
    note:SetText("Prévia sem overrides. Costume: walk / run. Física: primeira chave de velocidade do drive. " ..
        "Para excluir uma pill, defina hnsSpeedNorm = false na formTable.")

    local search = SherlockHNS.UI.Create("DTextEntry", pnl)
    search:Dock(TOP)
    search:DockMargin(0, 0, 0, 4)
    search:SetPlaceholderText("Buscar pill...")

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(TOP)
    list:SetTall(430)
    list:SetMultiSelect(false)
    list:AddColumn("Pill")
    list:AddColumn("Tipo"):SetFixedWidth(60)
    list:AddColumn("Original"):SetFixedWidth(110)
    list:AddColumn("Runner"):SetFixedWidth(110)
    list:AddColumn("Killer"):SetFixedWidth(110)

    local function Fill()
        if not IsValid(list) then return end

        head:SetText("Prévia da compatibilização" ..
        (SN.Toggle("SnOn") and "" or "  (opção desligada: valores abaixo são só simulação)"))

        local filter, rows = string.lower(search:GetValue() or ""), {}
        for name, t in pairs((pk_pills and pk_pills.Forms) or {}) do
            if istable(t) and t.printName and (t.type == "ply" or t.type == "phys") then
                local label = tostring(t.printName)
                if filter == "" or label:lower():find(filter, 1, true) or name:lower():find(filter, 1, true) then
                    rows[#rows + 1] = { name = name, label = label, t = t }
                end
            end
        end
        table.sort(rows, function(a, b) return a.label:lower() < b.label:lower() end)

        local lp = LocalPlayer()
        list:Clear()
        for _, r in ipairs(rows) do
            local t = r.t
            if t.type == "ply" then
                list:AddLine(r.label, "costume",
                    FmtPly(SP.PlyOriginal(t)),
                    FmtPly(SN.PlySpeeds(t, lp, nil, TEAM_HIDERS, true)),
                    FmtPly(SN.PlySpeeds(t, lp, nil, TEAM_KILLERS, true)))
            else
                local k = SN.DriveKeys(t)[1]
                if k then
                    local function V(d) return ("%s %.0f"):format(k, d[k] or 0) end
                    list:AddLine(r.label, "física", V(t.driveOptions),
                        V(SN.DriveOptions(t, TEAM_HIDERS, nil, true)),
                        V(SN.DriveOptions(t, TEAM_KILLERS, nil, true)))
                else
                    list:AddLine(r.label, "física", "-", "-", "-")
                end
            end
        end
    end

    search.OnChange = Fill
    Fill()

    -- as globals chegam depois do envio: recalcula quando a configuração mudar
    local lastSig, nextCheck = SN.Signature(), 0
    function pnl:Think()
        if CurTime() < nextCheck then return end
        nextCheck = CurTime() + 0.4

        local sig = SN.Signature()
        if sig ~= lastSig then
            lastSig = sig
            Fill()
        end
    end

    return pnl
end
