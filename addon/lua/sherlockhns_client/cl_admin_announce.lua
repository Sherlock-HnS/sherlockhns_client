-- Aba "Anúncio" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Anúncio", SherlockHNS.BuildAnnounceTab(sheet), "icon16/bell.png")

local A = SherlockHNS.Announce

function SherlockHNS.BuildAnnounceTab(sheet)
    local pnl = SherlockHNS.UI.Form(sheet)
    pnl.Paint = nil
    pnl:DockPadding(10, 10, 10, 10)

    local title = SherlockHNS.UI.Create("DTextEntry", pnl)
    title:Dock(TOP)
    title:DockMargin(0, 0, 0, 6)
    title:SetPlaceholderText("Título")
    title:SetMaximumCharCount(A.MaxTitle)

    local subtitle = SherlockHNS.UI.Create("DTextEntry", pnl)
    subtitle:Dock(TOP)
    subtitle:DockMargin(0, 0, 0, 6)
    subtitle:SetPlaceholderText("Subtítulo (opcional)")
    subtitle:SetMaximumCharCount(A.MaxSubtitle)

    local dur = SherlockHNS.UI.Create("DNumSlider", pnl)
    dur:Dock(TOP)
    dur:DockMargin(0, 0, 0, 6)
    dur:SetText("Duração (s)")
    dur:SetDark(true)
    dur:SetMin(A.MinDuration)
    dur:SetMax(A.MaxDuration)
    dur:SetDecimals(0)
    dur:SetValue(A.DefaultDuration)

    local row = SherlockHNS.UI.Create("DPanel", pnl)
    SherlockHNS.UI.Flow(row)
    row:Dock(TOP)
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

    Btn("Enviar anúncio", function()
        local t = string.Trim(title:GetValue())
        if t == "" then
            notification.AddLegacy("Preencha o título.", NOTIFY_ERROR, 3)
            return
        end

        net.Start("sherlockhns_announce_admin")
        net.WriteString(t)
        net.WriteString(string.Trim(subtitle:GetValue()))
        net.WriteUInt(math.floor(dur:GetValue()), 8)
        net.SendToServer()
    end)

    Btn("Limpar campos", function()
        title:SetValue("")
        subtitle:SetValue("")
    end)

    local hint = SherlockHNS.UI.Create("DLabel", pnl)
    hint:Dock(TOP)
    hint:DockMargin(0, 10, 0, 0)
    hint:SetTall(20)
    hint:SetDark(true)
    hint:SetText("Console: hns_announce \"Título\" \"Subtítulo\" [segundos]")

    return pnl
end
