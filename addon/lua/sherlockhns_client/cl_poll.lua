-- Enquetes (cliente): segure G para liberar o mouse e votar.
-- Servidor: gamemode/sv_poll.lua | Shared: gamemode/sh_poll.lua
-- Visual provisório: o update de visual refaz OpenPanel e o HUDPaint.

local SH = SherlockHNS
local P  = SH.Poll

local panel
-- { id, question, options, endAt, counts, mine }
local cur

function P.GetCurrent() return cur end

-- ===== Rede =====
net.Receive("sherlockhns_poll_open", function()
    local id       = net.ReadUInt(16)
    local question = net.ReadString()
    local options  = {}
    for i = 1, net.ReadUInt(4) do options[i] = net.ReadString() end
    local endAt  = net.ReadFloat()
    local mine   = net.ReadUInt(4)

    local counts = {}
    for i = 1, #options do counts[i] = 0 end

    if IsValid(panel) then panel:Remove() end
    cur = {
        id       = id,
        question = question,
        options  = options,
        endAt    = endAt,
        counts   = counts,
        mine     = mine > 0 and mine or nil,
    }

    surface.PlaySound("buttons/blip1.wav")
end)

net.Receive("sherlockhns_poll_counts", function()
    local id, n = net.ReadUInt(16), net.ReadUInt(4)
    local counts = {}
    for i = 1, n do counts[i] = net.ReadUInt(10) end

    if cur and cur.id == id then cur.counts = counts end
end)

net.Receive("sherlockhns_poll_close", function()
    local id = net.ReadUInt(16)
    if cur and cur.id == id then
        cur = nil
        if IsValid(panel) then panel:Remove() end
    end
end)

hook.Add("InitPostEntity", "SherlockHNS_PollRequest", function()
    net.Start("sherlockhns_poll_request")
    net.SendToServer()
end)

local function SendVote(i)
    if not cur then return end
    cur.mine = i
    surface.PlaySound("ui/buttonclick.wav")

    net.Start("sherlockhns_poll_vote")
    net.WriteUInt(cur.id, 16)
    net.WriteUInt(i, 4)
    net.SendToServer()
end

-- ===== Painel (provisório) =====
local function OpenPanel()
    local n = #cur.options
    local w, rowH, gap, header = 520, 40, 6, 70
    local h = header + n * (rowH + gap) + 12

    panel = SherlockHNS.UI.Create("DPanel")
    SherlockHNS.UI.Window(panel, w, h, 90)
    local body = SherlockHNS.UI.Create("DScrollPanel", panel)
    body:Dock(FILL); body:DockMargin(12, header, 12, 12)
    panel:MakePopup()
    panel:SetKeyboardInputEnabled(false) -- mouse livre, mas ainda dá para andar

    function panel:Paint(pw, ph)
        draw.RoundedBox(8, 0, 0, pw, ph, Color(15, 15, 20, 235))
        if not cur then return end

        draw.SimpleText("ENQUETE", "DermaDefaultBold", 16, 10, Color(180, 136, 0))
        draw.SimpleText(SherlockHNS.UI.Fit(cur.question, "Trebuchet24", pw - 32), "Trebuchet24", 16, 28, color_white)

        if cur.endAt > 0 then
            local left = math.max(0, math.ceil(cur.endAt - CurTime()))
            draw.SimpleText(left .. "s", "DermaDefaultBold", pw - 16, 10, color_white, TEXT_ALIGN_RIGHT)
        end
    end

    for i, text in ipairs(cur.options) do
        local btn = SherlockHNS.UI.Create("DButton", body)
        btn:Dock(TOP); btn:DockMargin(0, 0, 0, gap)
        btn:SetTall(rowH)
        btn:SetTooltip(text)
        btn:SetText("")

        function btn:Paint(bw, bh)
            local c = cur and cur.counts[i] or 0
            local bg = Color(40, 40, 52)
            if cur and cur.mine == i then
                bg = Color(70, 110, 200)
            elseif self:IsHovered() then
                bg = Color(58, 58, 74)
            end

            draw.RoundedBox(6, 0, 0, bw, bh, bg)
            draw.SimpleText(SherlockHNS.UI.Fit(text, "DermaDefaultBold", bw - 110), "DermaDefaultBold", 12, bh / 2,
                color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(c .. (c == 1 and " voto" or " votos"), "DermaDefault", bw - 12, bh / 2,
                Color(190, 190, 190), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        function btn:DoClick() SendVote(i) end
    end
end

-- Não abre se o player está digitando (chat, campo de texto) ou com menu/pause aberto
local function CanOpen()
    if SherlockHNS.UI.HasWindow(70, panel) then return false end
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end
    if lp:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return false end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return false end

    local focus = vgui.GetKeyboardFocus()
    if IsValid(focus) and focus.GetClassName and focus:GetClassName() == "TextEntry" then return false end

    return true
end

hook.Add("Think", "SherlockHNS_PollKey", function()
    local want = cur ~= nil and CanOpen() and SherlockHNS.Keys.IsDown("poll")

    if want and not IsValid(panel) then
        OpenPanel()
    elseif not want and IsValid(panel) then
        panel:Remove()
    end
end)

-- ===== Aviso na tela (provisório) =====
hook.Add("HUDPaint", "SherlockHNS_PollHint", function()
    if not SherlockHNS.UI.GameplayVisible() then return end
    if not cur or IsValid(panel) then return end
    if SH.IsMenuOpen and SH.IsMenuOpen() then return end

    local txt = "ENQUETE: " .. cur.question
    if cur.mine then txt = txt .. "  (seu voto: " .. cur.options[cur.mine] .. ")" end

    draw.SimpleTextOutlined(txt, "DermaDefaultBold", ScrW() / 2, SherlockHNS.UI.HUDY("poll"), color_white,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("Segure " .. SherlockHNS.Keys.Name("poll") .. " para votar", "DermaDefault", ScrW() / 2,
        SherlockHNS.UI.HUDY("poll") + 18,
        Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end)
