-----------------------------------------------------
-- Polygon Class
-----------------------------------------------------
local Polygon = {}

function Polygon:new ()
  local o = {}
  _G.setmetatable(o, self)
  self.__index = self
  return o
end

function Polygon:cw(v)
  local index = (v % #self) + 1
  return index
end

function Polygon:ccw(v)
  local index = ((v - 2) % #self) + 1
  return index
end

function Polygon:are_adjacent(u, v)
  return math.abs(v - u) % (#self - 2) == 1
end

function Polygon:gen_y_sort()
  local sorted = {inverse = {}}
  for i = 1, #self do table.insert(sorted, i) end
  table.sort(sorted, function(u, v)
      u = self[u]
      v = self[v]
      return u.y < v.y or (u.y == v.y and u.x < v.x)
    end)
  for i = 1, #sorted do sorted.inverse[sorted[i]] = i end
  self._sorted = sorted
end

function Polygon:sorted(i)
  if not self._sorted then self:gen_y_sort() end
  return self._sorted[i]
end

function Polygon:check_orientation()
  local b = self[1]
  local b_index = 1
  for i, v in ipairs(self) do
    if v.y < b.y then
      b = v
      b_index = i
    end
  end
  local a = self[self:cw(b_index)]
  local c = self[self:ccw(b_index)]
  local abc_det = (b.x*c.y+a.x*b.y+c.x*a.y) - (b.x*a.y+c.x*b.y+a.x*c.y)
  if abc_det < 0 then
    local size = #self
    for i=1,math.floor(size / 2) do
      local temp = self[i]
      self[i] = self[size + 1 - i]
      self[size + 1 - i] = temp
    end
  end
end

return Polygon