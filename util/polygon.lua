-----------------------------------------------------
-- Polygon Class
-----------------------------------------------------
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

-----------------------------------------------------
-- Triangulation
-----------------------------------------------------

local function make_subpolygon(model, new_edges, visited_out, vertices, start)
  local p = {}
  table.insert(p, start)
  local prev = start
  local curr = vertices:cw(start)
  while curr ~= start do
    table.insert(p, curr)
    if new_edges[curr] then
      for i, w in ipairs(new_edges[curr]) do
        if w == prev then
          local next = new_edges[curr][i + 1]
          if next == vertices:cw(curr) then
            visited_out[curr] = true
          end
          prev = curr
          curr = next
          break
        end
      end
    else
      visited_out[curr] = true
      prev = curr
      curr = vertices:cw(curr)
    end
  end
  return p
end

function Polygon:triangulate(model)
  local trapezoids = self:trapezoidalize(model)

  -- Work out all the cross edges
  local new_edges = {}
  for _, t in ipairs(trapezoids) do
    if not self:are_adjacent(t.bottom, t.top) then
      new_edges[t.bottom] = new_edges[t.bottom] or {self:ccw(t.bottom), self:cw(t.bottom)}
      table.insert(new_edges[t.bottom], t.top)
      new_edges[t.top] = new_edges[t.top] or {self:ccw(t.top), self:cw(t.top)}
      table.insert(new_edges[t.top], t.bottom)
    end
  end

  -- Sort cross edge lists by angle
  local compute_angle = function(src, dest, base_angle, base_vtx)
    local angle = math.atan(self[dest].y - self[src].y, self[dest].x - self[src].x) % TWO_PI
    if base_angle and base_vtx then
      angle = ((angle % TWO_PI) + TWO_PI - base_angle) % TWO_PI
      if dest == base_vtx then angle = 0 end
    end
    return angle
  end
  for v, neighbours in pairs(new_edges) do
    local base = self:ccw(v)
    local base_angle  = compute_angle(v, base)
    table.sort(neighbours, function (a, b)
        return compute_angle(v, a, base_angle, base) < compute_angle(v, b, base_angle, base)
      end)
  end

  -- Go through each outside edge and compute its subpolygon
  -- visited[i] = true means we've visited the edge (i, i+1)
  local subpolygons = {}
  local visited_out = {}
  for v = 1, #self do
    if not visited_out[v] then
      visited_out[v] = true
      local p = make_subpolygon(model, new_edges, visited_out, self, v)
      table.insert(subpolygons, p)
    end
  end
  return subpolygons
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
local function is_inside(edges, v, model)
  if model then -- Debug tool - pass in model to get all these warnings
    model:warning(v.x.. ", "..v.y)
  end
  for index, edge in ipairs(edges) do
    p, q = edge:endpoints()
    if model then -- Debug tool - pass in model to get all these warnings
      model:warning("edge: ", p.x..","..p.y.." - "..q.x..","..q.y)
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
    local inside, next_edge_i = is_inside(edges, v, false and model)
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
        model:warning(index, p.x..","..p.y.." - "..q.x..","..q.y)
      end
    end
  end
  return trapezoids
end

return Polygon