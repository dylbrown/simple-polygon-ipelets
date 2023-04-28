-----------------------------------------------------
-- Polygon Class
-----------------------------------------------------


local Stack = _G.require("util.stack")
local Polygon = {}
local TWO_PI = 2 * math.pi

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

function Polygon:left_turn_test(a, b, c)
a = self[a]
b = self[b]
c = self[c]
return (b.x*c.y+a.x*b.y+c.x*a.y) - (b.x*a.y+c.x*b.y+a.x*c.y) < 0
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
  local a = self:cw(b_index)
  local c = self:ccw(b_index)
  if self:left_turn_test(a, b_index, c) then
    local size = #self
    for i=1,math.floor(size / 2) do
      local temp = self[i]
      self[i] = self[size + 1 - i]
      self[size + 1 - i] = temp
    end
    return true
  end
  return false
end

function Polygon:compute_angle(src, dest, base_angle, base_vtx)
  local dest_vtx = dest
  local vtx_vtx = false
  if type(dest) == 'number' then
    dest_vtx = self[dest]
    vtx_vtx = true
  end
  local angle = math.atan(dest_vtx.y - self[src].y, dest_vtx.x - self[src].x) % TWO_PI
  if base_angle and base_vtx then
    angle = ((angle % TWO_PI) + TWO_PI - base_angle) % TWO_PI
    if vtx_vtx and dest == base_vtx then angle = 0 end
  end
  return angle
end

function Polygon:locate_point(p)
  if not self.triangles then self:triangulate() end
  local function in_side(a, b, third)
    local line = ipe.LineThrough(self[a], self[b])
    local in_side = line:side(self[third])
    local p_side = line:side(p)
    return p_side == 0 or p_side == in_side
  end
  for _, t in pairs(self.triangles) do
    if in_side(t[1],t[2],t[3]) and in_side(t[2],t[3],t[1]) and in_side(t[3],t[1],t[2]) then
      return t
    end
  end
end

-----------------------------------------------------
-- Triangulation
-----------------------------------------------------

local function make_subpolygon(new_edges, visit, vertices, start, first)
  local p = {}
  table.insert(p, start)
  local prev = start
  local curr = first
  while curr ~= start do
    table.insert(p, curr)
    if new_edges[curr] then
      for i, w in ipairs(new_edges[curr]) do
        if w == prev then
          local next = new_edges[curr][i + 1] or new_edges[curr][#new_edges[curr]]
          visit(curr, next)
          prev = curr
          curr = next
          break
        end
      end
    else
      visit(curr, vertices:cw(curr))
      prev = curr
      curr = vertices:cw(curr)
    end
  end

  local min = 1
  for i, v in ipairs(p) do
    if vertices[v].y < vertices[p[min]].y then
      min = i
    end
  end

  -- Ensure first vertex is bottom vertex
  local q = {}
  for i = min,#p do
    table.insert(q, p[i])
  end
  for i = 1,min-1 do
    table.insert(q, p[i])
  end

  return q
end

function Polygon:triangulate()
  local trapezoids = self:trapezoidalize()

  -- Work out all the cross edges
  local edges_lookup = {}
  local edges_tracker = {}
  local connect = function(u, v)
    edges_tracker[u] = edges_tracker[u] or {}
    edges_tracker[u][self:cw(u)] = true
    edges_tracker[u][self:ccw(u)] = true
    if (edges_tracker[u] and edges_tracker[u][v]) or (edges_tracker[v] and edges_tracker[v][u]) then
      return
    end
    edges_tracker[u][v] = true
    edges_lookup[u] = edges_lookup[u] or {self:ccw(u), self:cw(u)}
    table.insert(edges_lookup[u], v)
    edges_lookup[v] = edges_lookup[v] or {self:ccw(v), self:cw(v)}
    table.insert(edges_lookup[v], u)
  end
  for _, t in ipairs(trapezoids) do
    if not self:are_adjacent(t.bottom, t.top) then
      connect(t.bottom, t.top)
    end
  end

  -- Sort cross edge lists by angle
  for v, neighbours in pairs(edges_lookup) do
    local base = self:ccw(v)
    local base_angle  = self:compute_angle(v, base)
    table.sort(neighbours, function (a, b)
        return self:compute_angle(v, a, base_angle, base) < self:compute_angle(v, b, base_angle, base)
      end)
  end

  -- Go through each outside edge and compute its subpolygon
  -- visited[i] = true means we've visited the edge (i, i+1)
  local subpolygons = {}
  local visited_out = {}
  local visit = function(u, v)
    if v == self:cw(u) then
      visited_out[u] = true
    end
  end
  for v = 1, #self do
    if not visited_out[v] then
      visited_out[v] = true
      local p = make_subpolygon(edges_lookup, visit, self, v, self:cw(v))
      table.insert(subpolygons, p)
    end
  end

  -- TODO: Go through subpolygons, triangulate and add their edges to edges_lookup
  for _, p in ipairs(subpolygons) do
    if #p > 3 then
      local s = Stack:new()
      if self[p[2]].y < self[p[#p]].y then
        s:push(p[1], p[2])
        for i = 3,#p do 
          local c = p[i]
          while s:size() >= 2 do
            local b, a = s:top(2)
            if self:left_turn_test(a, b, c) then
              connect(a, c)
              s:pop()
            else
              break
            end
          end
          s:push(c)
        end
      else
        s:push(p[1], p[#p])
        for i = #p-1,2,-1 do 
          local c = p[i]
          while s:size() >= 2 do
            local b, a = s:top(2)
            if not self:left_turn_test(a, b, c) then
              connect(a, c)
              s:pop()
            else
              break
            end
          end
          s:push(c)
        end
      end
    end
  end
  
  -- Sort cross edge lists by angle again
  for v, neighbours in pairs(edges_lookup) do
    local base = self:ccw(v)
    local base_angle  = self:compute_angle(v, base)
    table.sort(neighbours, function (a, b)
        return self:compute_angle(v, a, base_angle, base) < self:compute_angle(v, b, base_angle, base)
      end)
  end
  local triangle_visited = {}
  self.triangles = {}
  local function visited(a, b)
    return triangle_visited[a] and triangle_visited[a][b]
  end
  visit = function(a, b)
    if a and b then
      triangle_visited[a] = triangle_visited[a] or {}
      triangle_visited[a][b] = true
    end
  end
  for u, neighbours in pairs(edges_lookup) do
    for _, v in ipairs(neighbours) do
      if not visited(u, v) then
        table.insert(self.triangles, make_subpolygon(edges_lookup, visit, self, u, v))
      end
    end
  end

  return edges_lookup, subpolygons
end

-----------------------------------------------------
-- Trapezoidalization
-----------------------------------------------------

local Trapezoid = {bottom = 0, bottom_far = {}, top = nil, top_far = {}}

function Trapezoid:new (bottom, far_edges)
  local o = {}
  _G.setmetatable(o, self)
  self.__index = self
  o.bottom = bottom
  o.bottom_far = far_edges
  return o
end

local function add_trapezoid(list, bottom, ...)
  local t = Trapezoid:new(bottom, {...})
  list.by_bottom[bottom] = t
  for _, edge in ipairs({...}) do
    list.by_edge[edge] = t
  end
  table.insert(list, t)
end

local function close_trapezoid(trapezoid, top, ...)
  trapezoid.top = top
  trapezoid.top_far = {...}
end

-- Returns if inside, and the index of the first edge not strictly to the left of the point
-- If the point is on the edge, it describes the region to the left
-- Linear time, could totally be improved to logarithmic with binary search on a tree
local function is_inside(edges, v)
  if false then -- Debug tool
    _G.ipe_warn(v.x.. ", "..v.y)
  end
  for index, edge in ipairs(edges) do
    p, q = edge:endpoints()
    if false then -- Debug tool
      _G.ipe_warn("edge: ", p.x..","..p.y.." - "..q.x..","..q.y)
    end
    if v == p or v == q then
      return index % 2 == 0, index
    end
    local diff = v - edge:line():project(v)
    if diff.x <= 0 then
      return index % 2 == 0, index
    end
  end
  return false, #edges + 1
end

function Polygon:trapezoidalize(model)
  local edges = {}
  local trapezoids = {by_bottom = {}, by_top = {}, by_edge = {}}
  for i = 1, #self do
    local v = self[self:sorted(i)]
    local u = self[self:ccw(self:sorted(i))]
    local w = self[self:cw(self:sorted(i))]
    local inside, next_edge_i = is_inside(edges, v)
    local left_edge = edges[next_edge_i-1]
    local right_edge = edges[next_edge_i] -- Because of tie breaking, sometimes this is the intersecting edge
    local right_right_edge = edges[next_edge_i+1]
    local right_right_right_edge = edges[next_edge_i+2]
    if v.y <= u.y and v.y < w.y then -- "V" case
      if inside then -- hollow "V"
        table.insert(edges, next_edge_i, ipe.Segment(v, w))
        table.insert(edges, next_edge_i, ipe.Segment(v, u))
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], self:sorted(i), right_edge, left_edge)
        add_trapezoid(trapezoids, self:sorted(i), left_edge, edges[next_edge_i])
        add_trapezoid(trapezoids, self:sorted(i), right_edge, edges[next_edge_i+1])
      else -- filled "V"
        table.insert(edges, next_edge_i, ipe.Segment(v, u))
        table.insert(edges, next_edge_i, ipe.Segment(v, w))
        add_trapezoid(trapezoids, self:sorted(i), edges[next_edge_i], edges[next_edge_i+1])
      end
    elseif v.y >= u.y and v.y > w.y then -- "^" Case
      table.remove(edges, next_edge_i)
      table.remove(edges, next_edge_i)
      if inside then -- hollow "^"
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], self:sorted(i), left_edge)
        close_trapezoid(trapezoids.by_edge[right_right_edge] or trapezoids.by_edge[right_right_right_edge], self:sorted(i), right_right_right_edge)
        add_trapezoid(trapezoids, self:sorted(i), left_edge, right_right_right_edge)
      else -- filled "^"
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[right_right_edge], self:sorted(i))
      end
    else -- "<" or ">" case
      local new_edge = nil
      if v.y < u.y then
        new_edge = ipe.Segment(v, u)
      else
        new_edge = ipe.Segment(v, w)
      end
      if inside then -- Fill is to the left
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], self:sorted(i), left_edge)
        add_trapezoid(trapezoids, self:sorted(i), left_edge, new_edge)
      else -- Fill is to the right
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[right_right_edge], self:sorted(i), right_right_edge)
        add_trapezoid(trapezoids, self:sorted(i), right_right_edge, new_edge)
      end
      -- This is us add/removing at the same time, because the edge should have the same index
      edges[next_edge_i] = new_edge
    end
    if false then -- logging
      for index, edge in ipairs(edges) do
        p, q = edge:endpoints()
        _G.ipe_warn(index, p.x..","..p.y.." - "..q.x..","..q.y)
      end
    end
  end
  return trapezoids
end

return Polygon