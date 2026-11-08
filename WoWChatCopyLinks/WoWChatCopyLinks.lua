local addon = CreateFrame("Frame", "WoWChatCopyLinksEventFrame")
local DB, history = nil, {}
local MAX_HISTORY = 100
local nextID, byID = 0, {}
local channels = {
 CHAT_MSG_SAY=true, CHAT_MSG_RAID=true, CHAT_MSG_RAID_LEADER=true,
 CHAT_MSG_BATTLEGROUND=true, CHAT_MSG_BATTLEGROUND_LEADER=true,
 CHAT_MSG_CHANNEL=true,
}
local function Clean(s)
 s = tostring(s or "")
 s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
 s = s:gsub("|H.-|h(.-)|h", "%1")
 return s
end
local function ExtractLinks(s)
 local result, seen = {}, {}
 local function add(v)
  v = v:gsub("[%.,;!%?%)%]%}]+$", "")
  if v ~= "" and not seen[v] then seen[v]=true; result[#result+1]=v end
 end
 for v in s:gmatch("https?://[^%s<>\"']+") do add(v) end
 for v in s:gmatch("www%.[%w%-%.]+[^%s<>\"']*") do add(v) end
 for v in s:gmatch("[%w%-_]+%.[%a][%a][%a]?[%a]?[^%s<>\"']*") do
  if v:match("^[%w%-_]+%.[%a]+") then add(v) end
 end
 return result
end
local ui = CreateFrame("Frame", "WoWChatCopyLinksWindow", UIParent)
ui:SetWidth(560); ui:SetHeight(440); ui:SetPoint("CENTER"); ui:SetFrameStrata("DIALOG")
ui:SetMovable(true); ui:EnableMouse(true); ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
ui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
ui:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}})
ui:Hide()
local title = ui:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
title:SetPoint("TOP",0,-18); title:SetText("WoW Chat Copy & Links")
local close = CreateFrame("Button",nil,ui,"UIPanelCloseButton")
close:SetPoint("TOPRIGHT",-5,-5)
local label = ui:CreateFontString(nil,"OVERLAY","GameFontNormal")
label:SetPoint("TOPLEFT",25,-52); label:SetText("Recent messages (click to select)")
local scroll = CreateFrame("ScrollFrame","WoWChatCopyLinksScroll",ui,"FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT",22,-75); scroll:SetWidth(494); scroll:SetHeight(215)
local rows={}
local function ShowCopy(text)
 ui:Show()
 ui.edit:SetText(Clean(text)); ui.edit:SetFocus(); ui.edit:HighlightText()
end
local function UpdateRows()
 FauxScrollFrame_Update(scroll,#history,10,21)
 local offset=FauxScrollFrame_GetOffset(scroll)
 for i=1,10 do
  local row=rows[i]; local entry=history[i+offset]
  if entry then
   row.entry=entry
   row.text:SetText(string.format("|cffaaaaaa[%s]|r |cff55ccff%s|r: %s",entry.channel,entry.sender,entry.message:sub(1,70)))
   row:Show()
  else row.entry=nil; row:Hide() end
 end
end
for i=1,10 do
 local b=CreateFrame("Button",nil,ui)
 b:SetHeight(21); b:SetWidth(485); b:SetPoint("TOPLEFT",28,-77-(i-1)*21)
 b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 b.text:SetAllPoints(); b.text:SetJustifyH("LEFT")
 b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
 b:SetScript("OnClick",function(self)
  if self.entry then
   ShowCopy(self.entry.message)
   ui.selected=self.entry
   ui.links:SetText(table.concat(ExtractLinks(self.entry.message),"\n"))
  end
 end)
 rows[i]=b
end
scroll:SetScript("OnVerticalScroll",function(self,offset) FauxScrollFrame_OnVerticalScroll(self,offset,21,UpdateRows) end)
local copyLabel=ui:CreateFontString(nil,"OVERLAY","GameFontNormal")
copyLabel:SetPoint("TOPLEFT",25,-303); copyLabel:SetText("Selected text — press Ctrl+C")
local edit=CreateFrame("EditBox",nil,ui)
edit:SetPoint("TOPLEFT",27,-323); edit:SetWidth(505); edit:SetHeight(24)
edit:SetFontObject("ChatFontNormal"); edit:SetAutoFocus(false)
edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
edit:SetScript("OnEditFocusGained",function(self) self:HighlightText() end)
ui.edit=edit
local links=CreateFrame("EditBox",nil,ui)
links:SetPoint("TOPLEFT",27,-364); links:SetWidth(505); links:SetHeight(46)
links:SetMultiLine(true); links:SetFontObject("ChatFontNormal"); links:SetAutoFocus(false)
links:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
links:SetScript("OnEditFocusGained",function(self) self:HighlightText() end)
ui.links=links
local linksLabel=ui:CreateFontString(nil,"OVERLAY","GameFontNormal")
linksLabel:SetPoint("TOPLEFT",25,-348); linksLabel:SetText("Detected links (select and Ctrl+C)")
-- Per-character-visible chat controls; settings persist in SavedVariables.
local settingsTitle=ui:CreateFontString(nil,"OVERLAY","GameFontNormal")
settingsTitle:SetPoint("TOPLEFT",25,-415)
settingsTitle:SetText("Chat buttons:")
local function MakeToggle(label,x,key)
 local cb=CreateFrame("CheckButton",nil,ui,"UICheckButtonTemplate")
 cb:SetWidth(22); cb:SetHeight(22); cb:SetPoint("TOPLEFT",x,-407)
 local txt=ui:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 txt:SetPoint("LEFT",cb,"RIGHT",1,0); txt:SetText(label)
 cb:SetScript("OnClick",function(self)
  if DB then DB[key]=(self:GetChecked()==1) end
 end)
 cb:SetScript("OnShow",function(self)
  self:SetChecked(not DB or DB[key]~=false)
 end)
 return cb
end
local copyToggle=MakeToggle("[C] Copy",130,"showCopy")
local linkToggle=MakeToggle("[L] Links",260,"showLinks")
local function Push(event,msg,sender,...)
 if event=="CHAT_MSG_CHANNEL" then
  local channelName=select(2,...)
  local channelNumber=tonumber(tostring(channelName or ""):match("^(%d+)"))
  if not channelNumber or channelNumber<1 or channelNumber>7 then return end
 end
 local name=Clean(sender or "Unknown")
 local latest=history[1]
 if latest and latest.message==Clean(msg) and latest.sender==name and latest.channel==event:gsub("CHAT_MSG_","") and (GetTime()-(latest.stamp or 0))<0.2 then return end
 nextID=nextID+1
 local entry={id=nextID,channel=event:gsub("CHAT_MSG_",""),sender=name,message=Clean(msg),stamp=GetTime()}
 table.insert(history,1,entry)
 byID[nextID]=entry
 if #history>MAX_HISTORY then local old=table.remove(history); byID[old.id]=nil end
 if ui:IsShown() then UpdateRows() end
end
addon:SetScript("OnEvent",function(self,event,...)
 if event=="ADDON_LOADED" then
  local name=...
  if name~="WoWChatCopyLinks" then return end
  WoWChatCopyLinksDB=WoWChatCopyLinksDB or {}
  DB=WoWChatCopyLinksDB
  if DB.angle==nil then DB.angle=220 end
  if DB.radius==nil then DB.radius=80 end
  if DB.showCopy==nil then DB.showCopy=true end
  if DB.showLinks==nil then DB.showLinks=true end
  self:UnregisterEvent("ADDON_LOADED")
  self:RegisterEvent("PLAYER_LOGIN")
 elseif event=="PLAYER_LOGIN" then
  local button=CreateFrame("Button","WoWChatCopyLinksMinimapButton",Minimap)
  button:SetWidth(32); button:SetHeight(32); button:SetFrameStrata("MEDIUM")
  -- Round minimap button: icon cropped inside the circular minimap tracking border.
  local icon=button:CreateTexture(nil,"ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER",0,0)
  icon:SetTexCoord(.12,.88,.12,.88)
  local border=button:CreateTexture(nil,"OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(54); border:SetHeight(54); border:SetPoint("TOPLEFT",0,0)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:SetMovable(true); button:RegisterForDrag("LeftButton")
  local function Position()
   local a=math.rad(DB.angle or 220)
   button:ClearAllPoints(); button:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*(DB.radius or 80),math.sin(a)*(DB.radius or 80))
  end
  button:SetScript("OnDragStart",function(self) self.dragging=true end)
  button:SetScript("OnDragStop",function(self) self.dragging=false end)
  button:SetScript("OnUpdate",function(self)
   if not self.dragging then return end
   local x,y=GetCursorPosition(); local scale=Minimap:GetEffectiveScale(); x=x/scale; y=y/scale
   local cx,cy=Minimap:GetCenter(); DB.angle=math.deg(math.atan2(y-cy,x-cx)); Position()
  end)
  button:SetScript("OnClick",function() if ui:IsShown() then ui:Hide() else ui:Show(); UpdateRows() end end)
  button:SetScript("OnEnter",function(self)
   GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:AddLine("WoW Chat Copy & Links"); GameTooltip:AddLine("Click: open history | Drag: move icon",1,1,1); GameTooltip:Show()
  end)
  button:SetScript("OnLeave",function() GameTooltip:Hide() end)
  Position()
 else
  if channels[event] then Push(event,...) end
 end
end)
addon:RegisterEvent("ADDON_LOADED")
for event in pairs(channels) do addon:RegisterEvent(event) end
SLASH_WOWCHATCOPYLINKS1="/chatcopy"
SLASH_WOWCHATCOPYLINKS2="/ccl"
SlashCmdList.WOWCHATCOPYLINKS=function()
 if ui:IsShown() then ui:Hide() else ui:Show(); UpdateRows() end
end

-- Chat-line action links. ChatFrame_AddMessageEventFilter is available in the 3.3.5 client.
-- The link targets our own recent-history entries and never executes external URLs.
local function ChatCopyFilter(self,event,msg,sender,...)
 if type(msg)~="string" then return false end
 local id=nextID
 local entry=byID[id]
 -- Event filters are invoked after our event handler in the usual client dispatch,
 -- but do not assume order: capture a matching message if necessary.
 if not entry or entry.message~=Clean(msg) or entry.sender~=Clean(sender or "Unknown") then
  Push(event,msg,sender,...)
  id=nextID
  entry=byID[id]
 end
 if not entry then return false end
 local suffix=""
 if not DB or DB.showCopy~=false then
  suffix=" |cff66ccff|Hcclcopy:"..id.."|h[C]|h|r"
 end
 local links=ExtractLinks(Clean(msg))
 if #links>0 and (not DB or DB.showLinks~=false) then suffix=suffix.." |cff66ff99|Hccllink:"..id.."|h[L]|h|r" end
 return false,msg..suffix,sender,...
end
if ChatFrame_AddMessageEventFilter then
 for event in pairs(channels) do ChatFrame_AddMessageEventFilter(event,ChatCopyFilter) end
end
local oldSetItemRef=SetItemRef
SetItemRef=function(link,text,button,...)
 local action,id=tostring(link or ""):match("^(ccl%a+):(%d+)$")
 if action and id then
  local entry=byID[tonumber(id)]
  if entry then
   if action=="cclcopy" then
    ShowCopy(entry.message)
    ui.selected=entry
    ui.links:SetText(table.concat(ExtractLinks(entry.message),"\n"))
   elseif action=="ccllink" then
    local links=ExtractLinks(entry.message)
    ShowCopy(links[1] or "")
    ui.selected=entry
    ui.links:SetText(table.concat(links,"\n"))
   end
  end
  return
 end
 return oldSetItemRef(link,text,button,...)
end
