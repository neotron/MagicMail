require "Window"
require "MailSystemLib"
require "GameLib"
require "Apollo"

local MagicMail = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MagicMail", false, { "Mail" }, "Gemini:Hook-1.0" )
local GeminiGUI = Apollo.GetPackage("Gemini:GUI-1.0").tPackage
local strupper = string.upper
local strfind = string.find
local strlen = string.len
local sort = table.sort


function MagicMail:OnInitialize()
   Apollo.RegisterSlashCommand("magmail", "OnSlashCommand", self)
   self.guiDefinition = { -- PushButton
      WidgetType    = "PushButton",
      Text          = "Take All",
      Name = "TakeAllBtn",
      Base = "CRB_Basekit:kitBtn_Metal_LargeGreen",
      AnchorPoints = { 0, 1, 0, 1 },
      AnchorOffsets = {212,-78,324,-31},
      NormalTextColor = "UI_BtnTextGreenNormal",
      PressedTextColor = "UI_BtnTextGreenPressed",
      Events = {
	 ButtonSignal = "OnSlashCommand"
      },
   }
   Apollo.RegisterEventHandler("WindowManagementAdd",   "OnWindowManagementAdd", self)
   Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
   Apollo.RegisterEventHandler("GuildRoster",           "OnGuildRoster", self)
   Apollo.RegisterEventHandler("GuildMemberChange",     "OnGuildMemberChange", self)
end

function MagicMail:OnEnable()
   for _,guild in ipairs(GuildLib.GetGuilds()) do
      guild:RequestMembers()
   end
   -- This is used to filter characters in mail recipients
   local charInfo = GameLib.GetAccountRealmCharacter()
   self.character = charInfo.strCharacter
   self.realm = charInfo.strRealm
   self.faction = GameLib.GetPlayerUnit():GetFaction()
end

function MagicMail:OnDisable()
   self:UnhookAll()
end

function MagicMail:OnMailResult(luaCaller, result)
   if result == GameLib.CodeEnumGenericError.Mail_MailBoxOutOfRange  or
   result == GameLib.CodeEnumGenericError.Item_InventoryFull then
      -- Can still get cash
      Print("Too far away, fetching cash only.")
      self.getCashOnly = true;
   elseif result == GameLib.CodeEnumGenericError.Mail_Busy then
      self:FinishMailboxProcess(true)
   else
      self.hooks[self.mailAddon].OnMailResult(luaCaller, result)
   end
end

function MagicMail:OnWindowManagementReady()
   self.mailAddon = Apollo.GetAddon("Mail")
   local mailform = self.mailAddon.wndMain:FindChild("MailForm")
   self.button = mailform:FindChild("TakeAllBtn") or GeminiGUI:Create(self.guiDefinition):GetInstance(self, mailform)
end

function MagicMail:OnWindowManagementAdd(tbl)
   if tbl and tbl.strName == Apollo.GetString("Mail_ComposeLabel") then
      self:PostHook(self.mailAddon.luaComposeMail, "OnInfoChanged")
      self.composeRecipient = self.mailAddon.luaComposeMail.wndMain:FindChild("NameEntryText")
   end
end

function MagicMail:OnInfoChanged(luaCaller, wndHandler, wndControl)
   Print("OnInfoChanged")
   if wndControl == self.composeRecipient then
      local partial = wndControl:GetText()
      local matches = self:MatchPartialName(partial)
      if matches and  #matches > 0 then
	 -- temporary until list is added
	 wndControl:SetText(matches[1])
	 wndControl:SetSel(partial:len(), -1)
      end
   end
end

function MagicMail:OnSlashCommand()
   if self.pendingMails or self.busyTimer then
      self:FinishMailboxProcess()
   else
      self:ProcessMailbox()
   end
end

function MagicMail:ProcessMailbox()
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
   self:Unhook(self.mailAddon, "OnMailResult")
   self:RawHook(self.mailAddon, "OnMailResult")
   self:ProcessNextBatch()
end

function MagicMail:ProcessNextBatch()
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
   if endIdx > startIdx + 20 then
      endIdx = startIdx + 20
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
	    if count >= 10 then
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
	 self.timer = ApolloTimer.Create(0.2, true, "ProcessNextBatch", self)
      end
   else
      self:FinishMailboxProcess()
   end
end


function MagicMail:FinishMailboxProcess(busy)
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

function MagicMail:RestoreResultHandler()
   self:Unhook(self.mailAddon, "OnMailResult")
   self.resultTimer = nil
end

function MagicMail:StopTimers()
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
function MagicMail:MatchPartialName(partial)
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
   if matches then
      local sorted = {q}
      for v in pairs(matches) do
	 sorted[#sorted+1] = v
      end
      sort(sorted)
      return sorted
   end
end

function MagicMail:FindMoreMatchesInTable(partial, tbl, matches, numFound)
   local realm, faction, name
   if not tbl then return
	 true, numFound
   end
   for k,v in pairs(tbl) do
      realm = v.realm or v.strRealmName
      faction = v.faction or v.nFactionId
      name = v.name or v.strCharacterName
      if (name ~= self.character)
	 and (not realm or realm == self.realm)
	 and (not faction or faction == self.faction)
         and (strfind(strupper(name), partial) == 1)
	 and not matches[name]
	 and (v.bIgnore == nil or v.bIgnore == false)
      then
	    matches[name] = true
	    numFound = numFound +1
      end
      if numFound >= 10 then
	 return false, numFound
      end
   end
   return true, numFound
end

function MagicMail:GuildId(guildCurr)
   return guildCurr:GetType()..":"..guildCurr:GetName()
end


function MagicMail:OnGuildMemberChange( guildCurr )
   if guildCurr and guildCurr:GetType() == GuildLib.GuildType_Guild then
      if self.guildRoster then
	 self.guildRoster[self:GuildId(guildCurr)] = nil
      end
      guildCurr:RequestMembers()
   end
end

-- Update roster for a guild. We only care about the name since guilds are realm specific
function MagicMail:OnGuildRoster(guildCurr, roster)
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
