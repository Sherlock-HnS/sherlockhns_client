-- Enquetes (cliente): segure G para liberar o mouse e votar.
-- Servidor: gamemode/sv_poll.lua | Shared: gamemode/sh_poll.lua
-- Visual provisório: o update de visual refaz OpenPanel e o HUDPaint.

local SH = SherlockHNS
local P  = SH.Poll

local panel
-- { id, question, options, endAt, counts, mine, active, winners, resultUntil }
local cur
local lastResult
local RESULT_DURATION = 12

function P.GetCurrent() return cur or lastResult end

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
    lastResult = nil
    cur = {
        active   = true,
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

    if cur and cur.active ~= false and cur.id == id then cur.counts = counts end
end)

net.Receive("sherlockhns_poll_close", function()
    local id       = net.ReadUInt(16)
    local question = net.ReadString()
    local options  = {}
    for i = 1, net.ReadUInt(4) do options[i] = net.ReadString() end

    local counts, total = {}, 0
    for i = 1, #options do
        counts[i] = net.ReadUInt(16)
        total = total + counts[i]
    end
    total = net.ReadUInt(16)

    local winners = {}
    for i = 1, net.ReadUInt(4) do winners[i] = net.ReadUInt(4) end

    local mine = cur and cur.id == id and cur.mine or nil
    cur = {
        active      = false,
        id          = id,
        question    = question,
        options     = options,
        counts      = counts,
        total       = total,
        winners     = winners,
        mine        = mine,
        resultUntil = CurTime() + RESULT_DURATION,
    }
    lastResult = cur

    if IsValid(panel) then panel:Remove() end
    surface.PlaySound("buttons/blip1.wav")
end)

hook.Add("InitPostEntity", "SherlockHNS_PollRequest", function()
    net.Start("sherlockhns_poll_request")
    net.SendToServer()
end)

local function SendVote(i)
    if not cur or cur.active == false then return end
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

        draw.SimpleText(cur.active == false and "RESULTADO" or "ENQUETE", "DermaDefaultBold", 16, 10, Color(180, 136, 0))
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
        btn:SetEnabled(cur.active ~= false)

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

        function btn:DoClick()
            if cur and cur.active ~= false then SendVote(i) end
        end
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
    if cur and cur.active == false and (cur.resultUntil or 0) <= CurTime() then
        cur = nil
    end

    local want = cur ~= nil and cur.active ~= false and CanOpen() and SherlockHNS.Keys.IsDown("poll")

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

    local x, y = ScrW() / 2, SherlockHNS.UI.HUDY("poll")
    if cur.active == false then
        local total = cur.total or 0
        local height = 42 + #cur.options * 17
        draw.RoundedBox(8, x - 300, y - 14, 600, height, Color(15, 15, 20, 225))
        draw.SimpleTextOutlined("RESULTADO DA ENQUETE", "DermaDefaultBold", x, y, Color(255, 210, 95),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        draw.SimpleTextOutlined(cur.question, "DermaDefault", x, y + 18, color_white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

        for i, option in ipairs(cur.options) do
            local votes = cur.counts[i] or 0
            local pct = total > 0 and math.floor(votes / total * 100 + 0.5) or 0
            local won = table.HasValue(cur.winners or {}, i)
            local label = ("%s%s  •  %d (%d%%)"):format(won and "✓ " or "", option, votes, pct)
            draw.SimpleTextOutlined(label, "DermaDefault", x, y + 39 + (i - 1) * 17,
                won and Color(150, 230, 155) or Color(220, 220, 220),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        end
        return
    end

    local txt = "ENQUETE: " .. cur.question
    if cur.mine then txt = txt .. "  (seu voto: " .. cur.options[cur.mine] .. ")" end

    draw.SimpleTextOutlined(txt, "DermaDefaultBold", x, y, color_white,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined("Segure " .. SherlockHNS.Keys.Name("poll") .. " para votar", "DermaDefault", x,
        y + 18, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end)
