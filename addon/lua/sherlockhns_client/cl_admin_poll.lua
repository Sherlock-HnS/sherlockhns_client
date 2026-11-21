-- Aba "Enquete" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Enquete", SherlockHNS.BuildPollTab(sheet), "icon16/chart_bar.png")

local P = SherlockHNS.Poll

local function Send(act, fn)
    net.Start("sherlockhns_poll_admin")
    net.WriteUInt(act, 2)
    if fn then fn() end
    net.SendToServer()
end

function SherlockHNS.BuildPollTab(sheet)
    local pnl = SherlockHNS.UI.Form(sheet)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    local question = SherlockHNS.UI.Create("DTextEntry", pnl)
    question:Dock(TOP)
    question:DockMargin(0, 0, 0, 6)
    question:SetPlaceholderText("Pergunta")
    question:SetMaximumCharCount(P.MaxQuestion)

    local entries = {}
    for i = 1, P.MaxOptions do
        local e = SherlockHNS.UI.Create("DTextEntry", pnl)
        e:Dock(TOP)
        e:DockMargin(0, 0, 0, 3)
        e:SetPlaceholderText("Resposta " .. i .. (i > 2 and " (opcional)" or ""))
        e:SetMaximumCharCount(P.MaxOption)
        entries[i] = e
    end

    local dur = SherlockHNS.UI.Create("DNumSlider", pnl)
    dur:Dock(TOP)
    dur:DockMargin(0, 6, 0, 0)
    dur:SetText("Duração (s) - 0 = até encerrar")
    dur:SetDark(true)
    dur:SetMin(0)
    dur:SetMax(P.MaxDuration)
    dur:SetDecimals(0)
    dur:SetValue(60)

    local row = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(row)
    row:Dock(TOP)
    row:DockMargin(0, 6, 0, 6)
    row:SetTall(28)
    row:SetPaintBackground(false)

    local function Btn(text, fn)
        local b = SherlockHNS.UI.Create("DButton", row)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(150)
        b:SetText(text)
        b.DoClick = fn
    end

    Btn("Lançar enquete", function()
        local opts = {}
        for _, e in ipairs(entries) do
            local v = string.Trim(e:GetValue())
            if v ~= "" then opts[#opts + 1] = v end
        end

        Send(P.ACT.LAUNCH, function()
            net.WriteString(string.Trim(question:GetValue()))
            net.WriteUInt(#opts, 4)
            for _, o in ipairs(opts) do net.WriteString(o) end
            net.WriteUInt(math.floor(dur:GetValue()), 10)
        end)
    end)

    Btn("Encerrar enquete", function() Send(P.ACT.CLOSE) end)

    Btn("Limpar campos", function()
        question:SetValue("")
        for _, e in ipairs(entries) do e:SetValue("") end
    end)

    -- resultado ao vivo
    local status = SherlockHNS.UI.Create("DLabel", pnl)
    status:Dock(TOP)
    status:SetWrap(true)
    status:SetAutoStretchVertical(true)
    status:SetDark(true)
    status:SetContentAlignment(7)

    function status:Think()
        local c = P.GetCurrent()
        if not c then
            self:SetText("Nenhuma enquete ativa.")
            return
        end

        local lines, total = {}, 0
        for i, o in ipairs(c.options) do
            lines[#lines + 1] = ("%s: %d"):format(o, c.counts[i] or 0)
            total = total + (c.counts[i] or 0)
        end
        self:SetText("Ativa: " .. c.question .. "  (" .. total .. " votos)\n" .. table.concat(lines, "\n"))
    end

    return pnl
end
