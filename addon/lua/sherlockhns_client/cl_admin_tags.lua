-- Aba "Tags" do painel admin (cliente)
-- Usada por cl_admin.lua: Add("Tags", SherlockHNS.BuildTagsTab(sheet), "icon16/tag_blue.png")
local T = SherlockHNS.Tags
local ACT_SAVE, ACT_DELETE, ACT_GIVE, ACT_TAKE = 1, 2, 3, 4

local function Send(act, fn)
    net.Start("sherlockhns_tags_action")
    net.WriteUInt(act, 3)
    if fn then fn() end
    net.SendToServer()
end

function SherlockHNS.BuildTagsTab(sheet)
    local selected -- id da tag em edição (nil = nova)
    local filling = false

    local pnl = SherlockHNS.UI.Create("DPanel", sheet)
    pnl:SetPaintBackground(false)
    pnl:DockPadding(6, 6, 6, 6)

    -- ===== Esquerda: lista de tags =====
    local tagList = SherlockHNS.UI.Create("DListView", pnl)
    tagList:Dock(LEFT)
    tagList:SetWide(230)
    SherlockHNS.UI.Split(pnl, tagList, 230, 850)
    tagList:DockMargin(0, 0, 6, 0)
    tagList:SetMultiSelect(false)
    tagList:AddColumn("Prior."):SetFixedWidth(50)
    tagList:AddColumn("Tag")

    -- ===== Direita =====
    local right = SherlockHNS.UI.Create("DPanel", pnl)
    right:Dock(FILL)
    right:SetPaintBackground(false)

    local editor = SherlockHNS.UI.Create("DPanel", right)
    editor:Dock(TOP)
    editor:SetTall(250)
    editor:SetPaintBackground(false)

    local btns = SherlockHNS.UI.Create("DPanel", editor)
    SherlockHNS.UI.Flow(btns)
    btns:Dock(BOTTOM)
    btns:SetTall(28)
    btns:DockMargin(0, 6, 0, 0)
    btns:SetPaintBackground(false)

    local text = SherlockHNS.UI.Create("DTextEntry", editor)
    text:Dock(TOP)
    text:SetPlaceholderText("Texto da tag (ex.: Admin)")

    local prio = SherlockHNS.UI.Create("DNumSlider", editor)
    prio:Dock(TOP)
    prio:DockMargin(0, 6, 0, 0)
    prio:SetText("Prioridade (maior = mais importante)")
    prio:SetDark(true)
    prio:SetMin(0)
    prio:SetMax(100)
    prio:SetDecimals(0)
    prio:SetValue(10)

    local mixer = SherlockHNS.UI.Create("DColorMixer", editor)
    mixer:Dock(FILL)
    mixer:DockMargin(0, 6, 0, 0)
    mixer:SetPalette(false)
    mixer:SetAlphaBar(false)
    mixer:SetWangs(true)
    mixer:SetColor(Color(255, 200, 60))

    local function Btn(label, fn)
        local b = SherlockHNS.UI.Create("DButton", btns)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(110)
        b:SetText(label)
        b.DoClick = fn
    end

    Btn("Salvar", function()
        local col = mixer:GetColor()
        Send(ACT_SAVE, function()
            net.WriteUInt(selected or 0, 16)
            net.WriteString(text:GetValue())
            net.WriteUInt(col.r, 8)
            net.WriteUInt(col.g, 8)
            net.WriteUInt(col.b, 8)
            net.WriteInt(math.floor(prio:GetValue()), 16)
        end)
    end)

    Btn("Nova", function()
        selected = nil
        tagList:ClearSelection()
        text:SetValue("")
    end)

    Btn("Excluir", function()
        if not selected then return end
        local id = selected
        Derma_Query("Excluir esta tag de todos os players?", "Excluir tag",
            "Excluir", function()
                selected = nil
                Send(ACT_DELETE, function() net.WriteUInt(id, 16) end)
            end, "Cancelar")
    end)

    tagList.OnRowSelected = function(_, _, line)
        selected = line.tagId
        if filling then return end

        local d = T.Defs[line.tagId]
        if not d then return end
        text:SetValue(d.text)
        prio:SetValue(math.Clamp(d.priority, 0, 100))
        mixer:SetColor(Color(d.color.r, d.color.g, d.color.b))
    end

    -- ===== Players =====
    local pbtns = SherlockHNS.UI.Create("DPanel", right)
    SherlockHNS.UI.Flow(pbtns)
    pbtns:Dock(BOTTOM)
    pbtns:SetTall(28)
    pbtns:DockMargin(0, 6, 0, 0)
    pbtns:SetPaintBackground(false)

    local players = SherlockHNS.UI.Create("DListView", right)
    players:Dock(FILL)
    players:DockMargin(0, 6, 0, 0)
    players:SetMultiSelect(true)
    players:AddColumn("Jogador")
    players:AddColumn("Tags")

    local lines = {}
    local nextSync = 0
    function players:Think()
        if CurTime() < nextSync then return end
        nextSync = CurTime() + 0.5

        for p, line in pairs(lines) do
            if not IsValid(p) then
                self:RemoveLine(line:GetID())
                lines[p] = nil
            end
        end
        for _, p in ipairs(player.GetAll()) do
            if not p:IsBot() then
                local line = lines[p]
                if not line then
                    line = self:AddLine("", "")
                    line.ply = p
                    lines[p] = line
                end
                local names = {}
                for _, t in ipairs(T.GetTags(p)) do names[#names + 1] = t.text end
                line:SetColumnText(1, p:Nick())
                line:SetColumnText(2, table.concat(names, ", "))
            end
        end
    end

    local function ForSelected(act)
        if not selected then return end
        for _, line in ipairs(players:GetSelected()) do
            if IsValid(line.ply) then
                Send(act, function()
                    net.WriteEntity(line.ply)
                    net.WriteUInt(selected, 16)
                end)
            end
        end
    end

    local function PBtn(label, act)
        local b = SherlockHNS.UI.Create("DButton", pbtns)
        b:Dock(LEFT)
        b:DockMargin(0, 0, 6, 0)
        b:SetWide(170)
        b:SetText(label)
        b.DoClick = function() ForSelected(act) end
    end
    PBtn("Dar tag selecionada", ACT_GIVE)
    PBtn("Remover tag selecionada", ACT_TAKE)

    -- ===== Atualização das definições =====
    local function FillTags()
        if not IsValid(tagList) then return end

        filling = true
        tagList:Clear()

        local defs = {}
        for _, d in pairs(T.Defs) do defs[#defs + 1] = d end
        table.sort(defs, T.ByPriority)

        for _, d in ipairs(defs) do
            local line = tagList:AddLine(d.priority, d.text)
            line.tagId = d.id
            if d.id == selected then tagList:SelectItem(line) end
        end
        filling = false
    end

    hook.Add("SherlockHNS_TagsUpdated", "SherlockHNS_TagsTab", FillTags)
    FillTags()

    return pnl
end
