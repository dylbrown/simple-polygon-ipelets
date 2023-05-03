-----------------------------------------------------
-- Line Arrangement & Face Classes
-----------------------------------------------------


local Arrangement = {Face = {face = true}}

function Arrangement:new (lines, boundary)
  local o = {lines=lines, boundary=boundary}
  _G.setmetatable(o, self)
  self.__index = self
  return o
end

function Arrangement.Face:new (boundary)
  local o = {}
  if boundary then o = {table.unpack(boundary)} end
  _G.setmetatable(o, self)
  self.__index = self
  return o
end

function Arrangement:generate(model)
  if self.faces then return self.faces end
  local faces = {self.boundary}
  for id, line in ipairs(self.lines) do
    local faces_intersected = {}
    for face_id = #faces,1,-1 do
      local face = faces[face_id]
      for i = 1, #face do
        if face[i]:intersects(line) then
          -- Split Face
          if not faces_intersected[face] then
            faces_intersected[face] = true
            local split = {}
            for k, edge in ipairs(face) do
              if edge:intersects(line) then
                table.insert(split, k)
                if #split == 2 then break end
              end
            end
            local min_pt, max_pt
            if #split < 2 then
              
              goto continue
              -- Epsilon away from an edge
              p, q = line:endpoints()
              local other_endpoint = ((p == split[1]) and q) or p
              for k, edge in ipairs(face) do
                local dist = edge:distance(other_endpoint)
                if dist < .001 then
                  split[2] = k
                  break
                end
              end
              if #split < 2 then
                local paths = {}
                for _, edge in ipairs(face) do
                  p, q = edge:endpoints()
                  local curve = {type="curve"; closed=false; {type="segment"; p, q}}
                  table.insert(paths, ipe.Path(model.attributes, {curve}))
                end
                p, q = line:endpoints()
                table.insert(paths, ipe.Path(model.attributes, {{type="curve"; closed=false; {type="segment"; p, q}}}))
                
                local pt = face[split[1]]:intersects(line)
                _G.ipe_warn(pt.x.." "..pt.y)
                model:creation("Face", ipe.Group(paths))
              end
              if split[1] < split[2] then
                max_pt = other_endpoint
              else
                min_pt = other_endpoint
              end
            end
            local min_id = math.min(split[1], split[2])
            local min_pt = min_pt or face[min_id]:intersects(line)
            local min_p, min_q = face[min_id]:endpoints();
            local max_id = math.max(split[1], split[2])
            local max_pt = max_pt or face[max_id]:intersects(line)
            local max_p, max_q = face[max_id]:endpoints();

            -- First new face
            local f1 = Arrangement.Face:new()
            if (min_pt - min_q):len() > .0001 then
              table.insert(f1, ipe.Segment(min_pt, min_q))
            end
            for l = min_id+1, max_id-1 do
              table.insert(f1, face[l])
            end
            if (max_p - max_pt):len() > .0001 then
              table.insert(f1, ipe.Segment(max_p, max_pt))
            end
            table.insert(f1, ipe.Segment(max_pt, min_pt))

            -- Second new face
            local f2 = Arrangement.Face:new()
            if (max_q - max_pt):len() > .0001 then
              table.insert(f2, ipe.Segment(max_pt, max_q))
            end
            for l = max_id+1, #face do
              table.insert(f2, face[l])
            end
            for l = 1, min_id-1 do
              table.insert(f2, face[l])
            end
            if (min_p - min_pt):len() > .0001 then
              table.insert(f2, ipe.Segment(min_p, min_pt))
            end
            table.insert(f2, ipe.Segment(min_pt, max_pt))

            -- Remove old face
            table.remove(faces, face_id)

            -- Add new faces
            table.insert(faces, f1)
            table.insert(faces, f2)
            faces_intersected[f1] = true
            faces_intersected[f2] = true
          end
        end
          ::continue::
      end
    end
  end
  self.faces = faces
  return faces
end

return Arrangement
