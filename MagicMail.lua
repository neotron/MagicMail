


local mod = {}

function mod:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self 
   return o
end

function mod:Init()
   Apollo.RegisterAddon(self, false, "Configure", { "Mail" })
   Apollo.RegisterSlashCommand("magmail", "OnSlashCommand", self)
   Print("MagicMail initialized.")
end
 
function mod:OnLoad()
   -- NOOP right now
end

function mod:OnSlashCommand()
   Print("Hello, executing slash here.")
   mod:ProcessMailbox()
end

function mod:ProcessMailbox()
   mod:FinishMailboxProcess()
   local pendingMails = MailSystemLib.GetInbox()
   if not #pendingMails then
      Print("No mails to process.")
      return
   end
   Print("Master, you have "..#pendingMails.." mails waiting.")
   
   self.pendingMails = pendingMails
   self.mailsToDelete = {}
   self.currentMailIndex = 1
   mod:ProcessNextBatch()
end

function mod:ProcessNextBatch()
   local startIdx = self.currentMailIndex or 1
   local isLastBatch = false
   local mails = self.pendingMails

   local mail, sender, subject, hasMoney, hasAttachments, msgInfo
   local numProcessed = 0
   local endIdx
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
   
end


-- creating the instance.

local MagicMailInstance = mod:new()
MagicMailInstance:Init()
