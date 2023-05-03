-----------------------------------------------------
-- Shortest Path Equivalency Map
-----------------------------------------------------
local SPT = _G.require("util.spt")
local SPEM = {}

function SPEM:new(vertices, edges)
    local o = {vertices=vertices, boundary=edges}
    _G.setmetatable(o, self)
    self.__index = self
    return o
end

function SPEM:generate()
    local seams = {endpoints = {}, opposites = {}}
    local duplicate_data = {}
    local function duplicate_check(v, opposite)
      if not duplicate_data[v] then
        duplicate_data[v] = { opposite }
        return true
      end
      for _, other in ipairs(duplicate_data[v]) do
        if (opposite - other):len() < .0001 then return false end
      end
      table.insert(duplicate_data[v], opposite)
      return true
    end
    for i = 1, #self.vertices do
      local spt = SPT:new(self.vertices, i, self.boundary)
      spt:generate()
  
      for v = 1, #self.vertices do
        local u = spt.graph[v]
        if u == nil then goto continue end
        local u_vtx = self.vertices[u]
        local line = ipe.LineThrough(u_vtx, self.vertices[v])
        local duv = (self.vertices[v] - u_vtx):len()
        local opposite = nil
        local min_distance = nil
        for _, s in ipairs(spt.boundary) do
          local x = s:intersects(line)
          if x then
            local du = (x-u_vtx):len()
            local dv = (x-self.vertices[v]):len()
            if duv < du and dv < du and (not min_distance or dv < min_distance) then
              local prev = self.vertices:ccw(v)
              local next = self.vertices:cw(v)
              local min_angle = self.vertices:compute_angle(v, prev)
              local max_angle = self.vertices:compute_angle(v, next, min_angle, prev)
              local angle = self.vertices:compute_angle(v, x, min_angle, u)
              if angle < max_angle then
                opposite = x
                min_distance = dv
              end
            end
          end
        end
        if opposite and duplicate_check(v, opposite) then
          table.insert(seams, ipe.Segment(self.vertices[v], opposite))
          table.insert(seams.endpoints, self.vertices[v])
          table.insert(seams.opposites, opposite)
        end
        ::continue::
      end
    end
    self.seams = seams
end

return SPEM