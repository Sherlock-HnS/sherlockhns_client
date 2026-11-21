-- Tags (cliente): recebe as definições e injeta no Custom Chat.
local T = SherlockHNS.Tags

net.Receive("sherlockhns_tags_sync", function()
    local list = util.JSONToTable(net.ReadString()) or {}

    T.Defs = {}
    for _, d in ipairs(list) do
        if istable(d) and isnumber(d.id) then T.Defs[d.id] = d end
    end
    hook.Run("SherlockHNS_TagsUpdated")
end)

hook.Add("InitPostEntity", "SherlockHNS_TagsRequest", function()
    net.Start("sherlockhns_tags_request")
    net.SendToServer()
end)

-- O Custom Chat desenha essas partes antes do nome (maior prioridade primeiro).
-- keepOriginal = false: as tags antigas do Custom Chat (por time/SteamID) são ignoradas
-- para quem tem tag do gamemode.
hook.Add("OverrideCustomChatTags", "SherlockHNS_ChatTags", function(ply)
    local tags = T.GetDisplayTags(ply)
    if #tags == 0 then return end

    local parts = {}
    for _, t in ipairs(tags) do
        parts[#parts + 1] = Color(t.color.r, t.color.g, t.color.b)
        parts[#parts + 1] = "[" .. t.text .. "] "
    end
    return parts, false
end)
