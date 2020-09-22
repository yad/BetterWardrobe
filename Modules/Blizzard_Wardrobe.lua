-- C_TransmogCollection.GetItemInfo(itemID, [itemModID]/itemLink/itemName) = appearanceID, sourceID
-- C_TransmogCollection.GetAllAppearanceSources(appearanceID) = { sourceID } This is cross-class, but no guarantee a source is actually attainable
-- C_TransmogCollection.GetSourceInfo(sourceID) = { data }
-- 15th return of GetItemInfo is expansionID
-- new events: TRANSMOG_COLLECTION_SOURCE_ADDED and TRANSMOG_COLLECTION_SOURCE_REMOVED, parameter is sourceID, can be cross-class (wand unlocked from ensemble while on warrior)
local addonName, addon = ...
--addon = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0")
addon = LibStub("AceAddon-3.0"):GetAddon(addonName)
local Profile
local Sets


local BASE_SET_BUTTON_HEIGHT = 46
local VARIANT_SET_BUTTON_HEIGHT = 20
local SET_PROGRESS_BAR_MAX_WIDTH = 204
local IN_PROGRESS_FONT_COLOR = CreateColor(0.251, 0.753, 0.251)
local IN_PROGRESS_FONT_COLOR_CODE = "|cff40c040"
local COLLECTION_LIST_WIDTH = 260

function addon.Init:Blizzard_Wardrobe()
	Profile = addon.Profile
	Sets = addon.Sets
end

--CollectionList:BuildCollectionList()

--===WardrobeCollectionFrame.ItemsCollectionFrame overwrites
local EXCLUSION_CATEGORY_OFFHAND	= 1
local EXCLUSION_CATEGORY_MAINHAND	= 2

local ItemsCollectionFrame = WardrobeCollectionFrame.ItemsCollectionFrame

function ItemsCollectionFrame:RefreshVisualsList()
	if ( self.transmogType == LE_TRANSMOG_TYPE_ILLUSION ) then
		self.visualsList = C_TransmogCollection.GetIllusions()
	else
		if( ItemsCollectionFrame:GetActiveSlot() == "MAINHANDSLOT" ) then
			self.visualsList = C_TransmogCollection.GetCategoryAppearances(self.activeCategory, EXCLUSION_CATEGORY_MAINHAND)
		elseif (ItemsCollectionFrame:GetActiveSlot() == "SECONDARYHANDSLOT" ) then
			self.visualsList = C_TransmogCollection.GetCategoryAppearances(self.activeCategory, EXCLUSION_CATEGORY_OFFHAND)
		else
			self.visualsList = C_TransmogCollection.GetCategoryAppearances(self.activeCategory)
		end

	end

	--Mod to allow visual view of sets from the journal
	if BW_CollectionListButton.ToggleState then self.visualsList = addon.CollectionList:BuildCollectionList() end

	self:FilterVisuals()
	self.filteredVisualsList = addon.Sets:ClearHidden(self.filteredVisualsList, "item")
	self:SortVisuals()

	self.PagingFrame:SetMaxPages(ceil(#self.filteredVisualsList / self.PAGE_SIZE))
end


function ItemsCollectionFrame:OnShow()
	self:RegisterEvent("TRANSMOGRIFY_UPDATE")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("TRANSMOGRIFY_SUCCESS")

	local needsUpdate = false	-- we don't need to update if we call WardrobeCollectionFrame_SetActiveSlot as that will do an update
	if ( self.jumpToLatestCategoryID and self.jumpToLatestCategoryID ~= self.activeCategory and not WardrobeFrame_IsAtTransmogrifier() ) then
		local slot = WardrobeCollectionFrame_GetSlotFromCategoryID(self.jumpToLatestCategoryID)
		-- The model got reset from OnShow, which restored all equipment.
		-- But ChangeModelsSlot tries to be smart and only change the difference from the previous slot to the current slot, so some equipment will remain left on.
		local ignorePreviousSlot = true
		self:SetActiveSlot(slot, LE_TRANSMOG_TYPE_APPEARANCE, self.jumpToLatestCategoryID, ignorePreviousSlot)
		self.jumpToLatestCategoryID = nil
	elseif ( self.activeSlot ) then
		-- redo the model for the active slot
		self:ChangeModelsSlot(nil, self.activeSlot)
		needsUpdate = true
	else
		self:SetActiveSlot("HEADSLOT", LE_TRANSMOG_TYPE_APPEARANCE)
	end

	WardrobeCollectionFrame.progressBar:SetShown(not WardrobeUtils_IsCategoryLegionArtifact(self:GetActiveCategory()))

	if ( needsUpdate ) then
		WardrobeCollectionFrame_UpdateUsableAppearances()
		self:RefreshVisualsList()
		self:UpdateItems()
		self:UpdateWeaponDropDown()
	end

	-- tab tutorial
	SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_JOURNAL_TAB, true)
	self:GetParent().SetsTabHelpBox:SetShown(self:ShouldShowSetsHelpTip())
	BW_WardrobeCollectionFrame.SetsTabHelpBox:SetShown(self:ShouldShowSetsHelpTip())

end

local SetsDataProvider = CreateFromMixins(WardrobeSetsDataProviderMixin)

function SetsDataProvider:SortSets(sets, reverseUIOrder, ignorePatchID)
	--local sortedSources = SetsDataProvider:GetSortedSetSources(data.setID)
	addon.SortSet(sets, reverseUIOrder, ignorePatchID)
	--addon.Sort["DefaultSortSet"](self, sets, reverseUIOrder, ignorePatchID)
end


function SetsDataProvider:GetBaseSets()
	if (not self.baseSets) then
		self.baseSets = addon.Sets:ClearHidden(C_TransmogSets.GetBaseSets(), "set")
		self:DetermineFavorites()
		self:SortSets(self.baseSets)
	end
	return self.baseSets
end


function SetsDataProvider:GetUsableSets(incVariants)
	if (not self.usableSets) then
		local atTransmogrifier = WardrobeFrame_IsAtTransmogrifier()
		local setIDS = {}

		if not Profile.ShowIncomplete  then 
			self.usableSets = C_TransmogSets.GetUsableSets()
			self:SortSets(self.usableSets)
			-- group sets by baseSetID, except for favorited sets since those are to remain bucketed to the front
			for i, set in ipairs(self.usableSets) do
				setIDS[set.baseSetID or set.setID] = true
				if (not set.favorite) then
					local baseSetID = set.baseSetID or set.setID
					local numRelatedSets = 0
					for j = i + 1, #self.usableSets do
						if (self.usableSets[j].baseSetID == baseSetID or self.usableSets[j].setID == baseSetID) then
							numRelatedSets = numRelatedSets + 1
							-- no need to do anything if already contiguous
							if (j ~= i + numRelatedSets) then
								local relatedSet = self.usableSets[j]
								tremove(self.usableSets, j)
								tinsert(self.usableSets, i + numRelatedSets, relatedSet)
							end
						end
					end
				end
			end
			return self.usableSets
		end

		if Profile.ShowIncomplete or BW_WardrobeToggle.VisualMode then 
			self.usableSets = {}
			local availableSets = self:GetBaseSets()
			for i, set in ipairs(availableSets) do
				if not setIDS[set.setID or set.baseSetID] then 
					local topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceCounts(set.setID)

					if ((not atTransmogrifier and BW_WardrobeToggle.VisualMode) or topSourcesCollected >= Profile.PartialLimit)  then --and not C_TransmogSets.IsSetUsable(set.setID) then
						
						tinsert(self.usableSets, set)
					end
				end

				if incVariants then 
					local variantSets = C_TransmogSets.GetVariantSets(set.setID)
					for i, set in ipairs(variantSets) do
						if not setIDS[set.setID or set.baseSetID] then 
							local topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceCounts(set.setID)
							if topSourcesCollected == topSourcesTotal then set.collected = true end
							if ((not atTransmogrifier and BW_WardrobeToggle.VisualMode) or topSourcesCollected >= Profile.PartialLimit)  then --and not C_TransmogSets.IsSetUsable(set.setID) then
								tinsert(self.usableSets, set)
							end
						end
						
					end
				end
			end

		elseif not Profile.ShowIncomplete  then 
		self.usableSets = C_TransmogSets.GetUsableSets()

		self:SortSets(self.usableSets)
		-- group sets by baseSetID, except for favorited sets since those are to remain bucketed to the front
			for i, set in ipairs(self.usableSets) do
				setIDS[set.baseSetID or set.setID] = true
				if (not set.favorite) then
					local baseSetID = set.baseSetID or set.setID
					local numRelatedSets = 0
					for j = i + 1, #self.usableSets do
						if (self.usableSets[j].baseSetID == baseSetID or self.usableSets[j].setID == baseSetID) then
							numRelatedSets = numRelatedSets + 1
							-- no need to do anything if already contiguous
							if (j ~= i + numRelatedSets) then
								local relatedSet = self.usableSets[j]
								tremove(self.usableSets, j)
								tinsert(self.usableSets, i + numRelatedSets, relatedSet)
							end
						end
					end
				end
			end
		end
				
		self:SortSets(self.usableSets)
	end

	return addon.Sets:ClearHidden(self.usableSets, "set") 
end


function SetsDataProvider:FilterSearch()
	local baseSets = self:GetUsableSets(true)
	local filteredSets = {}
	local searchString = string.lower(WardrobeCollectionFrameSearchBox:GetText())

	if searchString then 
		for i = 1, #baseSets do
			local baseSet = baseSets[i]
			local match = string.find(string.lower(baseSet.name), searchString) -- or string.find(baseSet.label, searchString) or string.find(baseSet.description, searchString)
			
			if match then 
				tinsert(filteredSets, baseSet)
			end
		end

		self.usableSets = filteredSets 
	else 
		self.usableSets = baseSets 
	end
	self:SortSets(self.usableSets)

end


--===WardrobeCollectionFrame.SetsCollectionFrame===--
function WardrobeCollectionFrame.SetsCollectionFrame:OnSearchUpdate()
	if (self.init) then
		SetsDataProvider:ClearBaseSets()
		SetsDataProvider:ClearVariantSets()
		SetsDataProvider:ClearUsableSets()
		self:Refresh()
	end
end


function WardrobeCollectionFrame.SetsCollectionFrame:OnShow()
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	-- select the first set if not init
	local baseSets = SetsDataProvider:GetBaseSets()
	if (not self.init) then
		self.init = true
		if (baseSets and baseSets[1]) then
			self:SelectSet(self:GetDefaultSetIDForBaseSet(baseSets[1].setID))
		end
	else
		self:Refresh()
	end

	local latestSource = C_TransmogSets.GetLatestSource()
	if (latestSource ~= NO_TRANSMOG_SOURCE_ID) then
		local sets = C_TransmogSets.GetSetsContainingSourceID(latestSource)
		local setID = sets and sets[1]
		if (setID) then
			self:SelectSet(setID)
			local baseSetID = C_TransmogSets.GetBaseSetID(setID)
			self:ScrollToSet(baseSetID)
		end
		self:ClearLatestSource()
	end

	WardrobeCollectionFrame.progressBar:Show()
	self:UpdateProgressBar()
	self:RefreshCameras()

	if (self:GetParent().SetsTabHelpBox:IsShown()) or BW_WardrobeCollectionFrame.SetsTabHelpBox:IsShown() then
		self:GetParent().SetsTabHelpBox:Hide()
		BW_WardrobeCollectionFrame.SetsTabHelpBox:Hide()
		SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_TAB, true)
	end
end



function WardrobeCollectionFrame.SetsCollectionFrame:HandleKey(key)
	if (not self:GetSelectedSetID()) then
		return false
	end
	local selectedSetID = C_TransmogSets.GetBaseSetID(self:GetSelectedSetID())
	local _, index = SetsDataProvider:GetBaseSetByID(selectedSetID)
	if (not index) then
		return
	end
	if (key == WARDROBE_DOWN_VISUAL_KEY) then
		index = index + 1
	elseif (key == WARDROBE_UP_VISUAL_KEY) then
		index = index - 1
	end
	local sets = SetsDataProvider:GetBaseSets()
	index = Clamp(index, 1, #sets)
	self:SelectSet(self:GetDefaultSetIDForBaseSet(sets[index].setID))
	self:ScrollToSet(sets[index].setID)
end


function WardrobeCollectionFrame.SetsCollectionFrame:ScrollToSet(setID)
	local totalHeight = 0
	local scrollFrameHeight = self.ScrollFrame:GetHeight()
	local buttonHeight = self.ScrollFrame.buttonHeight
	for i, set in ipairs(SetsDataProvider:GetBaseSets()) do
		if (set.setID == setID) then
			local offset = self.ScrollFrame.scrollBar:GetValue()
			if (totalHeight + buttonHeight > offset + scrollFrameHeight) then
				offset = totalHeight + buttonHeight - scrollFrameHeight
			elseif (totalHeight < offset) then
				offset = totalHeight
			end
			self.ScrollFrame.scrollBar:SetValue(offset, true)
			break
		end
		totalHeight = totalHeight + buttonHeight
	end
end


WardrobeCollectionFrame.SetsCollectionFrame:SetScript("OnShow", WardrobeCollectionFrame.SetsCollectionFrame.OnShow)


function WardrobeCollectionFrame.SetsTransmogFrame:OnSearchUpdate()
	SetsDataProvider:ClearUsableSets()
	SetsDataProvider:FilterSearch()
	WardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
end


--local BetterWardrobeSetsTransmogMixin = CreateFromMixins(WardrobeSetsTransmogMixin)

function WardrobeCollectionFrame.SetsTransmogFrame:UpdateSets()
	local usableSets = SetsDataProvider:GetUsableSets(true)
	self.PagingFrame:SetMaxPages(ceil(#usableSets / self.PAGE_SIZE))
	local pendingTransmogModelFrame = nil
	local indexOffset = (self.PagingFrame:GetCurrentPage() - 1) * self.PAGE_SIZE
	for i = 1, self.PAGE_SIZE do
		local model = self.Models[i]
		local index = i + indexOffset
		local set = usableSets[index]

		if (set) then
			model:Show()

			--if (model.setID ~= set.setID) then
				model:Undress()
				local sourceData = SetsDataProvider:GetSetSourceData(set.setID)

				for sourceID in pairs(sourceData.sources) do
					--if (not Profile.HideMissing and not BW_WardrobeToggle.VisualMode) or (Profile.HideMissing and BW_WardrobeToggle.VisualMode) or (Profile.HideMissing and isMogKnown(sourceID)) then 
					if (not Profile.HideMissing and (not BW_WardrobeToggle.VisualMode or (Sets.isMogKnown(sourceID) and BW_WardrobeToggle.VisualMode))) or 
						(Profile.HideMissing and (BW_WardrobeToggle.VisualMode or Sets.isMogKnown(sourceID))) then 
						model:TryOn(sourceID)
					end
				end
			--end

			local transmogStateAtlas
			if (set.setID == self.appliedSetID and set.setID == self.selectedSetID) then
				transmogStateAtlas = "transmog-set-border-current-transmogged"
			elseif (set.setID == self.selectedSetID) then
				transmogStateAtlas = "transmog-set-border-selected"
				pendingTransmogModelFrame = model
			end

			if (transmogStateAtlas) then
				model.TransmogStateTexture:SetAtlas(transmogStateAtlas, true)
				model.TransmogStateTexture:Show()
			else
				model.TransmogStateTexture:Hide()
			end

			local topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceCounts(set.setID)
			local setInfo = C_TransmogSets.GetSetInfo(set.setID)

			model.Favorite.Icon:SetShown(C_TransmogSets.GetIsFavorite(set.setID))
			model.setID = set.setID

			local isHidden = addon.chardb.profile.set[set.setID]
			model.CollectionListVisual.Hidden.Icon:SetShown(isHidden)

			local isInList = addon.chardb.profile.collectionList["set"][set.setID] 
			model.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
			model.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and C_TransmogSets.IsBaseSetCollected(set.setID))

			model.SetInfo.setName:SetText((Profile.ShowNames and setInfo["name"].."\n"..(setInfo["description"] or "")) or "")
			model.SetInfo.progress:SetText((Profile.ShowSetCount and topSourcesCollected.."/".. topSourcesTotal) or "")
			model.setCollected = topSourcesCollected == topSourcesTotal


		else
			model:Hide()
		end
	end

	if (pendingTransmogModelFrame) then
		self.PendingTransmogFrame:SetParent(pendingTransmogModelFrame)
		self.PendingTransmogFrame:SetPoint("CENTER")
		self.PendingTransmogFrame:Show()
		if (self.PendingTransmogFrame.setID ~= pendingTransmogModelFrame.setID) then
			self.PendingTransmogFrame.TransmogSelectedAnim:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim2:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim2:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim3:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim3:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim4:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim4:Play()
			self.PendingTransmogFrame.TransmogSelectedAnim5:Stop()
			self.PendingTransmogFrame.TransmogSelectedAnim5:Play()
		end
		self.PendingTransmogFrame.setID = pendingTransmogModelFrame.setID
	else
		self.PendingTransmogFrame:Hide()
	end

	self.NoValidSetsLabel:SetShown(not C_TransmogSets.HasUsableSets())
end


function WardrobeCollectionFrame.SetsTransmogFrame:LoadSet(setID)
	local waitingOnData = false
	local transmogSources = { }
	local sources = C_TransmogSets.GetSetSources(setID)
	local combineSources = IsShiftKeyDown()
	local selectedItems = {}

	for sourceID in pairs(sources) do
		local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
			local slot = C_Transmog.GetSlotForInventoryType(sourceInfo.invType)
			local slotSources = C_TransmogSets.GetSourcesForSlot(setID, slot)
	if slotSources then 
			WardrobeCollectionFrame_SortSources(slotSources, sourceInfo.visualID)
			local index = WardrobeCollectionFrame_GetDefaultSourceIndex(slotSources, sourceID)
			local knownID = Sets.isMogKnown(sourceID)
			if knownID then transmogSources[slot] = knownID end

			if combineSources then 
				local _, hasPending = C_Transmog.GetSlotInfo(slot, LE_TRANSMOG_TYPE_APPEARANCE)
				if hasPending then 
					local _,_,_,_,sourceID, appearanceID = C_Transmog.GetSlotVisualInfo(slot, LE_TRANSMOG_TYPE_APPEARANCE)

					local emptyappearanceID, emptySourceID = EmptyArmor[slot] and C_TransmogCollection.GetItemInfo(EmptyArmor[slot])

					if appearanceID == emptyappearanceID then
						C_Transmog.ClearPending(slot, LE_TRANSMOG_TYPE_APPEARANCE)
						transmogSources[slot] = slotSources[index].sourceID
					else				
						transmogSources[slot] = sourceID
					end

				else
					transmogSources[slot] = (slotSources[index] and slotSources[index].sourceID) or sourceID
				end
			else

				transmogSources[slot] = (slotSources[index] and slotSources[index].sourceID) or sourceID
			end
	

			for i, slotSourceInfo in ipairs(slotSources) do
				if (not slotSourceInfo.name) then
					waitingOnData = true
				end
			end
		end
	end
	if (waitingOnData) then
		self.loadingSetID = setID
	else
		self.loadingSetID = nil
		-- if we don't ignore the event, clearing will momentarily set the page to the one with the set the user currently has transmogged
		-- if that's a different page from the current one then the models will flicker as we swap the gear to different sets and back
		self.ignoreTransmogrifyUpdateEvent = true
		C_Transmog.ClearPending()
		self.ignoreTransmogrifyUpdateEvent = false
		C_Transmog.LoadSources(transmogSources, -1, -1)

		if Profile.HiddenMog then				
			local emptySlotData = addon.Sets:GetEmptySlots()
			for i, x in pairs(transmogSources) do
				if not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(x) and i ~= 7 and emptySlotData[i] then
					local _, source = addon.GetItemSource(emptySlotData[i]) -- C_TransmogCollection.GetItemInfo(emptySlotData[i])
					C_Transmog.SetPending(i, LE_TRANSMOG_TYPE_APPEARANCE, source)
				end
			end
		end
	end
end


local function GetPage(entryIndex, pageSize)
	return floor((entryIndex-1) / pageSize) + 1
end


function WardrobeCollectionFrame.SetsTransmogFrame:ResetPage()
	local page = 1
	if (self.selectedSetID) then
		local usableSets = SetsDataProvider:GetUsableSets(true)
		self.PagingFrame:SetMaxPages(ceil(#usableSets / self.PAGE_SIZE))
		for i, set in ipairs(usableSets) do
			if (set.setID == self.selectedSetID) then
				page = GetPage(i, self.PAGE_SIZE)
				break
			end
		end
	end
	self.PagingFrame:SetCurrentPage(page)
	self:UpdateSets()
end


function WardrobeCollectionFrame.SetsTransmogFrame:OnShow()
	self:RegisterEvent("TRANSMOGRIFY_UPDATE")
	self:RegisterEvent("TRANSMOGRIFY_SUCCESS")
	self:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
	self:RefreshCameras()
	local RESET_SELECTION = true
	self:Refresh(RESET_SELECTION)
	WardrobeCollectionFrame.progressBar:Show()
	self:UpdateProgressBar()
	self.sourceQualityTable = { }

	if (self:GetParent().SetsTabHelpBox:IsShown()) or (BW_WardrobeCollectionFrame.SetsTabHelpBox:IsShown()) then
		self:GetParent().SetsTabHelpBox:Hide()
		BW_WardrobeCollectionFrame.SetsTabHelpBox:Hide()
		SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_TRANSMOG_SETS_VENDOR_TAB, true)
	end
end


function WardrobeCollectionFrame.SetsTransmogFrame:OnHide()
	self:UnregisterEvent("TRANSMOGRIFY_UPDATE")
	self:UnregisterEvent("TRANSMOGRIFY_SUCCESS")
	self:UnregisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	self:UnregisterEvent("TRANSMOG_COLLECTION_UPDATED")
	self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:UnregisterEvent("TRANSMOG_SETS_UPDATE_FAVORITE")
	self.loadingSetID = nil
	SetsDataProvider:ClearSets()
	WardrobeCollectionFrame_ClearSearch(LE_TRANSMOG_SEARCH_TYPE_USABLE_SETS)
	self.sourceQualityTable = nil
	BW_WardrobeToggle.VisualMode = false
end


function WardrobeCollectionFrame.SetsTransmogFrame:OnEvent(event, ...)
	if (event == "TRANSMOGRIFY_UPDATE" and not self.ignoreTransmogrifyUpdateEvent) then
		self:Refresh()
	elseif (event == "TRANSMOGRIFY_SUCCESS") then
		-- this event fires once per slot so in the case of a set there would be up to 9 of them
		if (not self.transmogrifySuccessUpdate) then
			self.transmogrifySuccessUpdate = true
			C_Timer.After(0, function() self.transmogrifySuccessUpdate = nil self:Refresh() end)
		end
	elseif (event == "TRANSMOG_COLLECTION_UPDATED" or event == "TRANSMOG_SETS_UPDATE_FAVORITE") then
		SetsDataProvider:ClearSets()
		self:Refresh()
		self:UpdateProgressBar()
	elseif (event == "TRANSMOG_COLLECTION_ITEM_UPDATE") then
		if (self.loadingSetID) then
			local setID = self.loadingSetID
			self.loadingSetID = nil
			self:LoadSet(setID)
		end
		if (self.tooltipModel) then
			self.tooltipModel:RefreshTooltip()
		end
	elseif (event == "PLAYER_EQUIPMENT_CHANGED") then
		if (self.selectedSetID) then
			self:LoadSet(self.selectedSetID)
		end
		self:Refresh()
	end
end

WardrobeCollectionFrame.SetsTransmogFrame:SetScript("OnShow", WardrobeCollectionFrame.SetsTransmogFrame.OnShow)
WardrobeCollectionFrame.SetsTransmogFrame:SetScript("OnHide", WardrobeCollectionFrame.SetsTransmogFrame.OnHide)
WardrobeCollectionFrame.SetsTransmogFrame:SetScript("OnEvent", WardrobeCollectionFrame.SetsTransmogFrame.OnEvent)


function WardrobeCollectionFrame.SetsCollectionFrame.ScrollFrame:Update()
	local offset = HybridScrollFrame_GetOffset(self)
	local buttons = self.buttons
	local baseSets = SetsDataProvider:GetBaseSets()

	-- show the base set as selected
	local selectedSetID = self:GetParent():GetSelectedSetID()
	local selectedBaseSetID = selectedSetID and C_TransmogSets.GetBaseSetID(selectedSetID)

	for i = 1, #buttons do
		local button = buttons[i]
		local setIndex = i + offset
		if (setIndex <= #baseSets) then
			local baseSet = baseSets[setIndex]
			button:Show()
			button.Name:SetText(baseSet.name)
			local topSourcesCollected, topSourcesTotal = SetsDataProvider:GetSetSourceTopCounts(baseSet.setID)
			local setCollected = C_TransmogSets.IsBaseSetCollected(baseSet.setID)
			local color = IN_PROGRESS_FONT_COLOR
			if (setCollected) then
				color = NORMAL_FONT_COLOR
			elseif (topSourcesCollected == 0) then
				color = GRAY_FONT_COLOR
			end
			button.Name:SetTextColor(color.r, color.g, color.b)
			button.Label:SetText(baseSet.label)
			button.Icon:SetTexture(SetsDataProvider:GetIconForSet(baseSet.setID))
			button.Icon:SetDesaturation((topSourcesCollected == 0) and 1 or 0)
			button.SelectedTexture:SetShown(baseSet.setID == selectedBaseSetID)
			button.Favorite:SetShown(baseSet.favoriteSetID and true)
			local isHidden = addon.chardb.profile.set[baseSet.setID]
			button.CollectionListVisual.Hidden.Icon:SetShown(isHidden)

			local variantSets = SetsDataProvider:GetVariantSets(baseSet.setID)
			local variantSelected
			for i, data in ipairs(variantSets) do
				if addon.chardb.profile.collectionList["set"][data.setID] then 
					variantSelected = data.setID
				end
			end

			local isInList = addon.chardb.profile.collectionList["set"][variantSelected and variantSelected or baseSet.setID] 
			button.CollectionListVisual.Collection.Collection_Icon:SetShown(isInList)
			button.CollectionListVisual.Collection.Collected_Icon:SetShown(isInList and C_TransmogSets.IsBaseSetCollected(baseSet.setID))
			button.New:SetShown(SetsDataProvider:IsBaseSetNew(baseSet.setID))
			button.setID = baseSet.setID

			if (topSourcesCollected == 0 or setCollected) then
				button.ProgressBar:Hide()
			else
				button.ProgressBar:Show()
				button.ProgressBar:SetWidth(SET_PROGRESS_BAR_MAX_WIDTH * topSourcesCollected / topSourcesTotal)
			end
			button.IconCover:SetShown(not setCollected)
		else
			button:Hide()
		end
	end

	local extraHeight = (self.largeButtonHeight and self.largeButtonHeight - BASE_SET_BUTTON_HEIGHT) or 0
	local totalHeight = #baseSets * BASE_SET_BUTTON_HEIGHT + extraHeight
	HybridScrollFrame_Update(self, totalHeight, self:GetHeight())
end
--This bit sets "update" which is set via on load and triggers when scrolling. Its what caused sorting issues
WardrobeCollectionFrame.SetsCollectionFrame.ScrollFrame.update = WardrobeCollectionFrame.SetsCollectionFrame.ScrollFrame.Update

--=======