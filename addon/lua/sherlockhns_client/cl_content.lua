-- Regras e créditos (cliente): recebe do servidor e substitui SherlockHNS.Rules / Credits.
-- Servidor: gamemode/sv_content.lua

net.Receive("sherlockhns_content_sync", function()
    local n = net.ReadUInt(16)
    local d = util.JSONToTable(util.Decompress(net.ReadData(n)) or "")
    if not istable(d) then return end

    if istable(d.rules) then SherlockHNS.Rules = d.rules end
    if istable(d.credits) then SherlockHNS.Credits = d.credits end
    hook.Run("SherlockHNS_ContentUpdated")
end)

hook.Add("InitPostEntity", "SherlockHNS_ContentRequest", function()
    net.Start("sherlockhns_content_request")
    net.SendToServer()
end)
