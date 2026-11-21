-- Roleta (cliente): resultado autoritativo do servidor (sv_roulette.lua), grade paginada.
-- Servidor: gamemode/sv_roulette.lua | Estado: ROUND_ROULETTE (shared.lua)

local gold, dim = Color(218, 181, 100), Color(150, 151, 155)

for name, size in pairs({ Title = 36, Name = 26, Body = 18, Label = 15, Hero = 44, Pill = 30 }) do
    surface.CreateFont("PR_Roll_" .. name, {
        font = "Trebuchet MS", size = size, weight = 800, antialias = true, extended = true,
    })
end

local activeFrame

-- ============================================================
-- Sons
-- ============================================================
local SOUNDS = {
    Tick = { "buttons/button15.wav", 0.25, 50 },
    End  = { "buttons/button14.wav", 0.5, 60 },
}

local function soundCue(key)
    local ply, s = LocalPlayer(), SOUNDS[key]
    if IsValid(ply) and s then ply:EmitSound(s[1], s[3], 100, s[2]) end
end

-- ============================================================
-- Texto: truncamento UTF-8 medido (com cache)
-- ============================================================
local function measureFit(text, font, width)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= width then return text end

    local count = utf8.len(text)
    if not count then return "..." end

    local low, high = 0, count
    while low < high do
        local mid = math.ceil((low + high) / 2)
        if surface.GetTextSize(utf8.sub(text, 1, mid) .. "...") <= width then
            low = mid
        else
            high = mid - 1
        end
    end
    return utf8.sub(text, 1, low) .. "..."
end

local fitCache, fitCount = {}, 0
local function FitText(value, font, width)
    width = math.max(0, math.floor(width))
    local text = tostring(value or "")
    local key = font .. "\0" .. width .. "\0" .. text

    if fitCache[key] then return fitCache[key] end
    if fitCount >= 1024 then fitCache, fitCount = {}, 0 end

    local result = measureFit(text, font, width)
    fitCache[key] = result
    fitCount = fitCount + 1
    return result
end

-- ============================================================
-- Rolo estilo caça-níquel
-- ============================================================
local function DrawReel(panel, reel, pos, x, cy, w, rowH, bigFont, smallFont)
    local sx, sy = panel:LocalToScreen(x, cy - rowH)
    render.SetScissorRect(sx, sy, sx + w, sy + rowH * 2, true)

    local from = math.max(1, math.floor(pos) - 1)
    local to   = math.min(#reel, math.floor(pos) + 4)

    for i = from, to do
        local d = math.abs((i - 1) - pos)
        local f = math.Clamp(1 - d, 0, 1)
        local font = d < 0.5 and bigFont or smallFont
        local g = 110 + 145 * f
        local y = cy + ((i - 1) - pos) * rowH

        draw.SimpleText(FitText(reel[i], font, w), font, x, y,
            Color(g, g, g, 110 + 145 * f), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- linhas da "janela" do meio
    surface.SetDrawColor(gold.r, gold.g, gold.b, 90)
    surface.DrawRect(x, cy - rowH / 2, w, 1)
    surface.DrawRect(x, cy + rowH / 2, w, 1)

    render.SetScissorRect(0, 0, 0, 0, false)
end

-- ============================================================
-- Arte da pill (mesma convenção do ContentIcon do pk_pills: materials/pills/<id>.png)
-- ============================================================
local pillMaterials = {}

local function GetPillArtwork(id)
    id = tostring(id or "")
    if id == "" or id:find("..", 1, true) then return nil end
    if pillMaterials[id] then return pillMaterials[id] end

    local path = "pills/" .. id .. ".png"
    if not file.Exists("materials/" .. path, "GAME") then return nil end

    local mat = Material(path, "smooth")
    if mat:IsError() then return nil end

    pillMaterials[id] = mat
    return mat
end

-- Modelo de reserva quando a pill não tem PNG
local function GetPillModel(id)
    local t = pk_pills and pk_pills.getPillTable and pk_pills.getPillTable(id)
    if not t then return nil end
    if isstring(t.model) and t.model ~= "" then return t.model end

    if isfunction(t.options) then
        local ok, opts = pcall(t.options)
        local first = ok and istable(opts) and (opts[1] or select(2, next(opts)))
        if istable(first) and isstring(first.model) then return first.model end
    end
end

local PLACEHOLDER_DOTS = { { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.5, 0.5 }, { 0.25, 0.75 }, { 0.75, 0.75 } }

-- id vazio/nil = placeholder (killer sem pill). cover = preenche o painel inteiro.
local function CreatePillArtwork(parent, id, cover)
    id = tostring(id or "")

    local art = vgui.Create("DPanel", parent)
    art:SetMouseInputEnabled(false)

    if id == "" then
        art.Paint = function(_, w, h)
            local size = math.min(w, h) * 0.72
            local x, y = (w - size) / 2, (h - size) / 2
            draw.RoundedBox(12, x, y, size, size, Color(100, 25, 35))
            for _, p in ipairs(PLACEHOLDER_DOTS) do
                local r = math.max(3, size * 0.065)
                draw.RoundedBox(r, x + size * p[1] - r, y + size * p[2] - r, r * 2, r * 2, color_white)
            end
        end
        return art
    end

    local mat = GetPillArtwork(id)
    if mat then
        art.Paint = function(_, w, h)
            local mw, mh = math.max(1, mat:Width()), math.max(1, mat:Height())
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(mat)

            if cover then
                local scale = math.max(w / mw, h / mh)
                local u, v = (1 - w / (mw * scale)) / 2, (1 - h / (mh * scale)) / 2
                surface.DrawTexturedRectUV(0, 0, w, h, u, v, 1 - u, 1 - v)
            else
                local scale = math.min(w / mw, h / mh)
                local dw, dh = mw * scale, mh * scale
                surface.DrawTexturedRect((w - dw) / 2, (h - dh) / 2, dw, dh)
            end
        end
        return art
    end

    art.Paint = function(_, w, h)
        draw.SimpleText("SEM IMAGEM", "DermaDefaultBold", w / 2, h / 2, Color(140, 145, 150),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local model = GetPillModel(id)
    if isstring(model) and model ~= "" and util.IsValidModel(model) then
        art.Paint = nil
        local icon = vgui.Create("SpawnIcon", art)
        icon:Dock(FILL)
        icon:SetModel(model)
        icon:SetMouseInputEnabled(false)
        icon:SetTooltip(false)
    end

    return art
end

-- ============================================================
-- Layout da grade
-- ============================================================
local function RouletteLayout(count, width, height)
    local cols = math.min(count, math.max(1, math.min(3, math.floor(width / 370))))
    local maxRows = math.max(1, math.floor(height / 190))
    local perPage = cols * maxRows
    return cols, math.min(maxRows, math.ceil(count / cols)), perPage, math.ceil(count / perPage)
end

-- ============================================================
-- Roleta
-- ============================================================
local function showRoulette(players, selected, duration)
    if not istable(players) or #players == 0 or not istable(selected) or #selected == 0 then return end
    if IsValid(activeFrame) then activeFrame:Remove() end

    duration = math.Clamp(tonumber(duration) or 6, 0.1, 60)

    local frame = vgui.Create("DFrame")
    activeFrame = frame
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:SetKeyboardInputEnabled(false)
    frame:SetMouseInputEnabled(false)

    local width = math.min(1100, ScrW() * 0.76)
    local available = math.max(190, math.min(420, ScrH() * 0.43))
    local cols, rows, perPage, pages = RouletteLayout(#selected, width, available)
    local gap = 14
    local cellW = (width - gap * (cols - 1)) / cols
    local cellH = math.min(#selected == 1 and 420 or 250, (available - gap * (rows - 1)) / rows)
    local originY = (ScrH() - (rows * cellH + (rows - 1) * gap) + 90) / 2
    local headingY = originY - 92

    local started, blurStart = CurTime(), SysTime()
    local final, page = false, 1
    local cards = {}

    frame.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, blurStart)
        surface.SetDrawColor(0, 0, 0, 185)
        surface.DrawRect(0, 0, w, h)

        draw.SimpleText("S O R T E I O", "PR_Roll_Label", w / 2, headingY, gold, TEXT_ALIGN_CENTER)

        local title = final and (#selected == 1 and "O KILLER FOI ESCOLHIDO" or "OS KILLERS FORAM ESCOLHIDOS")
            or "SORTEANDO OS PRÓXIMOS KILLERS"
        draw.SimpleText(FitText(title, "PR_Roll_Title", width - 24), "PR_Roll_Title", w / 2, headingY + 22,
            color_white, TEXT_ALIGN_CENTER)
        draw.SimpleText(
            final and "Prepare-se. A caçada está prestes a começar."
            or "Aguarde a revelação dos jogadores e suas Pills.",
            "PR_Roll_Body", w / 2, headingY + 64, dim, TEXT_ALIGN_CENTER)

        if pages > 1 then
            draw.SimpleText("KILLERS • PÁGINA " .. page .. " / " .. pages, "PR_Roll_Label", w / 2, h - 25,
                gold, TEXT_ALIGN_CENTER)
        end
    end

    for index, selection in ipairs(selected) do
        local sel = selection
        local card = vgui.Create("DPanel", frame)
        card:SetSize(cellW, cellH)

        local rows = math.max(24, math.floor(duration * 7))
        local reel, lastName = {}, nil
        local function RandName()
            local n
            for _ = 1, 6 do
                n = players[math.random(#players)].name
                if n ~= lastName or #players == 1 then break end
            end
            lastName = n
            return n
        end
        for r = 1, rows - 1 do reel[r] = RandName() end
        reel[rows] = sel.name
        reel[rows + 1], reel[rows + 2] = RandName(), RandName()
        card.PR_Reel = reel

        -- cards mais à frente param um pouco depois (o último para junto com a revelação)
        local frac = #selected > 1 and (index - 1) / (#selected - 1) or 1
        local stopAt = duration * (0.8 + 0.2 * frac)
        card.PR_GetPos = function(elapsed)
            local t = math.Clamp(elapsed / stopAt, 0, 1)
            return (1 - (1 - t) ^ 4) * (rows - 1)
        end

        local hero = #selected == 1 and cellW >= 850
        local avatarSize = hero and math.min(280, cellH * 0.40) or math.min(100, math.max(44, cellH - 140))
        local artX = math.floor(cellW * (hero and 0.34 or 0.46))
        local avatarX = hero and math.floor(cellW * 0.05) or 18
        local avatarY = hero and math.floor((cellH - avatarSize) / 2) or 50

        local avatar = vgui.Create("AvatarImage", card)
        avatar:SetPos(avatarX, avatarY)
        avatar:SetSize(avatarSize, avatarSize)
        avatar:SetVisible(false)
        avatar:SetMouseInputEnabled(false)
        card.PR_Avatar = avatar

        card.PR_RevealArt = function()
            local art = CreatePillArtwork(card, sel.pillType, true)
            art:SetPos(artX, 1)
            art:SetSize(cellW - artX - 1, cellH - 2)
            art:SetZPos(-1) -- por baixo do avatar e do PaintOver
        end

        card.Paint = function(_, w, h) draw.RoundedBox(2, 0, 0, w, h, Color(5, 8, 7, 250)) end

        card.PaintOver = function(self, w, h)
            if final then
                -- degradê escurecendo a arte atrás do texto (esquerda e base)
                local fadeW = (w - artX) * 0.8
                for step = 0, 47 do
                    local fraction = step / 47
                    surface.SetDrawColor(5, 8, 7, 255 * (1 - fraction))
                    surface.DrawRect(artX + fraction * fadeW, 1, fadeW / 47 + 1, h - 2)
                    surface.SetDrawColor(5, 8, 7, 245 * fraction)
                    surface.DrawRect(artX, h - 140 + fraction * 140, w - artX, 4)
                end
            end

            surface.SetDrawColor(gold.r, gold.g, gold.b, 160)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            surface.DrawRect(avatarX - 5, avatarY, 4, avatarSize)

            draw.SimpleText("JOGADOR " .. index, "PR_Roll_Label", 24, 22, dim)
            draw.SimpleText(final and "CONFIRMADO" or "SORTEANDO", "PR_Roll_Label", w - 24, 22, gold, TEXT_ALIGN_RIGHT)

            local nameX, nameY, nameW = 18, avatarSize + 60, artX - 30
            if hero then
                nameX = avatarX + avatarSize + 38
                nameY = avatarY + avatarSize * 0.3
                nameW = w * 0.38
                draw.SimpleText("COMPETIDOR", "PR_Roll_Label", nameX, nameY - 48, dim)
            end

            local rowH = hero and 52 or 26
            local cy   = nameY + (hero and 28 or 16)
            DrawReel(self, self.PR_Reel, self.PR_GetPos(CurTime() - started), nameX, cy, nameW, rowH,
                hero and "PR_Roll_Hero" or "PR_Roll_Name",
                hero and "PR_Roll_Name" or "PR_Roll_Body")

            local isMe = final and IsValid(LocalPlayer()) and sel.sid == LocalPlayer():SteamID()
            draw.SimpleText(isMe and "VOCÊ FOI ESCOLHIDO" or "HIDE & SEEK", "PR_Roll_Label", nameX,
                nameY + (hero and 92 or 46), gold)

            if not final then
                draw.RoundedBox(4, avatarX, avatarY, avatarSize, avatarSize, Color(36, 36, 33))
                draw.SimpleText("?", "PR_Roll_Title", avatarX + avatarSize / 2, avatarY + avatarSize / 2, dim,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            local pillX = hero and w * 0.62 or artX + 12
            local pillY = h - (hero and 110 or 68)
            surface.SetDrawColor(gold)
            surface.DrawRect(pillX - 12, pillY, 2, hero and 72 or 54)
            draw.SimpleText("PILL SELECIONADA", "PR_Roll_Label", pillX, pillY, gold)

            local pill = final and tostring(sel.pillName or sel.pillType or "Sem pill") or "Revelada ao final"
            local font = hero and "PR_Roll_Pill" or "PR_Roll_Name"
            draw.SimpleText(FitText(pill, font, w - pillX - 22), font, pillX, pillY + 24, color_white)
        end

        cards[#cards + 1] = card
    end

    local function updatePage(nextPage)
        page = nextPage
        for i, card in ipairs(cards) do
            local visible = math.floor((i - 1) / perPage) + 1 == page
            card:SetVisible(visible)
            if visible then
                local slot = (i - 1) % perPage
                card:SetPos((ScrW() - width) / 2 + (slot % cols) * (cellW + gap),
                    originY + math.floor(slot / cols) * (cellH + gap))
            end
        end
    end

    updatePage(1)

    local nextTick = 0
    frame.Think = function(self)
        -- rodada cancelada pelo admin / jogadores insuficientes
        if GetGlobalInt("sherlockhns_state", ROUND_WAITING) == ROUND_WAITING then
            self:Remove()
            return
        end

        local elapsed = CurTime() - started

        -- giro: embaralha candidatos e alterna as páginas
        if elapsed < duration then
            local ticked = false
            for _, card in ipairs(cards) do
                if card:IsVisible() then
                    local row = math.floor(card.PR_GetPos(elapsed))
                    if row ~= card.PR_LastRow then
                        card.PR_LastRow = row
                        ticked = true
                    end
                end
            end
            if ticked and CurTime() >= nextTick then
                nextTick = CurTime() + 0.04
                soundCue("Tick")
            end

            local nextPage = math.floor(elapsed / 1.8) % pages + 1
            if nextPage ~= page then updatePage(nextPage) end
            return
        end

        -- revelação
        if not final then
            final = true
            for i, card in ipairs(cards) do
                card.PR_RevealArt()

                local sid64 = util.SteamIDTo64(selected[i].sid or "")
                if sid64 and sid64 ~= "0" then
                    card.PR_Avatar:SetSteamID(sid64, 128)
                    card.PR_Avatar:SetVisible(true)
                end
            end
            updatePage(1)
            soundCue("End")
        end

        local finalElapsed = elapsed - duration
        local nextPage = math.min(pages, math.floor(finalElapsed / 1.4) + 1)
        if nextPage ~= page then updatePage(nextPage) end

        if finalElapsed >= math.max(1.8, 1.4 * pages) then self:Remove() end
    end
end

net.Receive("sherlockhns_roulette", function()
    local players = net.ReadTable()
    local selected = net.ReadTable()
    local duration = net.ReadFloat()
    showRoulette(players, selected, duration)
end)

-- Esconde a HUD de habilidades enquanto a roleta está na tela
hook.Add("SherlockHNS_ShouldDrawHUD", "SherlockHNS_RouletteHideHUD", function()
    if IsValid(activeFrame) then return false end
end)
