----------------------------------------------------------------------
-- triangulation ipelet
----------------------------------------------------------------------

label = "Simple Polygons"

about = [[
Various algorithms run on simple polygons
]]

-----------------------------------------------------
-- Hack to allow requiring other ipelets files
-----------------------------------------------------

local start = 0
while true do
  local find = string.find(_G.package.path, ";", start + 1)
  if find then
    start = find
  else
    break
  end
end

local lua_dir = string.sub(_G.package.path, start + 1)
local ipelets_dir = string.sub(lua_dir, 1, #lua_dir - 9) .. "ipelets\\?.lua;"

if not string.find(_G.package.path, ipelets_dir, 1, true) then
  _G.package.path = ipelets_dir .. _G.package.path
end

-----------------------------------------------------
-- Imports
-----------------------------------------------------

-- Hack to allow hot reloading. Might add cleverer logic to ipe's main.lua in future
_G.package.loaded['util.polygon'] = nil
local Polygon = _G.require("util.polygon")

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
-- Shortest Path Map Ipelet
-----------------------------------------------------

-----------------------------------------------------
-- Triangulate Ipelet
-----------------------------------------------------

function triangulate_and_draw(model)
  local vertices = make_vertices(model)
  if vertices == nil then return end
  local monotones = vertices:triangulate(model)
  
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

-----------------------------------------------------
-- Trapezoidalize Ipelet
-----------------------------------------------------

function trapezoidalize_and_draw(model)
  local vertices = make_vertices(model)
  if not vertices then return end
  local trapezoids = vertices:trapezoidalize(model)
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


methods = {
  { label="Trapezoidalize", run = trapezoidalize_and_draw },
  { label="Triangulate", run = triangulate_and_draw },
}

----------------------------------------------------------------------
