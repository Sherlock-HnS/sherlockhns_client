-- Minimal engine boundary for geometry tests. The production UI functions are loaded unchanged.
SherlockHNS = {}
utf8 = {len = function(text) return #text end}
local screenW, screenH = 1920, 1080
function ScrW() return screenW end
function ScrH() return screenH end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
color_white = Color(255,255,255)
math.Round = function(n) return math.floor(n+0.5) end
table.Copy = function(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and table.Copy(v) or v end return out end
surface = {CreateFont=function() end, SetFont=function() end, GetTextSize=function(t) return #t*8,16 end}
local callbacks={}
hook={Add=function(event,name,fn) callbacks[event]=fn end}
derma={GetSkinTable=function() return {Default={Colours={Label={},Button={},Tab={Active={},Inactive={}}}}} end,DefineSkin=function() end}
vgui={Create=function() error('Unexpected panel construction in geometry test') end}
NODOCK,LEFT,TOP=0,2,1
function IsValid(p) return p and not p.removed end
local function panel(w,h)
 local p={w=w,h=h,children={}}
 function p:SetSize(w,h) self.w=w;self.h=h end
 function p:GetWide() return self.w end
 function p:GetTall() return self.h end
 function p:SetWide(w) self.w=w end
 function p:SetTall(h) self.h=h end
 function p:SetPos(x,y) self.x=x;self.y=y end
 function p:Center() self.x=(ScrW()-self.w)/2;self.y=(ScrH()-self.h)/2 end
 function p:SetZPos(z) self.z=z end
 function p:GetChildren() return self.children end
 function p:Dock(mode) self.dock=mode end
 function p:DockMargin(...) self.margin={...} end
 function p:IsVisible() return true end
 function p:InvalidateLayout() end
 return p
end
-- PRODUCTION_SOURCE
local UI=SherlockHNS.UI
local cases={{640,480},{800,600},{1024,768},{1280,720},{1920,1080},{2560,1080},{3440,1440},{3840,2160},{1080,1920}}
local checks=0
for _,viewport in ipairs(cases) do
 screenW,screenH=viewport[1],viewport[2]
 local w,h=UI.Bounds(1500,900)
 assert(w>0 and h>0 and w<screenW and h<screenH)
 local window=panel(1,1)
 UI.Window(window,1500,900,80)
 assert(window.x>=0 and window.y>=0 and window.x+w<=screenW and window.y+h<=screenH)
 screenW,screenH=math.floor(screenW*0.8),math.floor(screenH*0.8)
 callbacks.OnScreenSizeChanged()
 assert(window.x>=0 and window.y>=0 and window.x+window.w<=screenW and window.y+window.h<=screenH)
 local row=panel(screenW-64,1)
 for i=1,9 do row.children[i]=panel(i%2==0 and 170 or 110,28) end
 UI.Flow(row);row:PerformLayout(row.w)
 for i,c in ipairs(row.children) do
  assert(c.x>=0 and c.x+c.w<=row.w and c.y+c.h<=row.h)
  for j=1,i-1 do
   local other=row.children[j]
   assert(c.x>=other.x+other.w or other.x>=c.x+c.w or c.y>=other.y+other.h or other.y>=c.y+c.h)
  end
 end
 -- A compact row must restore the preferred widths when enlarged.
 local preferred=row.children[1].HNSFlowWidth
 row.w=60;row:PerformLayout(row.w);assert(row.children[1].w==60)
 row.w=1000;row:PerformLayout(row.w);assert(row.children[1].w==preferred)
 local parent,sidebar=panel(1000,600),panel(230,600)
 UI.Split(parent,sidebar,230,850)
 parent:PerformLayout(1000,600);assert(sidebar.dock==LEFT and sidebar.w==230)
 parent:PerformLayout(600,400);assert(sidebar.dock==TOP and sidebar.h<=140)
 parent:PerformLayout(1000,600);assert(sidebar.dock==LEFT and sidebar.w==230)
 assert(UI.HasWindow(70))
 assert(not UI.HasWindow(90))
 window.removed=true
 checks=checks+1
end
assert(UI.Fit('short','font',100)=='short')
assert(UI.Fit('long','font',0)=='')
print('PASS: UI bounds, resize, action collisions, width restoration and sidebar reflow across '..checks..' viewports')
