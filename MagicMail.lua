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

local MAX_RECENT_CHARS = 8

local buttonDefinition = { 
   WidgetType    = "PushButton",
   Text          = "Take All",
   Name = "MMTakeAllBtn",
   Base = "CRB_Basekit:kitBtn_Metal_LargeGreen",
   AnchorPoints = { 0, 1, 0, 1 },
   AnchorOffsets = {212,-78,324,-31},
   NormalTextColor = "UI_BtnTextGreenNormal",
   PressedTextColor = "UI_BtnTextGreenPressed",
   Events = {
      ButtonSignal = "OnSlashCommand"
   },
}
   
local completionDefinition = {
   Name          = "MMCompletionWindow",
   Picture       = true,
   Border        = true,
   NewWindowDepth = true, 
   Sizable       = false,
   AnchorOffsets  = { 95, 67, 405, 500 },
   Children = {
      {
	 Name = "NameContainer",
	 AnchorPoints = "FILL",
	 AnchorOffsets = { 3, 3, 3, 3 }, 
      },
   },
}

local nameButtonDefinition = {
   WidgetType     = "PushButton",
   Base           = "CRB_Basekit:kitBtn_Holo_DatachronOption",
   Text           = "",
   TextThemeColor = "ffffffff", 
   AnchorCenter = { 280, 30 }, 
   Events = {
      ButtonSignal = "OnNameSelected"
   }
}

function MagicMail:OnInitialize()
   self.db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self,  self:GetConfigDefaults())

   Apollo.RegisterSlashCommand("magmail", "OnSlashCommand", self)
   Apollo.RegisterEventHandler("WindowManagementAdd",   "OnWindowManagementAdd", self)
   Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
   Apollo.RegisterEventHandler("GuildRoster",           "OnGuildRoster", self)
   Apollo.RegisterEventHandler("GuildMemberChange",     "OnGuildMemberChange", self)
end

function MagicMail:OnEnable()
   for _,guild in ipairs(GuildLib.GetGuilds()) do
      guild:RequestMembers()
   end
   
   self:AddSelfAsAlt()
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
   self.button = mailform:FindChild("MMTakeAllBtn") or GeminiGUI:Create(buttonDefinition):GetInstance(self, mailform)
end

function MagicMail:OnWindowManagementAdd(tbl)
   if tbl and tbl.strName == Apollo.GetString("Mail_ComposeLabel") then
      self:PostHook(self.mailAddon.luaComposeMail, "OnInfoChanged")
      self:Hook(self.mailAddon.luaComposeMail, "OnEmailSent")
      self.composeRecipient = self.mailAddon.luaComposeMail.wndMain:FindChild("NameEntryText")
      self.composeRecipient:AddEventHandler("EditBoxTab", "MMOnEditBoxNext")
      self.composeRecipient:AddEventHandler("EditBoxReturn", "MMOnEditBoxNext")
      self.composeRecipient:AddEventHandler("EditBoxEscape", "MMOnEditBoxClear")
      local this = self
      self.mailAddon.luaComposeMail.MMOnEditBoxNext = function()
	 this:OnEditBoxNext()
      end
      self.mailAddon.luaComposeMail.MMOnEditBoxClear = function()
	 this:OnEditBoxClear()
      end
      local mailcompose = self.mailAddon.luaComposeMail.wndMain:FindChild("MessageEntryComplex")
      self.completionWindow = mailcompose:FindChild("MMCompletionWindow") or GeminiGUI:Create(completionDefinition):GetInstance(self, mailcompose)
      self.completionWindow:Show(false)
   end
end

function MagicMail:OnEditBoxNext()
   self:OnEditBoxClear()
end

function MagicMail:OnEditBoxClear()
   self.composeRecipient:SetStyleEx("WantTab", false)
   self.completionWindow:Show(false)
end


function MagicMail:OnInfoChanged(luaCaller, wndHandler, wndControl)
   if wndControl == self.composeRecipient then
      local partial = wndControl:GetText()
      local matches = self:MatchPartialName(partial)
      self.matchWindows = self.matchWindows or {}
      for _,btn in ipairs(self.matchWindows) do
	 btn:Destroy()
      end
      local parent = self.completionWindow:FindChild("NameContainer")
      if matches and  #matches > 0 then
	 -- temporary until list is added
	 wndControl:SetText(matches[1])
	 wndControl:SetSel(partial:len(), -1)
	 for i=2,#matches do
	    local btn =  GeminiGUI:Create(nameButtonDefinition):GetInstance(self, parent);
	    btn:SetText(matches[i])
	    self.matchWindows[#self.matchWindows+1] = btn
	 end
      end
      local hasMatches  = #self.matchWindows > 0
      if hasMatches then
	 parent:ArrangeChildrenVert()
      end
      self.completionWindow:Show(hasMatches);
      self.composeRecipient:SetStyleEx("WantTab", hasMatches)
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
   local mailsToDelete = self.mailsToDelete or {}
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
	    local count = #mailsToDelete + 1
	    mailsToDelete[#mailsToDelete+1] = mail
	    if count >= 10 then
	       MailSystemLib.DeleteMultipleMessages(mailsToDelete)
	       mailsToDelete = {}
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
   self.mailsToDelete = mailsToDelete
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
      self.busyTimeout = (self.busyTimeout or 2) + 1
      if self.busyTimeout > 6 then
	 self.busyTimeout = 6
      end
      self.busyTimerRemaining = self.busyTimeout-1
      self.button:SetText("Busy ("..self.busyTimeout..")")
      self.busyTimer = ApolloTimer.Create(1, true, "CountDownBusyTimer", self);
   else
      self.button:SetText("Take All")
      -- restore mail addon handler, after a short delay
      self.resultTimer = ApolloTimer.Create(0.5, false, "RestoreResultHandler", self)
      self.busyTimeout = nil
   end
end

function  MagicMail:CountDownBusyTimer()
   self.button:SetText("Busy ("..self.busyTimerRemaining..")")
   self.busyTimerRemaining = self.busyTimerRemaining - 1
   if self.busyTimerRemaining < 0 then
      self.busyTimer:Stop()
      self.busyTimer = nil
      self:ProcessMailbox()
      return
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

function MagicMail:OnNameSelected(ctr)
   self.composeRecipient:SetText(ctr:GetText());
   self.completionWindow:Show(false)
end

function MagicMail:MatchPartialName(partial)
   if strlen(partial or "") == 0 then
      return nil
   end
   local matches = {}
   partial = strupper(partial)
   local fetchMore
   fetchMore = self:FindMoreMatchesInTable(partial, self.db.realm.alts, matches)
   fetchMore = self:FindMoreMatchesInTable(partial, self.db.realm.recent, matches)

   if fetchMore then
      fetchMore = self:FindMoreMatchesInTable(partial, FriendshipLib.GetList(), matches);
   end
   if self.guildRoster then
      for _,roster in pairs(self.guildRoster) do
	 if fetchMore then
	    fetchMore = self:FindMoreMatchesInTable(partial, roster, matches);
	 end
      end
   end

   if fetchMore then
      fetchMore = self:FindMoreMatchesInTable(partial, HousingLib.GetNeighborList(), matches);
   end
   sort(matches)
   return matches
end

function MagicMail:FindMoreMatchesInTable(partial, tbl, matches)
   local realm, faction, name
   if not tbl then return
	 true
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
	    matches[#matches + 1] = name
      end
      if #matches >= 8 then
	 return false
      end
   end
   return true
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

function MagicMail:OnEmailSent(luaHandler, wndHandler, wndControl, bSuccess)
   if bSuccess then
      self:AddRecentRecipient(self.composeRecipient:GetText());
      self:Unhook(self.mailAddon.luaComposeMail, "OnEmailSent")
      self:Unhook(self.mailAddon.luaComposeMail, "OnInfoChanged")
   end
end

function MagicMail:AddRecentRecipient(name)
   local recents = self.db.realm.recents
   local oldestTimestamp 
   local oldestKey 
   for k,v in pairs(recents) do
      if v.name == self.character then
	 return
      end
      if oldestTimestamp == nil or v.t < oldestTimestamp then
	 oldestTimestamp = v.t
	 oldestKey = k
      end
   end
   local newChar = {
      name = name,
      faction = self.faction,
      t = os.time()
   }
   if #recents >= MAX_RECENT_CHARS then
      recents[oldestKey] = newChar
   else
      recents[#recents + 1] = newChar
   end
end

function MagicMail:AddSelfAsAlt()
   -- This is used to filter characters in mail recipients
   local charInfo = GameLib.GetAccountRealmCharacter()
   self.character = charInfo.strCharacter
   self.faction = GameLib.GetPlayerUnit():GetFaction()
   local alts = self.db.realm.alts
   for k,v in pairs(alts) do
      if v.name == self.character then
	 return
      end
   end
   alts[#alts+1] = { name = self.character, faction = self.faction }
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

function MagicMail:GetConfigDefaults() 
   return {
      realm = {
	 alts = {},
	 recents = {}
      }
   }
end
