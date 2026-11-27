-- Aba "Conteúdo" do painel admin: edita Regras e Créditos do menu.
-- Usada por cl_admin.lua: Add("Conteúdo", SherlockHNS.BuildContentTab(sheet), "icon16/book_edit.png")

local function Send(act, tbl)
    net.Start("sherlockhns_content_save")
    net.WriteUInt(act, 2)
    if tbl then
        local data = util.Compress(util.TableToJSON(tbl))
        if #data > 60000 then
            net.Abort()
            notification.AddLegacy("Conteúdo grande demais.", NOTIFY_ERROR, 4)
            return
        end
        net.WriteUInt(#data, 16)
        net.WriteData(data, #data)
    end
    net.SendToServer()
end

local function Btn(parent, text, wide, fn)
    local b = SherlockHNS.UI.Create("DButton", parent)
    b:Dock(LEFT)
    b:DockMargin(0, 0, 6, 0)
    b:SetWide(wide)
    b:SetText(text)
    b.DoClick = fn
    return b
end

-- o = { source() -> lista, label(item), titleHint, bodyHint, toFields(item) -> título, corpo,
--       fromFields(título, corpo) -> item, publish(lista) }
local function Editor(parent, o)
    local pnl = SherlockHNS.UI.Create("DPanel", parent)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    local work = table.Copy(o.source())
    local selected

    local list = SherlockHNS.UI.Create("DListView", pnl)
    list:Dock(LEFT)
    list:SetWide(300)
    SherlockHNS.UI.Split(pnl, list, 300, 850)
    list:DockMargin(0, 0, 6, 0)
    list:SetMultiSelect(false)
    list:AddColumn("#"):SetFixedWidth(30)
    list:AddColumn("Item")

    local right = SherlockHNS.UI.Create("DPanel", pnl)
    right:Dock(FILL)
    right:SetPaintBackground(false)

    local row2 = SherlockHNS.UI.Create("DPanel", right)
    SherlockHNS.UI.Flow(row2)
    row2:Dock(BOTTOM)
    row2:DockMargin(0, 6, 0, 0)
    row2:SetTall(28)
    row2:SetPaintBackground(false)

    local row1 = SherlockHNS.UI.Create("DPanel", right)
    SherlockHNS.UI.Flow(row1)
    row1:Dock(BOTTOM)
    row1:DockMargin(0, 6, 0, 0)
    row1:SetTall(28)
    row1:SetPaintBackground(false)

    local title = SherlockHNS.UI.Create("DTextEntry", right)
    title:Dock(TOP)
    title:SetPlaceholderText(o.titleHint)

    local body = SherlockHNS.UI.Create("DTextEntry", right)
    body:Dock(FILL)
    body:DockMargin(0, 6, 0, 0)
    body:SetMultiline(true)
    body:SetPlaceholderText(o.bodyHint)

    local function Refill()
        list:Clear()
        for i, item in ipairs(work) do
            local line = list:AddLine(i, o.label(item))
            line.idx = i
            if i == selected then list:SelectItem(line) end
        end
    end

    list.OnRowSelected = function(_, _, line)
        selected = line.idx
        local t, b = o.toFields(work[selected])
        title:SetValue(t)
        body:SetValue(b)
    end

    local function Clear()
        selected = nil
        list:ClearSelection()
        title:SetValue("")
        body:SetValue("")
    end

    local function Move(dir)
        local j = selected and selected + dir
        if not j or j < 1 or j > #work then return end
        work[selected], work[j] = work[j], work[selected]
        selected = j
        Refill()
    end

    Btn(row1, "Novo", 80, Clear)
    Btn(row1, "Aplicar ao item", 130, function()
        local t = string.Trim(title:GetValue())
        if t == "" then
            notification.AddLegacy("Preencha o título.", NOTIFY_ERROR, 3)
            return
        end
        local item = o.fromFields(t, body:GetValue())
        if selected then
            work[selected] = item
        else
            work[#work + 1] = item
            selected = #work
        end
        Refill()
    end)
    Btn(row1, "Remover", 90, function()
        if not selected then return end
        table.remove(work, selected)
        selected = nil
        Clear()
        Refill()
    end)
    Btn(row1, "Subir", 70, function() Move(-1) end)
    Btn(row1, "Descer", 70, function() Move(1) end)

    Btn(row2, "Salvar e publicar", 150, function() o.publish(work) end)
    Btn(row2, "Descartar alterações", 150, function()
        work = table.Copy(o.source())
        Clear()
        Refill()
    end)
    Btn(row2, "Restaurar padrões", 150, function()
        Derma_Query("Restaurar regras E créditos para o padrão do código?", "Confirmar",
            "Restaurar", function() Send(2) end, "Cancelar")
    end)

    -- chegou atualização do servidor (ex.: publicado por outro superadmin)
    hook.Add("SherlockHNS_ContentUpdated", pnl, function()
        work = table.Copy(o.source())
        Clear()
        Refill()
    end)

    Refill()
    return pnl
end

local function Lines(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\r\n]+") do
        line = string.Trim(line)
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

function SherlockHNS.BuildContentTab(sheet)
    local root = SherlockHNS.UI.Create("DPanel", sheet)
    root:SetPaintBackground(false)
    root:DockPadding(4, 4, 4, 4)

    if not LocalPlayer():IsSuperAdmin() then
        local l = SherlockHNS.UI.Create("DLabel", root)
        l:Dock(FILL)
        l:SetContentAlignment(5)
        l:SetText("Apenas superadmins editam regras e créditos.")
        return root
    end

    local sub = SherlockHNS.UI.Create("DPropertySheet", root)
    sub:Dock(FILL)

    sub:AddSheet("Regras", Editor(sub, {
        source     = function() return SherlockHNS.Rules or {} end,
        label      = function(r) return r.title end,
        titleHint  = "Título da regra",
        bodyHint   = "Descrição (opcional; quebra de linha automática)",
        toFields   = function(r) return r.title or "", r.text or "" end,
        fromFields = function(t, b) return { title = t, text = string.Trim(b) } end,
        publish    = function(list) Send(1, { rules = list }) end,
    }), "icon16/book_open.png")

    sub:AddSheet("Créditos", Editor(sub, {
        source     = function() return SherlockHNS.Credits or {} end,
        label      = function(g) return g.title end,
        titleHint  = "Grupo (ex.: Administradores)",
        bodyHint   = "Um nome por linha",
        toFields   = function(g) return g.title or "", table.concat(g.names or {}, "\n") end,
        fromFields = function(t, b) return { title = t, names = Lines(b) } end,
        publish    = function(list) Send(1, { credits = list }) end,
    }), "icon16/group.png")

    return root
end
