


local mod = {}
local GeminiGUI = Apollo.GetPackage("Gemini:GUI-1.0").tPackage
local MailAddonOnMailResult

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
		    mod:OnSlashCommand()
	       end },
   }
   Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
   Apollo.RegisterEventHandler("MailResult", "OnMailResult", self)
   
end

function mod:OnMailResult(result)
   if result == GameLib.CodeEnumGenericError.Mail_MailBoxOutOfRange  or
      result == GameLib.CodeEnumGenericError.Item_InventoryFull then
      -- Can still get cash
      Print("Too far away, fetching cash only.")
      mod.getCashOnly = true;
   elseif result == GameLib.CodeEnumGenericError.Mail_Busy then
      mod:FinishMailboxProcess(true)
   else
      MailAddonOnMailResult(result)
   end
end

function mod:OnWindowManagementReady()
   self.mailAddon = Apollo.GetAddon("Mail")
   MailAddonOnMailResult = self.mailAddon.OnMailResult
   local mailform = self.mailAddon.wndMain:FindChild("MailForm")
   mod.button = mailform:FindChild("TakeAllBtn") or GeminiGUI:Create(self.guiDefinition):GetInstance(self, mailform)
end

function mod:OnSlashCommand()
   if mod.pendingMails or self.busyTimer then
      mod:FinishMailboxProcess()
   else
      mod:ProcessMailbox()
   end
end

function mod:ProcessMailbox()
   mod:StopTimers()
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
   mod:ProcessNextBatch()
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
	    if mod.getCashOnly then
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
	 if hasAttachments and not mod.getCashOnly then
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
      mod:FinishMailboxProcess()
   end
end


function mod:FinishMailboxProcess(busy)
   mod:StopTimers()
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

-- creating the instance.

local MagicMailInstance = mod:new()
MagicMailInstance:Init()
