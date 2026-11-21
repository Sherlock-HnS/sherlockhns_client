-- Anúncios (cliente): mostra título + subtítulo no topo da tela.
-- Visual provisório.

local cur -- { title, subtitle, born, endAt }

net.Receive("sherlockhns_announce_show", function()
    local title, subtitle, secs = net.ReadString(), net.ReadString(), net.ReadUInt(8)
    local now = CurTime()
    cur = { title = title, subtitle = subtitle, born = now, endAt = now + secs }
    surface.PlaySound("buttons/blip1.wav")
end)

hook.Add("HUDPaint", "SherlockHNS_Announce", function()
    if not SherlockHNS.UI.GameplayVisible() then return end
    if not cur then return end

    local now = CurTime()
    if now >= cur.endAt then
        cur = nil
        return
    end

    local a = math.min(1, (now - cur.born) / 0.4) * math.min(1, (cur.endAt - now) / 0.6)
    local x, y = ScrW() / 2, SherlockHNS.UI.HUDY("announce")

    draw.SimpleTextOutlined(SherlockHNS.UI.Fit(cur.title, "DermaLarge", ScrW() - 32), "DermaLarge", x, y,
        ColorAlpha(color_white, 255 * a),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, ColorAlpha(color_black, 255 * a))
    if cur.subtitle ~= "" then
        draw.SimpleTextOutlined(SherlockHNS.UI.Fit(cur.subtitle, "Trebuchet24", ScrW() - 32), "Trebuchet24", x, y + 36,
            ColorAlpha(Color(200, 200, 200), 255 * a),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, ColorAlpha(color_black, 255 * a))
    end
end)
