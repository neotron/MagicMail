
local mod = {}
local GeminiGUI = Apollo.GetPackage("Gemini:GUI-1.0").tPackage
local MailAddonOnMailResult
local MailAddonComposeOnInfoChanged
local strupper = string.upper
local strfind = string.find
local strlen = string.len
local sort = table.sort
local MagicMailInstance

function mod:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self 
   return o
end

function mod:Init()
   Apollo.RegisterAddon(self, false, "Configure", { "Mail" })
   Apollo.RegisterSlashCommand("magmail", "OnSlashCommand", self)
   mod.guiDefinition = { -- PushButton
      WidgetType    = "PushButton",
      Text          = "Take All",
      Name = "TakeAllBtn",
      Base = "CRB_Basekit:kitBtn_Metal_LargeGreen",
      AnchorPoints = { 0, 1, 0, 1 },
      AnchorOffsets = {212,-78,324,-31},
      NormalTextColor = "UI_BtnTextGreenNormal",
      PressedTextColor = "UI_BtnTextGreenPressed",
      Events = { ButtonSignal = function()
		    self:OnSlashCommand()
	       end },
   }
   Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
   Apollo.RegisterEventHandler("MailResult",            "OnMailResult", self)
   Apollo.RegisterEventHandler("GuildRoster",           "OnGuildRoster", self)
   Apollo.RegisterEventHandler("GuildMemberChange",     "OnGuildMemberChange", self)
   Apollo.RegisterEventHandler("WindowManagementAdd",   "OnWindowManagementAdd", self)
   
   -- This is used to filter characters in mail recipients
   local charInfo = GameLib.GetAccountRealmCharacter()
   self.character = charInfo.strCharacter
   self.realm = charInfo.strRealm
   self.faction = GameLib.GetPlayerUnit():GetFaction()
end

function mod:OnMailResult(result)
   if result == GameLib.CodeEnumGenericError.Mail_MailBoxOutOfRange  or
      result == GameLib.CodeEnumGenericError.Item_InventoryFull then
      -- Can still get cash
      Print("Too far away, fetching cash only.")
      self.getCashOnly = true;
   elseif result == GameLib.CodeEnumGenericError.Mail_Busy then
      self:FinishMailboxProcess(true)
   else
      MailAddonOnMailResult(result)
   end
end

function mod:OnWindowManagementAdd(tbl)
   if tbl and tbl.strName == Apollo.GetString("Mail_ComposeLabel") then
      MailAddonOnInfoChanged = self.mailAddon.luaComposeMail.OnInfoChanged
      self.mailAddon.luaComposeMail.OnInfoChanged = self.OnInfoChangedWrapper
      self.composeRecipient = self.mailAddon.luaComposeMail.wndMain:FindChild("NameEntryText")
   end
end

function mod:OnWindowManagementReady()
   self.mailAddon = Apollo.GetAddon("Mail")
   MailAddonOnMailResult = self.mailAddon.OnMailResult

   local mailform = self.mailAddon.wndMain:FindChild("MailForm")
   self.button = mailform:FindChild("TakeAllBtn") or GeminiGUI:Create(self.guiDefinition):GetInstance(self, mailform)
   
   for _,guild in ipairs(GuildLib.GetGuilds()) do
      guild:RequestMembers()
   end
end

function mod:OnInfoChangedWrapper(wndHandler, wndControl)
   if wndControl ~= wndHandler then
      return
   end
   -- call mail addon method
   MailAddonOnInfoChanged(self, wndHandler, wndControl)

   if wndControl == MagicMailInstance.composeRecipient then
      local partial = wndControl:GetText()
      local matches = MagicMailInstance:MatchPartialName(partial)
      if matches and  #matches > 0 then
	 -- temporary until list is added
	 wndControl:SetText(matches[1])
	 wndControl:SetSel(partial:len(), -1)
      end
   end
end

function mod:OnSlashCommand()
   if self.pendingMails or self.busyTimer then
      self:FinishMailboxProcess()
   else
      self:ProcessMailbox()
   end
end

function mod:ProcessMailbox()
   self:StopTimers()
   local pendingMails = MailSystemLib.GetInbox()
   if not #pendingMails then
      return
   end
   if self.button then self.button:SetText("Cancel ("..#pendingMails..")") end
   self.pendingMails = pendingMails
   self.mailsToDelete = {}
   self.currentMailIndex = 1
   self.getCashOnly = false
   -- quiet down the standard mailbox
   MailAddonOnMailResult = Apollo.GetAddon("Mail").OnMailResult
   Apollo.GetAddon("Mail").OnMailResult = function() end 
   self:ProcessNextBatch()
end

function mod:ProcessNextBatch()
   if not self.pendingMails then
      return
   end
   local startIdx = self.currentMailIndex or 1
   local isLastBatch = false
   local mails = self.pendingMails

   local mail, sender, subject, hasMoney, hasAttachments, msgInfo
   local endIdx = #mails
   local lastProcessedIndex = 0
   -- do at most 10 mails at a time
   if endIdx > startIdx + 10 then
      endIdx = startIdx + 10
   end

   for i=startIdx,endIdx do
      lastProcessedIndex = i
      mail = self.pendingMails[i]
      msgInfo = mail:GetMessageInfo()
      sender = msgInfo.strSenderName
      subject = msgInfo.strSubject
      hasMoney = not msgInfo.monGift:IsZero()
      hasAttachments = #msgInfo.arAttachments > 0
      local processed = false
      if sender == "Phineas T. Rotostar" or subject == "Here's your stuff!" then
	 -- Auction house
	 local shouldDelete = true
	 if hasAttachments then
	    if self.getCashOnly then
	       shouldDelete = false
	    else
	       mail:TakeAllAttachments()
	       processed = true
	    end
	 end
	 if hasMoney then
	    mail:TakeMoney()
	    processed = true
	 end
	 if shouldDelete then
	    local count = #self.mailsToDelete + 1
	    self.mailsToDelete[#self.mailsToDelete+1] = mail
	    if count > 20 then
	       MailSystemLib.DeleteMultipleMessages(self.mailsToDelete)
	       self.mailsToDelete = {}
	    end
	 end
      else
	 if hasAttachments and not self.getCashOnly then
	    processed = true
	    mail:TakeAllAttachments()
	 end
	 if hasMoney then
	    processed = true
	    mail:TakeMoney();
	 end
      end
      if processed then
	 -- Delay execution 
	 break 
      end
   end

   if lastProcessedIndex < #mails then
      self.currentMailIndex = lastProcessedIndex + 1
      if self.button then self.button:SetText("Cancel ("..(#mails-self.currentMailIndex)..")") end
      if not self.timer then
	 self.timer = ApolloTimer.Create(0.4, true, "ProcessNextBatch", self)
      end
   else 
      self:FinishMailboxProcess()
   end
end


function mod:FinishMailboxProcess(busy)
   self:StopTimers()
   if not busy and self.mailsToDelete and #self.mailsToDelete > 0 then
      MailSystemLib.DeleteMultipleMessages(self.mailsToDelete)
   end
   self.currentMailIndex = nil
   self.pendingMails = nil
   self.mailsToDelete = nil
   if busy then 
      self.button:SetText("Busy...")
      self.busyTimer = ApolloTimer.Create(3.141596, false, "ProcessMailbox", self);
   else
      self.button:SetText("Take All")
      -- restore mail addon handler, after a short delay
      self.resultTimer = ApolloTimer.Create(0.5, false, "RestoreResultHandler", self)
   end

end


function mod:RestoreResultHandler()
   Apollo.GetAddon("Mail").OnMailResult = MailAddonOnMailResult
   self.resultTimer = nil
end

function mod:StopTimers()
   if self.timer then
      self.timer:Stop()
      self.timer = nil
   end
   if self.busyTimer then
      self.busyTimer:Stop()
      self.busyTimer = nil
   end
   if self.resultTimer then
      self.resultTimer:Stop()
      self.resultTimer = nil
   end
end

-- AutoCompletion management
-- This method returns a list of matching friends, up to a maximum of 10
function mod:MatchPartialName(partial)
   if strlen(partial or "") == 0 then
      return nil
   end
   local matches = {}
   partial = strupper(partial)
   local numFound = 0
   local fetchMore
   fetchMore, numFound = self:FindMoreMatchesInTable(partial, FriendshipLib.GetList(), matches, numFound);

   for _,roster in pairs(self.guildRoster) do
      if fetchMore then
	 fetchMore, numFound = self:FindMoreMatchesInTable(partial, roster, matches, numFound);
      end
   end

   if fetchMore then
      fetchMore, numFound = self:FindMoreMatchesInTable(partial, HousingLib.GetNeighborList(), matches, numFound);
   end
   local sorted = {}
   for v in pairs(matches) do
      sorted[#sorted+1] = v
   end
   sort(sorted)
   return sorted
end

function mod:FindMoreMatchesInTable(partial, tbl, matches, numFound)
   local realm, faction, name
   for k,v in pairs(tbl) do
      realm = v.realm or v.strRealmName
      faction = v.faction or v.nFactionId
      name = v.name or v.strCharacterName
      if (name ~= self.character)
	 and (not realm or realm == self.realm)
	 and (not faction or faction == self.faction)
         and (strfind(strupper(name), partial) == 1)
	 and not matches[name] then
	    matches[name] = true
	    numFound = numFound +1
      end
      if numFound >= 10 then
	 return false, numFound
      end
   end
   return true, numFound
end

function mod:GuildId(guildCurr)
   return guildCurr:GetType()..":"..guildCurr:GetName()
end


function mod:OnGuildMemberChange( guildCurr )
   if guildCurr and guildCurr:GetType() == GuildLib.GuildType_Guild then
      if self.guildRoster then
	 self.guildRoster[self:GuildId(guildCurr)] = nil
      end
      guildCurr:RequestMembers()
   end
end

-- Update roster for a guild. We only care about the name since guilds are realm specific
function mod:OnGuildRoster(guildCurr, roster)   
   if not self.guildRoster then self.guildRoster = {} end
   -- circles and guilds can have the same name, make them unique
   local guildName =  self:GuildId(guildCurr)
   local memberNames = self.guildRoster[guildCurr:GetName()] or {}
   for _,member in ipairs(memberNames) do
      roster[member] = nil
   end
   for _,member in ipairs(roster) do 
      memberNames[#memberNames + 1] = { name = member.strName }
   end
   self.guildRoster[guildName] = memberNames
end
-- creating the instance.

MagicMailInstance = mod:new()
MagicMailInstance:Init()
