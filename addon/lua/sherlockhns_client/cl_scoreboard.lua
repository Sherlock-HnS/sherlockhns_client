-- Scoreboard (cliente): TAB. Tags só para o top 10 do ranking, ping e controle de voz.
-- Servidor: o rank vem de NetworkedVar "hns_rank" (veja o patch em sv_stats.lua).
-- Visual provisório: o update de interfaces refaz as cores/fontes.

local SH         = SherlockHNS
local T          = SH.Tags

SH.Scoreboard    = SH.Scoreboard or {}
local SB         = SH.Scoreboard

SB.TopN          = 10

local COL_ACCENT = Color(180, 136, 0)
local COL_DIM    = Color(190, 190, 190)
local COL_PANEL  = Color(15, 15, 20, 240)
local COL_ROW    = Color(255, 255, 255, 10)
local COL_KILLER = Color(255, 90, 90)
local COL_RUNNER = Color(120, 200, 255)

local MAT_ON     = Material("icon16/sound.png")
local MAT_MUTE   = Material("icon16/sound_mute.png")

local function U(v) return SherlockHNS.UI.Unit(v) end

local function F(size, weight)
    return SherlockHNS.UI.Font(size, weight or 700)
end

-- ============================================================
-- Voz: volume e mute por jogador (salvo em cookie, vale entre sessões)
-- ============================================================
local function VKey(ply)
    return "hns_voice_" .. (ply:IsBot() and ply:Nick() or (ply:SteamID64() or "0"))
end

local voiceCache = {}

local function VState(ply)
    local key = VKey(ply)
    local s = voiceCache[key]
    if not s then
        s = {
            key  = key,
            vol  = math.Clamp(cookie.GetNumber(key .. "_vol", 1), 0, 1),
            mute = cookie.GetNumber(key .. "_mute", 0) == 1,
        }
        voiceCache[key] = s
    end
    return s
end

function SB.GetVolume(ply) return VState(ply).vol end

function SB.IsMuted(ply) return VState(ply).mute end

local function ApplyVoice(ply)
    if not IsValid(ply) or ply == LocalPlayer() or ply:IsBot() then return end
    ply:SetMuted(SB.IsMuted(ply))
    ply:SetVoiceVolumeScale(SB.GetVolume(ply))
end

function SB.SetVolume(ply, v)
    local s = VState(ply)
    s.vol = math.Clamp(v, 0, 1)
    timer.Create("hns_vsave_vol_" .. s.key, 0.5, 1, function()
        cookie.Set(s.key .. "_vol", tostring(s.vol))
    end)
    ApplyVoice(ply)
end

function SB.SetMuted(ply, state)
    local s = VState(ply)
    s.mute = state and true or false
    cookie.Set(s.key .. "_mute", s.mute and "1" or "0") -- raro, pode gravar direto
    ApplyVoice(ply)
end

-- reaplica periodicamente (jogadores que entram depois, reconexões etc.)
timer.Create("SherlockHNS_SB_ApplyVoice", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do ApplyVoice(ply) end
end)

-- ============================================================
-- Dados
-- ============================================================
local function GroupOf(ply)
    if SH.IsInMenu(ply) or ply:Team() == TEAM_SPECTATOR then return 3 end
    if ply:Team() == TEAM_KILLERS then return 1 end
    return 2
end

local GROUP_TITLE = { "Killers", "Runners", "Espectadores / Menu" }

local function PingColor(p)
    if p < 60 then return Color(90, 220, 120) end
    if p < 120 then return Color(230, 200, 70) end
    return Color(230, 80, 80)
end

-- ============================================================
-- Linha de jogador
-- ============================================================
local function MakeSlider(row, ply)
    local s = SherlockHNS.UI.Create("DPanel", row)
    s:SetCursor("hand")

    function s:Paint(w, h)
        local v = SB.IsMuted(ply) and 0 or SB.GetVolume(ply)
        local ty = h / 2
        draw.RoundedBox(2, 0, ty - U(2), w, U(4), Color(255, 255, 255, 40))
        draw.RoundedBox(2, 0, ty - U(2), w * v, U(4), COL_ACCENT)
        draw.RoundedBox(U(6), w * v - U(5), ty - U(6), U(10), U(12), color_white)
    end

    local function FromCursor(self)
        local x = self:CursorPos()
        local v = math.Clamp(x / self:GetWide(), 0, 1)
        if SB.IsMuted(ply) and v > 0 then SB.SetMuted(ply, false) end
        SB.SetVolume(ply, v)
    end

    function s:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        self.drag = true
        self:MouseCapture(true)
        FromCursor(self)
    end

    function s:Think()
        if not self.drag then return end
        if not input.IsMouseDown(MOUSE_LEFT) then
            self.drag = false
            self:MouseCapture(false)
            return
        end
        FromCursor(self)
    end

    return s
end

local function MakeRow(parent, ply)
    local row = SherlockHNS.UI.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(U(42))
    row:DockMargin(0, 0, U(8), U(4))
    row.ply            = ply
    row.tags           = {}
    row.tagsNextUpdate = 0

    local isMe         = ply == LocalPlayer()
    local voice        = not isMe and not ply:IsBot()

    local av           = SherlockHNS.UI.Create("AvatarImage", row)
    av:SetPlayer(ply, 64)

    local mute, slider
    if voice then
        mute = SherlockHNS.UI.Create("DButton", row)
        mute:SetText("")
        mute:SetTooltip("Mutar / desmutar")
        function mute:Paint(w, h)
            local m = SB.IsMuted(ply)
            surface.SetDrawColor(255, 255, 255, m and 120 or 255)
            surface.SetMaterial(m and MAT_MUTE or MAT_ON)
            surface.DrawTexturedRect((w - 16) / 2, (h - 16) / 2, 16, 16)
            return true
        end

        function mute:DoClick() SB.SetMuted(ply, not SB.IsMuted(ply)) end

        slider = MakeSlider(row, ply)
    end

    function row:PerformLayout(w, h)
        av:SetPos(U(8), (h - U(30)) / 2)
        av:SetSize(U(30), U(30))
        if voice then
            local pingW = U(80)
            slider:SetSize(U(120), h)
            slider:SetPos(w - pingW - U(120) - U(8), 0)
            mute:SetSize(U(32), h)
            mute:SetPos(w - pingW - U(120) - U(8) - U(34), 0)
        end
    end

    function row:Paint(w, h)
        if not IsValid(ply) then return end
        draw.RoundedBox(6, 0, 0, w, h, isMe and Color(180, 136, 0, 60) or COL_ROW)

        local x, cy = U(50), h / 2

        -- top 10: posição + tags
        local rank = ply:GetNWInt("hns_rank", 0)
        if rank >= 1 and rank <= SB.TopN then
            local txt = "#" .. rank
            draw.SimpleText(txt, F(15), x, cy, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetFont(F(15))
            x = x + surface.GetTextSize(txt) + U(8)

            for i, tag in ipairs(row.tags) do
                local label = SherlockHNS.UI.Fit("[" .. tag.text .. "]", F(16), math.max(0, w - U(310) - x))
                draw.SimpleText(label, F(16), x, cy, Color(tag.color.r, tag.color.g, tag.color.b),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                surface.SetFont(F(16))
                x = x + surface.GetTextSize(label) + U(6)
            end
        end

        local col = color_white
        if not ply:Alive() then
            col = COL_DIM
        elseif ply:Team() == TEAM_KILLERS then
            col = COL_KILLER
        end
        local nameRight = voice and (w - U(280)) or (w - U(85))
        local playerLabel = ply:Nick() .. ((ply:Team() ~= TEAM_SPECTATOR and not ply:Alive()) and " (morto)" or "")
        local displayedName = SherlockHNS.UI.Fit(playerLabel, F(18), nameRight - x)
        draw.SimpleText(displayedName, F(18), x, cy, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- ping
        if ply:IsBot() then
            draw.SimpleText("BOT", F(16), w - U(16), cy, COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        else
            local p = ply:Ping()
            draw.SimpleText(p .. " ms", F(16), w - U(16), cy, PingColor(p), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    function row:Think()
        if not IsValid(ply) then return end

        local now = CurTime()
        if now < self.tagsNextUpdate then return end

        self.tagsNextUpdate = now + 0.5
        self.tags = T.GetDisplayTags(ply) or {}
    end

    return row
end

-- ============================================================
-- Painel
-- ============================================================
local board

local function Signature()
    local parts = {}
    for _, p in ipairs(player.GetAll()) do
        parts[#parts + 1] = p:UserID() .. ":" .. GroupOf(p) .. (p:Alive() and "a" or "d")
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function Rebuild(scroll)
    scroll:Clear()

    local groups = { {}, {}, {} }
    for _, p in ipairs(player.GetAll()) do
        local g = groups[GroupOf(p)]
        g[#g + 1] = p
    end

    for gi, list in ipairs(groups) do
        if #list > 0 then
            table.sort(list, function(a, b)
                if a:Alive() ~= b:Alive() then return a:Alive() end
                return a:Nick():lower() < b:Nick():lower()
            end)

            local head = SherlockHNS.UI.Create("DLabel", scroll)
            head:Dock(TOP)
            head:DockMargin(U(4), U(10), 0, U(6))
            head:SetTall(U(22))
            head:SetFont(F(16))
            head:SetTextColor(gi == 1 and COL_KILLER or (gi == 2 and COL_RUNNER or COL_DIM))
            head:SetText(GROUP_TITLE[gi] .. "  -  " .. #list)

            for _, p in ipairs(list) do MakeRow(scroll, p) end
        end
    end
end

local function Open()
    if IsValid(board) then board:Remove() end

    local w, h = U(900), math.min(ScrH() - U(120), U(820))
    board = SherlockHNS.UI.Create("DPanel")
    SherlockHNS.UI.Window(board, w, h, 70)
    board:Center()
    board:SetKeyboardInputEnabled(false)
    board:DockPadding(U(24), U(96), U(16), U(20))

    function board:Paint(pw, ph)
        draw.RoundedBox(U(12), 0, 0, pw, ph, COL_PANEL)
        draw.SimpleText(GetHostName(), F(30), U(24), U(20), color_white)
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(U(24), U(62), U(60), U(3))
        draw.SimpleText(game.GetMap() .. "  -  " .. player.GetCount() .. "/" .. game.MaxPlayers(),
            F(16), pw - U(24), U(30), COL_DIM, TEXT_ALIGN_RIGHT)
        draw.SimpleText("Voz: clique no alto-falante para mutar, arraste a barra para o volume",
            F(14, 500), U(24), U(72), COL_DIM)
    end

    local scroll = SherlockHNS.UI.Create("DScrollPanel", board)
    scroll:Dock(FILL)

    local nextSig = 0
    function scroll:Think()
        if CurTime() < nextSig then return end
        nextSig = CurTime() + 0.25
        local sig = Signature()
        if sig ~= lastSig then
            lastSig = sig
            Rebuild(self)
        end
    end
end

function GM:ScoreboardShow()
    Open()
    gui.EnableScreenClicker(true)
    return true
end

function GM:ScoreboardHide()
    if IsValid(board) then board:Remove() end
    board = nil
    gui.EnableScreenClicker(false)
    return true
end
