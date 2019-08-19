require "LibStub"
require "LibTextDict"

local dict1 = LibStub("LibTextDict")("addon1") -- LibTextDict#Dictionary
local dict2 = LibStub("LibTextDict")("addon2") -- LibTextDict#Dictionary
dict1:SetText("k","v1")
dict2:SetText("k","v2")

print ('v1: '..dict1:GetText("k"))
print ('v2: '..dict2:GetText("k"))

return nil