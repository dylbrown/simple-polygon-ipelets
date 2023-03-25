-- Stack Table
-- Source: http://lua-users.org/wiki/SimpleStack
-- Uses a table as stack, use <table>:push(value) and <table>:pop()
-- Lua 5.1 compatible

local Stack = {}

-- Create a Table with stack functions
function Stack:new()
    local o = {}
    _G.setmetatable(o, self)
    self.__index = self
    o._et = {}
    return o
end

function Stack:push(...)
    if ... then
        local targs = {...}
        -- add values
        for _,v in ipairs(targs) do
            table.insert(self._et, v)
        end
    end
end

function Stack:pop(num)
    -- get num values from stack
    local num = num or 1

    -- return table
    local entries = {}

    -- get values into entries
    for i = 1, num do
        -- get last entry
        if #self._et ~= 0 then
            table.insert(entries, self._et[#self._et])
            -- remove last value
            table.remove(self._et)
        else
            break
        end
    end
    -- return unpacked entries
    return table.unpack(entries)
end

function Stack:top(num)
    -- get num values from stack
    local num = num or 1

    -- return table
    local entries = {}

    -- get values into entries
    for i = 1, num do
        -- get ith last entry
        if #self._et ~= 0 then
            table.insert(entries, self._et[#self._et + 1 - i])
        else
            break
        end
    end
    -- return unpacked entries
    return table.unpack(entries)
end

-- get entries
function Stack:size()
    return #self._et
end

-- list values
function Stack:list()
    for i,v in pairs(self._et) do
    print(i, v)
    end
end

return Stack