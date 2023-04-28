-----------------------------------------------------
-- Shortest Path Tree
-----------------------------------------------------
local Stack = _G.require("util.stack")
local VisGraph = _G.require("util.vis-graph")
local SPT = {}

function SPT:new(vertices, point, edges)
    local o = {vertices=vertices, point=point, boundary=edges, vis=VisGraph:new(vertices, edges)}
    _G.setmetatable(o, self)
    self.__index = self
    return o
end

function SPT:generate()
    self.vis:generate()
    local graph = {}
    local dist = {}
    local stack = Stack:new()
    if type(self.point) == 'number' then
        dist[self.point] = 0
        stack:push(self.point)
    else -- centered point
        for j = 1, #self.vertices do
            local j_vtx = self.vertices[j]
            local line = ipe.Segment(self.point, j_vtx)
            local can_see = true
            for _, s in ipairs(self.boundary) do
                p, q = s:endpoints()
                if s:intersects(line) and j_vtx ~= p and j_vtx ~= q then
                    can_see = false
                    break
                end
            end

            if can_see then
                graph[j] = 0
                dist[j] = (j_vtx - self.point):len()
                stack:push(j)
            end
        end
    end

    while stack:size() > 0 do
        local u = stack:pop()
        for v, _ in pairs(self.vis[u]) do
            local dist_through_u = dist[u] + (self.vertices[v]-self.vertices[u]):len()
            if (not dist[v]) or dist_through_u < dist[v] then
                dist[v] = dist_through_u
                graph[v] = u
                stack:push(v)
            end
        end
    end

    self.graph = graph
    self.dist = dist
end

return SPT