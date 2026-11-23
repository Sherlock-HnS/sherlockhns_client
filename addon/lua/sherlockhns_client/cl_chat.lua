local C = SherlockHNS.Chat
local lastFrame, lastSig
local SHOW_SITE_ICON = true

local function Sync()
    if not (CustomChat and CustomChat.IsEnabled and CustomChat.IsEnabled()) then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local frame = CustomChat.frame
    if not IsValid(frame) or not frame.channels.alive then
        CustomChat:CreateCustomChannel("alive", "Vivos", "icon16/heart.png")
        CustomChat:CreateCustomChannel("dead", "Mortos / Espectadores", "icon16/status_offline.png")
        frame = CustomChat.frame
    end

    if frame ~= lastFrame then
        lastFrame, lastSig = frame, nil
    end

    local vis = {
        global = C.CanSee(lp, "global"),
        alive  = C.CanSee(lp, "alive"),
        dead   = C.CanSee(lp, "dead"),
        team   = false, -- substituído pelos canais acima
    }

    local sig = table.concat({ tostring(vis.global), tostring(vis.alive), tostring(vis.dead) }, ",")
    if sig == lastSig then return end
    lastSig = sig

    -- mostra primeiro, esconde depois (sempre sobra um canal ativo possível)
    for id, v in pairs(vis) do
        if v then frame:SetChannelHidden(id, false) end
    end
    for id, v in pairs(vis) do
        if not v then frame:SetChannelHidden(id, true) end
    end
end

timer.Create("SherlockHNS_ChatSync", 0.25, 0, Sync)

hook.Add("CustomChatDefaultChannel", "SherlockHNS_ChatDefault", function()
    local lp = LocalPlayer()
    if IsValid(lp) then return C.DefaultChannel(lp) end
end)

net.Receive("sherlockhns_sitechat", function()
    local name, id64, text, channel = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()

    local tags = {}
    for i = 1, net.ReadUInt(3) do
        local t = net.ReadString()
        tags[i] = { text = t, color = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)) }
    end

    -- Custom Chat desligado: texto simples
    if not (CustomChat and CustomChat.IsEnabled and CustomChat.IsEnabled()) then
        local parts = {}
        for _, t in ipairs(tags) do
            parts[#parts + 1] = t.color
            parts[#parts + 1] = "[" .. t.text .. "] "
        end
        parts[#parts + 1] = color_white
        parts[#parts + 1] = name .. ": " .. text
        chat.AddText(unpack(parts))
        return
    end

    local frame = CustomChat.frame
    if IsValid(frame) and not frame.channels[channel] then channel = "global" end

    -- Mesma estrutura de Tags:AddMessageWithCustomTags: tags, jogador, ": texto"
    local contents = {}

    if SHOW_SITE_ICON then
        contents[#contents + 1] = ":globe_with_meridians: "
    end

    for _, t in ipairs(tags) do
        contents[#contents + 1] = t.color
        contents[#contents + 1] = "[" .. t.text .. "] "
    end

    local ply = player.GetBySteamID64(id64)
    if IsValid(ply) then
        contents[#contents + 1] = ply -- jogador real: cor de time, menu e avatar nativos
    else
        contents[#contents + 1] = {
            blockType  = "player",
            blockValue = {
                name  = name,
                id    = util.SteamIDFrom64(id64),
                id64  = id64,
                isBot = false,
            },
        }
    end

    contents[#contents + 1] = color_white
    contents[#contents + 1] = ": " .. text

    -- O chat do site usa um canal próprio, então o Custom Chat não tem o speaker
    -- de customchat.say. Injeta o contexto apenas durante a renderização para manter
    -- os hooks de permissão e permitir embeds da whitelist também para usuários offline.
    local previousLastReceivedMessage = CustomChat.lastReceivedMessage
    local previousExternalEmbeds = CustomChat.allowExternalEmbeds

    CustomChat.lastReceivedMessage = IsValid(ply) and {
        speaker = ply,
        text = text,
        channel = channel,
    } or nil
    CustomChat.allowExternalEmbeds = true

    local ok, err = pcall(CustomChat.AddMessage, CustomChat, contents, channel)

    CustomChat.lastReceivedMessage = previousLastReceivedMessage
    CustomChat.allowExternalEmbeds = previousExternalEmbeds

    if not ok then
        ErrorNoHalt("[SherlockHNS Chat] " .. tostring(err) .. "\\n")
    end
end)
