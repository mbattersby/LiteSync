--[[----------------------------------------------------------------------------

    LiteSync DB

----------------------------------------------------------------------------]]--

local DB = CreateFrame('Frame', 'LiteSync', UIParent)

DB:SetScript('OnEvent',
    function (self, e, ...)
        if self[e] then self[e](self, e, ...) end
    end)
DB:RegisterEvent('PLAYER_LOGIN')

local function SplitHyperlink(link)
    return link:match("|H(.+)|h(.*)|h")
end

local function GetItemDetailFromHyperlink(link)
    local id, rest, name = link:match("|H(.-:%d+)(.-)|h%[(.*)%]|h")
    return id, id..':'..rest, name
end

function DB:PLAYER_LOGIN()
    self:Initialize()
end

function DB:Dump()
    LoadAddOn('Blizzard_DebugTools')
    DevTools_Dump(self.db)
end

function DB:Initialize()
    LiteSyncDB = LiteSyncDB or { }
    self.db = LiteSyncDB

    self.name = format('%s-%s', UnitFullName('player'))
    self.realm = select(2, UnitFullName('player'))
    self.faction = UnitFactionGroup('player')

    local guild = GetGuildInfo('player')
    if guild then
        self.guildname = format('%s-%s', guild, self.realm)
    end

    self:UpdateEquipped()
    self:UpdateBags()
    self:UpdateMoney()
    self:UpdateCurrency()
end

function DB:Store(key, item)
    local cur = self.db
    
    for i,k in ipairs(key) do
        if i == #key then
            cur[k] = item
        else
            if not cur[k] or type(cur[k]) ~= 'table' then
                cur[k] = {}
            end
            cur = cur[k]
        end
    end
end

function DB:StorePlayer(key, item)
    local playerKey = { 'player', self.name }
    for _, k in ipairs(key) do tinsert(playerKey, k) end
    self:Store(playerKey, item)
end

function DB:StoreGuild(key, item)
    local guildKey = { 'guild', self.guildname }
    for _, k in ipairs(key) do tinsert(guildKey, k) end
    self:Store(guildKey, item)
end

function DB:_DoSearch(m, results)
end

function DB:Search(m)
    local results = { }
end

function DB:SearchByID(id)
    return self:Search(function (e) return e.id == id end)
end

function DB:UpdateEquipped()
	for i = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local id = GetInventoryItemID("player", i)
        local key = { 'equipped', i }
		if id then
            local link = GetInventoryItemLink("player", i)
            self:StorePlayer(key, { count=1, link=SplitHyperlink(link), id='item:'..id })
        else
            self:StorePlayer(key, nil)
		end
	end
end

local VOID_STORAGE_MAX = 80
local VOID_STORAGE_PAGES = 2

function DB:UpdateVoid()
    self:StorePlayer({'void'})

	for page = 1,VOID_STORAGE_PAGES do
		for i = 1,VOID_STORAGE_MAX do
            local key = { 'void', page, i }
			local id = GetVoidItemInfo(page, i)
			if id then
                self:StorePlayer(key, { id=id, count=1, link="item:"..id })
            else
                self:StorePlayer('void', key, nil)
			end
		end
	end
end

local MAX_GUILDBANK_SLOTS_PER_TAB = 98

function DB:UpdateGuildBankTab(tab)
    local _, _, isViewable = GetGuildBankTabInfo(tab)
    if not isViewable then
        self:StorePlayer({'guildbank', tab })
        return
    end

    for i = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
        local link = GetGuildBankItemLink(tab, i)
        local key = { 'guildbank', tab, i }
        if link then
            local id = GetItemInfoFromHyperlink(link)
            local _, count = GetGuildBankItemInfo(tab, i)
            self:StorePlayer(key, { id=id, count=count, link=SplitHyperlink(link) })
        else
            self:StorePlayer(key, nil)
        end
    end
end

function DB:UpdateGuildBank()
    self:StorePlayer({'guildbank'})
	for tab = 1, GetNumGuildBankTabs() do
        self:UpdateGuildBankTab(tab)
	end
end

function DB:UpdateBagContainer(where, bag)
    for slot = 1, GetContainerNumSlots(bag) do
        local key = { where, bag, slot }
        local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
        if link then
            local id, itemString, name = GetItemDetailFromHyperlink(link)
            if id:match('^keystone') then id = 'item:138019' end
            self:StorePlayer(key, { id=id, count=count, link=itemString })
        else
            self:StorePlayer(key, nil)
        end
    end
end

function DB:UpdateBags()
    self:StorePlayer({'bags'})
    for i = BACKPACK_CONTAINER, BACKPACK_CONTAINER+NUM_BAG_SLOTS do
        self:UpdateBagContainer('bags', i)
    end
end

function DB:UpdateBank()
    self:StorePlayer({'bank'})

    self:UpdateBagContainer('bank', BANK_CONTAINER)

    for i = NUM_BAG_SLOTS+1, NUM_BAG_SLOTS+NUM_BANKBAGSLOTS do
        self:UpdateBagContainer('bank', i)
    end

    if IsReagentBankUnlocked() then
        self:UpdateBagContainer('bank', REAGENTBANK_CONTAINER)
    end
end

function DB:UpdateMail()
    self:StorePlayer({'mail'})
    for m = 1, GetInboxNumItems() do
        for i = 1, ATTACHMENTS_MAX_RECEIVE do
            local key = { 'mail', m, i }
            local _, id, _, count = GetInboxItem(mailIndex, i)
            if id then
                local link = GetInboxItemLink(mailIndex, i)
                local id, itemString, name = GetItemDetailFromHyperlink(link)
                self:StorePlayer(key, { id=id, count=count, link=itemString })
            else
                self:StorePlayer(key, nil)
            end
        end
    end
end

local timeLeftData = {
    [1] = { min=0, max=30*60 },
    [2] = { min=30*60+1, max=2*3600 },
    [3] = { min=2*3600+1, max=12*3600 },
    [4] = { min=12*3600+1, max=48*3600 },
}

function DB:UpdateAuctions()
    for i = 1, GetNumAuctionItems('owner') do
        local _, _, count  = GetAuctionItemInfo("owner", i)
        if count then
            local link = GetAuctionItemLink("owner", i)
            local timeIndex = GetAuctionItemTimeLeft("owner", i)
            local expires = time() + timeLeftData[timeIndex].max
            local id, itemString, name = GetItemDetailFromHyperlink(link)
            self:StorePlayer(key, { id=id, count=count, link=itemString })
            self:StorePlayer({ 'auction', i }, { id=id, count=count, link=SplitHyperlink(link), expires=expires })
        else
            self:StorePlayer({ 'auction', i }, nil)
        end
    end
end

function DB:UpdateCurrency()
    local collapseMe = { }
    local i, limit = 1, GetCurrencyListSize()
    local category

    while i <= limit do
        local name, isHeader, isExpanded, _, _, amount = GetCurrencyListInfo(i)
        if isHeader then
            category = name
            if not isExpanded then
                collapseMe[i] = true
                ExpandCurrencyList(i, 1)
            end
        else
            self:StorePlayer({ 'currency', name }, { id=id, name=name, category=category, amount=amount })
        end
        i = i + 1
        limit = GetCurrencyListSize()
    end

    for i = limit, 1, -1 do
        if collapseMe[i] then
            ExpandCurrencyList(i, 0)
        end
    end
end

function DB:UpdateMoney()
    self:StorePlayer({ 'money' }, GetMoney())
end
