----------------------------------------------------------------------
-- triangulation ipelet
----------------------------------------------------------------------

label = "Simple Polygons"

about = [[
Various algorithms run on simple polygons
]]

-----------------------------------------------------
-- Polygon Class
-----------------------------------------------------
Polygon = {}

TWO_PI = 2 * math.pi

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

function make_vertices(model)local page = model:page()
  local prim = page:primarySelection()
  if not prim then model.ui:explain("no selection") return end

  local obj = page[prim]
  if obj:type() ~= "path" then model:warning('Primary selection is not a path') return end

  local shape = obj:shape()
  if (#shape ~= 1 or shape[1].type ~= "curve") then
    model:warning('Primary selection is not a single curve')
    return
  end

  local vertices = Polygon:new()

  local m = obj:matrix()
  table.insert(vertices, m * shape[1][1][1])
  for _, line in ipairs(shape[1]) do
    table.insert(vertices, m * line[2])
  end
  vertices:check_orientation()
  return vertices
end

-----------------------------------------------------
-- Triangulate Ipelet
-----------------------------------------------------

function triangulate_and_draw(model)
  local vertices = make_vertices(model)
  if vertices == nil then return end
  local monotones = triangulate(vertices, model)
  
  local monotone_paths = {}
  for _, monotone in ipairs(monotones) do
    local curve = {type="curve"; closed=true}
    for i = 1,#monotone-1 do
      table.insert(curve, {type="segment"; vertices[monotone[i]], vertices[monotone[i+1]]})
    end
    table.insert(monotone_paths, ipe.Path(model.attributes, {curve}))
  end
  model:creation("Create monotone subpolygons", ipe.Group(monotone_paths))
end

function make_subpolygon(model, new_edges, visited_out, vertices, start)
  local p = {}
  local curve = {type="curve"; closed=true}
  table.insert(p, start)
  local prev = start
  local curr = vertices:cw(start)
  while curr ~= start do
    table.insert(p, curr)
    table.insert(curve, {type="segment"; vertices[prev], vertices[curr]})
    if new_edges[curr] then
      for i, w in ipairs(new_edges[curr]) do
        if w == prev then
          local next = new_edges[curr][i + 1]
          if next == vertices:cw(curr) then
            visited_out[curr] = true
          end
          if not new_edges[curr][i+1] then
            model:warning("Failed on the last edge at "..i, vertices[prev].x..","..vertices[prev].y.."->"..vertices[curr].x..","..vertices[curr].y)
            for i, test in ipairs(new_edges[curr]) do  
              model:creation("boop", ipe.Path(model.attributes, {{type="curve"; closed=false;
              {type="segment"; vertices[curr], vertices[test]}
            }}))
              model:warning("Pair "..i, vertices[test].x..","..vertices[test].y)
            end
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
  p.path = ipe.Path(model.attributes, {curve})
  return p
end

-----------------------------------------------------
-- Trapezoidalize Ipelet
-----------------------------------------------------

function trapezoidalize_and_draw(model)
  local vertices = make_vertices(model)
  local trapezoids = trapezoidalize(vertices, model)
  local actual_trapezoids = {}
  for _, t in ipairs(trapezoids) do
    local path = ipe.Path(model.attributes, make_trapezoid_curve(vertices, t, model))
    table.insert(actual_trapezoids, path)
  end
  model:creation("Trapezoidalize", ipe.Group(actual_trapezoids))
end

function make_trapezoid_curve(vertices, t, model)
  local p = vertices[t.bottom]
  local q = vertices[t.top]
  local p_cross_1 = ipe.Line(p, ipe.Vector(1, 0)):intersects(t.bottom_far[1]:line())

  -- These three may or may not exist depending on the situation, hence the conditionals
  local p_cross_2 = #t.bottom_far > 1 and ipe.Line(p, ipe.Vector(1, 0)):intersects(t.bottom_far[2]:line())
  local q_cross_1 = #t.top_far > 0 and ipe.Line(q, ipe.Vector(1, 0)):intersects(t.top_far[1]:line())
  local q_cross_2 = #t.top_far > 1 and ipe.Line(q, ipe.Vector(1, 0)):intersects(t.top_far[2]:line())

  local curve = {type="curve"; closed=true}
  local p2_next_to_q = false
  if p_cross_1 ~= p then
    table.insert(curve, {type="segment"; p_cross_1, p})
    if p_cross_2 then
      table.insert(curve, {type="segment"; p, p_cross_2})
      p = p_cross_2
      local a, b = t.bottom_far[2]:endpoints()
      p2_next_to_q = a == q or b == q
    end
  end
  if q_cross_1 then
    if (vertices:are_adjacent(t.bottom, t.top)) or p2_next_to_q then
      table.insert(curve, {type="segment"; p, q})
      table.insert(curve, {type="segment"; q, q_cross_1})
    else
      if q_cross_2 then
        if t.bottom_far[1] == t.top_far[2] then
          table.insert(curve, {type="segment"; p, q_cross_1})
          table.insert(curve, {type="segment"; q_cross_1, q})
          table.insert(curve, {type="segment"; q, q_cross_2})
        else
          table.insert(curve, {type="segment"; p, q_cross_2})
          table.insert(curve, {type="segment"; q_cross_2, q})
          table.insert(curve, {type="segment"; q, q_cross_1})
        end
      else
        table.insert(curve, {type="segment"; p, q_cross_1})
        table.insert(curve, {type="segment"; q_cross_1, q})
      end
    end
  elseif p and q then
    table.insert(curve, {type="segment"; p, q})
  end
  if #curve == 0 then
    model:warning("Bad Drawing!", p.x..","..p.y.." - "..q.x..","..q.y)
  end
  return {curve}
end

-----------------------------------------------------
-- Triangulation Functionality
-----------------------------------------------------

function triangulate(vertices, model)
  local trapezoids = trapezoidalize(vertices, model)

  -- Work out all the cross edges
  local new_edges = {}
  for _, t in ipairs(trapezoids) do
    if not vertices:are_adjacent(t.bottom, t.top) then
      new_edges[t.bottom] = new_edges[t.bottom] or {vertices:ccw(t.bottom), vertices:cw(t.bottom)}
      table.insert(new_edges[t.bottom], t.top)
      new_edges[t.top] = new_edges[t.top] or {vertices:ccw(t.top), vertices:cw(t.top)}
      table.insert(new_edges[t.top], t.bottom)
    end
  end

  -- Sort cross edge lists by angle
  local compute_angle = function(src, dest, base_angle, base_vtx)
    local angle = math.atan(vertices[dest].y - vertices[src].y, vertices[dest].x - vertices[src].x) % TWO_PI
    if base_angle and base_vtx then
      angle = ((angle % TWO_PI) + TWO_PI - base_angle) % TWO_PI
      if dest == base_vtx then angle = 0 end
    end
    return angle
  end
  for v, neighbours in pairs(new_edges) do
    local base = vertices:ccw(v)
    local base_angle  = compute_angle(v, base)
    table.sort(neighbours, function (a, b)
        return compute_angle(v, a, base_angle, base) < compute_angle(v, b, base_angle, base)
      end)
  end

  -- Go through each outside edge and compute its subpolygon
  -- visited[i] = true means we've visited the edge (i, i+1)
  local subpolygons = {}
  local visited_out = {}
  for v = 1, #vertices do
    if not visited_out[v] then
      visited_out[v] = true
      local p = make_subpolygon(model, new_edges, visited_out, vertices, v)
      table.insert(subpolygons, p)
    end
  end
  return subpolygons
end

function make_subpolygon(model, new_edges, visited_out, vertices, start)
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

Trapezoid = {bottom = 0, bottom_far = {}, top = nil, top_far = {}}

function Trapezoid:new (bottom, far_edges)
  local o = {}
  _G.setmetatable(o, self)
  self.__index = self
  o.bottom = bottom
  o.bottom_far = far_edges
  return o
end

function add_trapezoid(list, bottom, ...)
  local t = Trapezoid:new(bottom, {...})
  list.by_bottom[bottom] = t
  for _, edge in ipairs({...}) do
    list.by_edge[edge] = t
  end
  table.insert(list, t)
end

function close_trapezoid(trapezoid, top, ...)
  trapezoid.top = top
  trapezoid.top_far = {...}
end

function trapezoidalize(vertices, model)
  local edges = {}
  local trapezoids = {by_bottom = {}, by_top = {}, by_edge = {}}
  for i = 1, #vertices do
    local v = vertices[vertices:sorted(i)]
    local u = vertices[vertices:ccw(vertices:sorted(i))]
    local w = vertices[vertices:cw(vertices:sorted(i))]
    local inside, next_edge_i = is_inside(edges, v, false and model)
    local left_edge = edges[next_edge_i-1]
    local right_edge = edges[next_edge_i] -- Because of tie breaking, sometimes this is the intersecting edge
    local right_right_edge = edges[next_edge_i+1]
    local right_right_right_edge = edges[next_edge_i+2]
    if v.y <= u.y and v.y < w.y then -- "V" case
      if inside then -- hollow "V"
        table.insert(edges, next_edge_i, ipe.Segment(v, w))
        table.insert(edges, next_edge_i, ipe.Segment(v, u))
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], vertices:sorted(i), right_edge, left_edge)
        add_trapezoid(trapezoids, vertices:sorted(i), left_edge, edges[next_edge_i])
        add_trapezoid(trapezoids, vertices:sorted(i), right_edge, edges[next_edge_i+1])
      else -- filled "V"
        table.insert(edges, next_edge_i, ipe.Segment(v, u))
        table.insert(edges, next_edge_i, ipe.Segment(v, w))
        add_trapezoid(trapezoids, vertices:sorted(i), edges[next_edge_i], edges[next_edge_i+1])
      end
    elseif v.y >= u.y and v.y > w.y then -- "^" Case
      table.remove(edges, next_edge_i)
      table.remove(edges, next_edge_i)
      if inside then -- hollow "^"
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], vertices:sorted(i), left_edge)
        close_trapezoid(trapezoids.by_edge[right_right_edge] or trapezoids.by_edge[right_right_right_edge], vertices:sorted(i), right_right_right_edge)
        add_trapezoid(trapezoids, vertices:sorted(i), left_edge, right_right_right_edge)
      else -- filled "^"
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[right_right_edge], vertices:sorted(i))
      end
    else -- "<" or ">" case
      local new_edge = nil
      if v.y < u.y then
        new_edge = ipe.Segment(v, u)
      else
        new_edge = ipe.Segment(v, w)
      end
      if inside then -- Fill is to the left
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[left_edge], vertices:sorted(i), left_edge)
        add_trapezoid(trapezoids, vertices:sorted(i), left_edge, new_edge)
      else -- Fill is to the right
        close_trapezoid(trapezoids.by_edge[right_edge] or trapezoids.by_edge[right_right_edge], vertices:sorted(i), right_right_edge)
        add_trapezoid(trapezoids, vertices:sorted(i), right_right_edge, new_edge)
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

-- Returns if inside, and the index of the first edge not strictly to the left of the point
-- If the point is on the edge, it describes the region to the left
-- Linear time, could totally be improved to logarithmic with binary search on a tree
function is_inside(edges, v, model)
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


methods = {
  { label="Trapezoidalize", run = trapezoidalize_and_draw },
  { label="Triangulate", run = triangulate_and_draw },
}

----------------------------------------------------------------------
