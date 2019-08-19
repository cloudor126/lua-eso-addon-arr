require "LibStub"
require "LibTypeRegistry"

local reg1 = LibStub("LibTypeRegistry")("addon1") -- LibTypeRegistry#Registry
local reg2 = LibStub("LibTypeRegistry")("addon2") -- LibTypeRegistry#Registry

local p1 = {} -- #P1
p1.a = ''
local p2 = {} -- #P2
p2.b = ''

reg1('TestLibTypeRegistry#P1', p1)

return nil 