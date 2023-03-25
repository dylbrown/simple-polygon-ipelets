-----------------------------------------------------
-- Visibility Graph
-----------------------------------------------------
local VisGraph = {}

function VisGraph:new(vertices, edges)
    local o = {vertices=vertices, boundary=edges}
    _G.setmetatable(o, self)
    self.__index = self
    return o
end

function VisGraph:generate()
    local n = #self.vertices
    for i = 1, n do
        local i_vtx = self.vertices[i]
        local u = self.vertices:ccw(i)
        local v = self.vertices:cw(i)
        local min_angle = self.vertices:compute_angle(i, u)
        local max_angle = self.vertices:compute_angle(i, v, min_angle, u)
        for j = i+1, n do
            local j_vtx = self.vertices[j]
            local can_see = true
            local line = ipe.Segment(i_vtx, j_vtx)

            local angle = self.vertices:compute_angle(i, j, min_angle, u)
            if angle > max_angle then
                can_see = false
            end

            if can_see then
                for _, s in ipairs(self.boundary) do
                    if s:distance(i_vtx) < 1e-13 or
                            s:distance(j_vtx) < 1e-13 then
                        goto skip_edge
                    end
                    
                    if s:intersects(line) then
                        can_see = false
                        break
                    end

                    ::skip_edge::
                end
            end

            if can_see or self.vertices:are_adjacent(i, j) then
                self[i] = self[i] or {}
                self[j] = self[j] or {}
                self[i][j] = true
                self[j][i] = true
            end
        end
    end
end

return VisGraph