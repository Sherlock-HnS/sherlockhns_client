-- UI da votação de mapa (cliente)

surface.CreateFont("SherlockHNS_MapName", { font = "Tahoma", size = 22, weight = 700, extended = true })
surface.CreateFont("SherlockHNS_MapNameSmall", { font = "Tahoma", size = 15, weight = 700, extended = true })

local COL_PANEL    = Color(15, 15, 20, 235)
local COL_CARD     = Color(40, 40, 52)
local COL_HOVER    = Color(58, 58, 74)
local COL_SELECTED = Color(70, 110, 200)
local COL_WINNER   = Color(60, 160, 80)
local COL_DIM      = Color(190, 190, 190)

local BORDER       = 4 -- moldura colorida em volta da imagem

local vote, choice
local images       = {} -- [mapa] = URL da capa (enviada pelo servidor)

-- Capa remota via URLImage; evita criar um Chromium por card.
local function DrawURLImage(image, x, y, w, h)
    if not image then return false end
    local imageW, imageH = image()
    if not imageW or not imageH then return false end

    local sourceAspect, targetAspect = imageW / imageH, w / h
    local u0, v0, u1, v1 = 0, 0, 1, 1
    if sourceAspect > targetAspect then
        local crop = targetAspect / sourceAspect
        u0, u1 = (1 - crop) / 2, (1 + crop) / 2
    elseif sourceAspect < targetAspect then
        local crop = sourceAspect / targetAspect
        v0, v1 = (1 - crop) / 2, (1 + crop) / 2
    end

    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
    return true
end

local function SetCardImage(card, url)
    if not isstring(url) or url == "" or card.imageUrl == url then return end
    card.imageUrl = url

    if IsValid(card.html) then card.html:Remove() end
    card.html = nil

    -- A thunk is retained per card; only the thunk is polled from Paint.
    card.imageThunk = isfunction(surface.URLImage) and surface.URLImage(url, "smooth") or nil
    card.imageReady = false
end
local function OpenVote(opts)
    if IsValid(vote) then vote:Remove() end
    choice = nil
    if #opts == 0 then return end

    local s = math.max(0.65, SherlockHNS.UI.Scale())
    local cw, ch = math.Round(240 * s), math.Round(135 * s)
    local gap, pad = math.Round(16 * s), math.Round(24 * s)
    local header = math.max(80, math.Round(80 * s))

    local cols = math.min(#opts, 4)
    local rows = math.ceil(#opts / cols)
    local w = cols * cw + (cols - 1) * gap + pad * 2
    local h = header + rows * ch + (rows - 1) * gap + pad

    vote = SherlockHNS.UI.Create("DPanel")
    SherlockHNS.UI.Window(vote, w, h, 100)
    local body = SherlockHNS.UI.Create("DScrollPanel", vote)
    body:Dock(FILL)
    body:DockMargin(pad, header, pad, pad)
    local grid = SherlockHNS.UI.Create("DIconLayout", body)
    grid:Dock(TOP)
    grid:SetSpaceX(gap); grid:SetSpaceY(gap)
    local gridLayout = grid.PerformLayout
    grid.PerformLayout = function(self, width, height)
        local columns = math.max(1, math.min(4, math.floor((width + gap) / (180 * s + gap))))
        local cardWidth = math.max(1, math.floor((width - (columns - 1) * gap) / columns))
        for _, card in ipairs(self:GetChildren()) do card:SetSize(cardWidth, math.floor(cardWidth * 0.5625)) end
        gridLayout(self, width, height)
    end
    vote:MakePopup()
    vote:SetKeyboardInputEnabled(false) -- mouse livre, mas ainda dá para andar
    vote.cards = {}

    function vote:Paint(pw, ph)
        draw.RoundedBox(10, 0, 0, pw, ph, COL_PANEL)

        local nextMap = GetGlobalString("sherlockhns_map_next", "")
        local title, sub
        if nextMap ~= "" then
            title, sub = "Próximo mapa: " .. nextMap, "Trocando de mapa..."
        else
            local left = math.max(0, math.ceil(GetGlobalFloat("sherlockhns_state_end", 0) - CurTime()))
            title, sub = "Votação de mapa", "Clique em um mapa para votar  -  " .. left .. "s"
        end

        draw.SimpleText(SherlockHNS.UI.Fit(title, "DermaLarge", pw - 24), "DermaLarge", pw / 2, 10, color_white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(sub, "DermaDefaultBold", pw / 2, 46, COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end

    -- fecha se a votação for cancelada (estado mudou)
    function vote:Think()
        if GetGlobalInt("sherlockhns_state", ROUND_WAITING) ~= ROUND_MAPVOTE then
            self:Remove()
        end
    end

    for i, name in ipairs(opts) do
        local card = SherlockHNS.UI.Create("DButton", grid)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        card:SetPos(pad + col * (cw + gap), header + row * (ch + gap))
        card:SetSize(cw, ch)
        card:SetText("")
        card.count   = 0
        card.mapName = name

        -- sem capa da oficina: tenta o thumb do próprio mapa
        local thumb  = Material("maps/thumb/" .. name .. ".png")
        if thumb and not thumb:IsError() then card.thumb = thumb end

        function card:Paint(pw, ph)
            local nextMap = GetGlobalString("sherlockhns_map_next", "")
            local bg = COL_CARD
            if nextMap == name then
                bg = COL_WINNER
            elseif choice == name then
                bg = COL_SELECTED
            elseif nextMap == "" and self:IsHovered() then
                bg = COL_HOVER
            end
            draw.RoundedBox(8, 0, 0, pw, ph, bg)

            self.imageReady = DrawURLImage(self.imageThunk, BORDER, BORDER, pw - BORDER * 2, ph - BORDER * 2)
            if not self.imageReady and self.thumb then
                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(self.thumb)
                surface.DrawTexturedRect(BORDER, BORDER, pw - BORDER * 2, ph - BORDER * 2)
            end
        end

        -- texto por cima da imagem
        function card:PaintOver(pw, ph)
            local hasImage = self.imageReady or self.thumb
            local votes = self.count .. (self.count == 1 and " voto" or " votos")

            surface.SetFont("SherlockHNS_MapName")
            local font = surface.GetTextSize(name) > pw - 24 and "SherlockHNS_MapNameSmall" or "SherlockHNS_MapName"

            if hasImage then
                local bh = math.Round(38 * s)
                surface.SetDrawColor(0, 0, 0, 185)
                surface.DrawRect(BORDER, ph - BORDER - bh, pw - BORDER * 2, bh)

                draw.SimpleTextOutlined(SherlockHNS.UI.Fit(name, font, pw - 24), font, pw / 2, ph - BORDER - bh / 2,
                    color_white,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

                -- contador de votos no canto
                surface.SetFont("DermaDefaultBold")
                local tw = surface.GetTextSize(votes)
                draw.RoundedBox(6, pw - tw - 22, 10, tw + 14, 20, Color(0, 0, 0, 190))
                draw.SimpleText(votes, "DermaDefaultBold", pw - 15, 20, color_white,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(SherlockHNS.UI.Fit(name, font, pw - 24), font, pw / 2, ph / 2 - 8, color_white,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(votes, "DermaDefaultBold", pw / 2, ph - 22, COL_DIM,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        function card:DoClick()
            if GetGlobalString("sherlockhns_map_next", "") ~= "" then return end
            choice = name
            surface.PlaySound("ui/buttonclick.wav")
            net.Start("sherlockhns_map_vote")
            net.WriteString(name)
            net.SendToServer()
        end

        SetCardImage(card, images[name]) -- se a capa já chegou

        vote.cards[i] = card
    end
end

net.Receive("sherlockhns_map_vote_open", function()
    local opts = {}
    for i = 1, net.ReadUInt(4) do opts[i] = net.ReadString() end
    OpenVote(opts)
end)

net.Receive("sherlockhns_map_vote_counts", function()
    local counts = {}
    for i = 1, net.ReadUInt(4) do counts[i] = net.ReadUInt(8) end

    if not IsValid(vote) then return end
    for i, c in ipairs(counts) do
        if vote.cards[i] then vote.cards[i].count = c end
    end
end)

-- Capas dos mapas (podem chegar antes ou depois do painel abrir)
net.Receive("sherlockhns_map_images", function()
    for _ = 1, net.ReadUInt(4) do
        local name   = net.ReadString()
        local url    = net.ReadString()
        images[name] = url

        if IsValid(vote) then
            for _, card in ipairs(vote.cards) do
                if card.mapName == name then SetCardImage(card, url) end
            end
        end
    end
end)

-- Modo aleatório (ou votação de 1 opção): não há painel, só o aviso
hook.Add("HUDPaint", "SherlockHNS_MapNext", function()
    if IsValid(vote) then return end
    if GetGlobalInt("sherlockhns_state", ROUND_WAITING) ~= ROUND_MAPVOTE then return end

    local nextMap = GetGlobalString("sherlockhns_map_next", "")
    if nextMap == "" then return end

    draw.SimpleTextOutlined("Próximo mapa: " .. nextMap, "DermaLarge", ScrW() / 2, ScrH() * 0.3,
        color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end)
