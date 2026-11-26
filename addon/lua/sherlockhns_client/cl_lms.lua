-- Música do LMS (cliente): toca a faixa sorteada pelo servidor e mostra o "Tocando agora"
-- com nome, autor, álbum e thumbnail (mesmas informações do pill-legacy).
-- Shared: gamemode/sh_lms.lua | Servidor: gamemode/sv_lms.lua
-- Visual provisório: o update de visual refaz o painel.

local SH        = SherlockHNS
local LMS       = SH.LMS

local cvVolume  = CreateClientConVar("hns_lms_volume", "0.7", true, false,
    "Volume da música do LMS (0 a 1)", 0, 1)

local FADE_TIME = 1.0 -- s para entrar/sair

local channel         -- IGModAudioChannel tocando
local token     = 0   -- invalida callbacks assíncronos antigos do PlayFile
local sig             -- "faixa:inicio" já tratado
local fade      = 0
local fadeGoal  = 0

-- ============================================================
-- Painel "TOCANDO AGORA"
-- ============================================================
surface.CreateFont("SherlockHNS_LMS_Tag",
    { font = "Trebuchet MS", size = 11, weight = 800, antialias = true, extended = true })
surface.CreateFont("SherlockHNS_LMS_Title",
    { font = "Trebuchet MS", size = 16, weight = 900, antialias = true, extended = true })
surface.CreateFont("SherlockHNS_LMS_Sub",
    { font = "Trebuchet MS", size = 13, weight = 600, antialias = true, extended = true })

local panel
local PANEL_W, PANEL_H = 300, 80
local THUMB = 56

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

local function SetThumb(holder, url)
    holder.HasThumb = false
    holder.URLImage = nil

    for _, child in ipairs(holder:GetChildren()) do
        if IsValid(child) then child:Remove() end
    end
    if not isstring(url) or url == "" then return end

    if string.StartWith(url, "http://") or string.StartWith(url, "https://") then
        -- URLImage retorna uma thunk: crie uma vez e consulte no Paint.
        if isfunction(surface.URLImage) then
            holder.URLImage = surface.URLImage(url, "smooth")
        end
    else
        -- material local (relativo a materials/)
        local mat = Material(url)
        if mat and not mat:IsError() then
            local img = SherlockHNS.UI.Create("DImage", holder)
            img:Dock(FILL)
            img:SetImage(url)
            img:SetMouseInputEnabled(false)
            holder.HasThumb = true
        end
    end
end
local function BuildPanel()
    if IsValid(panel) then panel:Remove() end

    panel = SherlockHNS.UI.Create("DPanel")
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetPos(20, ScrH() - PANEL_H - 100)
    panel:SetAlpha(0)
    panel:SetMouseInputEnabled(false)

    function panel:Paint(w, h)
        draw.RoundedBox(10, 2, 3, w, h, Color(0, 0, 0, 90))
        draw.RoundedBox(10, 0, 0, w, h, Color(14, 12, 12, 225))
        surface.SetDrawColor(255, 195, 90, 60)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        surface.SetDrawColor(255, 195, 90, 200)
        surface.DrawRect(0, 0, 3, h)
    end

    -- some atrás do menu (F2 / tela inicial)
    function panel:Think()
        self:SetVisible(not (SherlockHNS.IsMenuOpen and SherlockHNS.IsMenuOpen()))
        self:SetWide(math.min(PANEL_W, ScrW() - 32))
        self:SetPos(16, ScrH() - PANEL_H - (ScrW() < 1000 and 170 or 100))
    end

    local holder = SherlockHNS.UI.Create("DPanel", panel)
    holder:SetPos(14, (PANEL_H - THUMB) / 2)
    holder:SetSize(THUMB, THUMB)
    holder:SetMouseInputEnabled(false)
    function holder:Paint(w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(30, 30, 30, 255))

        if DrawURLImage(self.URLImage, 0, 0, w, h) then
            self.HasThumb = true
        end

        if not self.HasThumb then
            draw.SimpleText("♪", "SherlockHNS_LMS_Title", w / 2, h / 2, Color(255, 195, 90, 220),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    panel.Holder = holder

    local infoX = 14 + THUMB + 12
    local infoW = PANEL_W - infoX - 14

    local tag = SherlockHNS.UI.Create("DLabel", panel)
    tag:SetFont("SherlockHNS_LMS_Tag")
    tag:SetTextColor(Color(255, 195, 90))
    tag:SetText("TOCANDO AGORA")
    tag:SetPos(infoX, 4)
    tag:SetSize(infoW, 14)
    tag:SetMouseInputEnabled(false)

    local name = SherlockHNS.UI.Create("DLabel", panel)
    name:SetFont("SherlockHNS_LMS_Title")
    name:SetTextColor(Color(235, 235, 235))
    name:SetPos(infoX, 20)
    name:SetSize(infoW, 22)
    name:SetMouseInputEnabled(false)
    panel.Name = name

    local sub = SherlockHNS.UI.Create("DLabel", panel)
    sub:SetFont("SherlockHNS_LMS_Sub")
    sub:SetTextColor(Color(180, 180, 190))
    sub:SetPos(infoX, 42)
    sub:SetSize(infoW, 18)
    sub:SetMouseInputEnabled(false)
    panel.Sub = sub

    function panel:PerformLayout(w)
        local available = math.max(1, w - infoX - 14)
        tag:SetWide(available); name:SetWide(available); sub:SetWide(available)
    end

    return panel
end

local function ShowNowPlaying(track)
    local name = tostring(track.name or "")
    if name == "" then return end

    BuildPanel()
    panel.Name:SetText(name)

    local parts = {}
    if (track.author or "") ~= "" then parts[#parts + 1] = track.author end
    if (track.album or "") ~= "" then parts[#parts + 1] = track.album end
    panel.Sub:SetText(table.concat(parts, " — "))

    SetThumb(panel.Holder, track.thumbnail)

    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.35, 0)
end

local function HideNowPlaying()
    if not IsValid(panel) then return end
    local p = panel
    panel = nil
    p:AlphaTo(0, 0.5, 0, function()
        if IsValid(p) then p:Remove() end
    end)
end

-- ============================================================
-- Reprodução
-- ============================================================
local function StopChannel()
    token = token + 1
    if IsValid(channel) then channel:Stop() end
    channel = nil
end

local function Start(index, startedAt)
    StopChannel()
    local my = token

    local track = LMS.GetTrack(index)
    if not track then return end

    local path = LMS.GetPath(track)
    if not file.Exists(path, "GAME") then
        -- download do FastDL incompleto ou falhou: sem som, sem painel enganoso
        print("[HnS] LMS: arquivo não encontrado no cliente: " .. path)
        return
    end

    fade, fadeGoal = 0, 1
    ShowNowPlaying(track)

    sound.PlayFile(path, "noplay", function(ch, errCode, errStr)
        if not IsValid(ch) then
            print(("[HnS] LMS: falha ao tocar %s (%s %s)"):format(path, tostring(errCode), tostring(errStr)))
            HideNowPlaying()
            return
        end
        if my ~= token then -- trocou/parou enquanto carregava
            ch:Stop()
            return
        end

        -- quem entra no meio da música (ou carrega tarde) cai no ponto certo
        local offset, len = CurTime() - startedAt, ch:GetLength()
        if offset > 1 and len > 0 then
            ch:SetTime(offset % len)
        end

        ch:EnableLooping(true)
        ch:SetVolume(0)
        ch:Play()
        channel = ch
    end)
end

local function FadeOut()
    fadeGoal = 0
    HideNowPlaying()
end

hook.Add("Think", "SherlockHNS_LMSPlayer", function()
    -- 1) servidor mudou a faixa?
    local index, startedAt = LMS.GetIndex(), LMS.GetStart()
    local now = index .. ":" .. startedAt
    if now ~= sig then
        sig = now
        if index == 0 then FadeOut() else Start(index, startedAt) end
    end

    -- 2) fade + volume ao vivo (o slider vale na hora)
    fade = math.Approach(fade, fadeGoal, FrameTime() / FADE_TIME)

    if IsValid(channel) then
        if fadeGoal == 0 and fade == 0 then
            StopChannel()
        elseif channel:GetState() == GMOD_CHANNEL_STOPPED then
            StopChannel()     -- o card continua; só o LMS acabando (index == 0) o remove
        else
            channel:SetVolume(math.Clamp(cvVolume:GetFloat(), 0, 1) * fade)
        end
    end
end)

-- Teste local: para tudo (equivale ao antigo pr_lms_test_stop)
concommand.Add("hns_lms_stop", function()
    StopChannel()
    HideNowPlaying()
    fade, fadeGoal = 0, 0
end)
