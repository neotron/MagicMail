


local mod = {}
local GeminiGUI = Apollo.GetPackage("Gemini:GUI-1.0").tPackage

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
   Apollo.RegisterEventHandler("MailBoxActivate", "OnMailboxOpened", self)
   Apollo.RegisterEventHandler("MailBoxDeactivate", "OnMailboxClosed", self)
   Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
end
 
function mod:OnWindowManagementReady()
   -- NOOP right now 
   self.mailAddon = Apollo.GetAddon("Mail")
   local mailform = self.mailAddon.wndMain:FindChild("MailForm")
   mod.button = mailform:FindChild("TakeAllBtn") or GeminiGUI:Create(self.guiDefinition):GetInstance(self, mailform)
   mod.button:Enable(false)
end


function mod:OnMailboxOpened()
   mod.atMailbox = true
   mod.button:Enable(true)
end

function mod:OnMailboxClosed()
   mod.atMailbox = false
   mod.button:Enable(false)
end

function mod:OnSlashCommand()
   if mod.atMailbox then 
      if mod.pendingMails then
	 mod:FinishMailboxProcess()
      else
	 mod:ProcessMailbox()
      end
   end
end

function mod:ProcessMailbox()
   local pendingMails = MailSystemLib.GetInbox()
   if not #pendingMails then
      return
   end
   if self.button then self.button:SetText("Cancel ("..#pendingMails..")") end
   self.pendingMails = pendingMails
   self.mailsToDelete = {}
   self.currentMailIndex = 1
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
   local numProcessed = 0
   local endIdx = 1
   for i=startIdx,#mails do
      endIdx = i
      mail = self.pendingMails[i]
      msgInfo = mail:GetMessageInfo()
      sender = msgInfo.strSenderName
      subject = msgInfo.strSubject
      hasMoney = not msgInfo.monGift:IsZero()
      hasAttachments = #msgInfo.arAttachments > 0
      local processed = false
      if sender == "Phineas T. Rotostar" then
	 -- Auction house
	 if hasAttachments then
	    mail:TakeAllAttachments()
	    processed = true
	 end
	 if hasMoney then
	    mail:TakeMoney()
	    processed = true
	 end
	 self.mailsToDelete[mail:GetIdStr()] = mail;
      elseif subject == "Here's your stuff!" then
	 if hasAttachments then
	    mail:TakeAllAttachments()
	    processed = true
	 end
	 self.mailsToDelete[mail:GetIdStr()] = mail;
      elseif hasAttachments then
	 processed = true
	 mail:TakeAllAttachments()
      elseif hasMoney then
	 processed = true
	 mail:TakeMoney();
      end
      if processed then
	 -- Delay execution 
	 break 
      end
   end

   if endIdx < #mails then
      self.currentMailIndex = endIdx + 1
      if self.button then self.button:SetText("Cancel ("..(#mails-self.currentMailIndex)..")") end
      if not self.timer then
	 self.timer = ApolloTimer.Create(0.4, true, "ProcessNextBatch", self)
      end
   else 
      mod:FinishMailboxProcess()
   end
end

function mod:FinishMailboxProcess()
   if self.timer then
      self.timer:Stop()
      self.timer = nil
   end
   if self.mailsToDelete then
      local mailsToDelete = {}
      for id,mail in pairs(self.mailsToDelete) do
	 mailsToDelete[#mailsToDelete+1] = mail
      end
      if #mailsToDelete > 0 then
	 Print("Deleting "..#mailsToDelete.." messages.");
	 MailSystemLib.DeleteMultipleMessages(mailsToDelete)
      end
   end
   self.currentMailIndex = nil
   self.pendingMails = nil
   self.mailsToDelete = nil
   if self.button then self.button:SetText("Take All") end
end


-- creating the instance.

local MagicMailInstance = mod:new()
MagicMailInstance:Init()
