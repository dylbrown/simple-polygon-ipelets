----------------------------------------------------------------------
-- triangulation ipelet
----------------------------------------------------------------------

label = "Simple Polygons"

about = [[
Various algorithms run on simple polygons
]]
Polygon = {}

function Polygon:new ()
  local o = {}
  _G.setmetatable(o, self)
  self.__index = self
  return o
end

function Polygon:sorted_cw(v)
  local index = ((self._sorted[v] - 2) % #self) + 1
  return index
end

function Polygon:sorted_ccw(v)
  local index  = (self._sorted[v] % #self) + 1
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

function make_vertices(model)local page = model:page()
  local prim = page:primarySelection()
  if not prim then model.ui:explain("no selection") return end

  local obj = page[prim]
  if obj:type() ~= "path" then incorrect(model) return end

  local shape = obj:shape()
  if (#shape ~= 1 or shape[1].type ~= "curve") then
    incorrect(model)
    return
  end

  local vertices = Polygon:new()

  local m = obj:matrix()
  table.insert(vertices, m * shape[1][1][1])
  for _, line in ipairs(shape[1]) do
    table.insert(vertices, m * line[2])
  end
  return vertices
end

function triangulate(model)
  local vertices = make_vertices(model)
  if vertices == nil then return end
  local trapezoids = trapezoidalize(vertices, model)
  local trapezoid_crosses = {}
  for _, t in ipairs(trapezoids) do
    if not vertices:are_adjacent(t.bottom, t.top) then
      local path = ipe.Path(model.attributes, {{type="curve"; closed=false;
          {type="segment"; vertices[t.bottom], vertices[t.top]}
        }})
      table.insert(trapezoid_crosses, path)
    end
  end
  model:creation("Slice Trapezoids", ipe.Group(trapezoid_crosses))
end

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
    local u = vertices[vertices:sorted_cw(i)]
    local w = vertices[vertices:sorted_ccw(i)]
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
  { label="Triangulate", run = triangulate },
}

----------------------------------------------------------------------
