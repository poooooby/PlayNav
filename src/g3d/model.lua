-- written by groverbuger for g3d
-- MIT license

-- PlayNav: run by g3d's init with the g3d table (no require in a mod); objloader and
-- collisions are left out
local g3d = ...
local newMatrix = g3d.newMatrix
local vectors = g3d.vectors
local camera = g3d.camera
local vectorCrossProduct = vectors.crossProduct
local vectorNormalize = vectors.normalize

----------------------------------------------------------------------------------------------------
-- define a model class
----------------------------------------------------------------------------------------------------

local model = {}
model.__index = model

-- define some default properties that every model should inherit
-- that being the standard vertexFormat and basic 3D shader
model.vertexFormat = {
    {"VertexPosition", "float", 3},
    {"VertexTexCoord", "float", 2},
    {"VertexNormal", "float", 3},
    {"VertexColor", "byte", 4},
}
model.shader = g3d.shader

-- this returns a new instance of the model class
-- a model must be given a .obj file or equivalent lua table, and a texture
-- translation, rotation, and scale are all 3d vectors and are all optional
local function newModel(verts, texture, translation, rotation, scale)
    local self = setmetatable({}, model)

    -- PlayNav: verts is always a table and texture an Image (or nil): no file paths, which
    -- the mod sandbox cannot open

    -- initialize my variables
    self.verts = verts
    self.texture = texture
    self.mesh = love.graphics.newMesh(self.vertexFormat, self.verts, "triangles")
    if self.texture then self.mesh:setTexture(self.texture) end
    self.matrix = newMatrix()
    if type(scale) == "number" then scale = {scale, scale, scale} end
    self:setTransform(translation or {0,0,0}, rotation or {0,0,0}, scale or {1,1,1})

    return self
end

-- populate model's normals in model's mesh automatically
-- if true is passed in, then the normals are all flipped
function model:makeNormals(isFlipped)
    for i=1, #self.verts, 3 do
        if isFlipped then
            self.verts[i+1], self.verts[i+2] = self.verts[i+2], self.verts[i+1]
        end

        local vp = self.verts[i]
        local v = self.verts[i+1]
        local vn = self.verts[i+2]

        local n_1, n_2, n_3 = vectorNormalize(vectorCrossProduct(v[1]-vp[1], v[2]-vp[2], v[3]-vp[3], vn[1]-v[1], vn[2]-v[2], vn[3]-v[3]))
        vp[6], v[6], vn[6] = n_1, n_1, n_1
        vp[7], v[7], vn[7] = n_2, n_2, n_2
        vp[8], v[8], vn[8] = n_3, n_3, n_3
    end

    self.mesh = love.graphics.newMesh(self.vertexFormat, self.verts, "triangles")
    self.mesh:setTexture(self.texture)
end

-- move and rotate given two 3d vectors
function model:setTransform(translation, rotation, scale)
    self.translation = translation or self.translation
    self.rotation = rotation or self.rotation
    self.scale = scale or self.scale
    self:updateMatrix()
end

-- move given one 3d vector
function model:setTranslation(tx,ty,tz)
    self.translation[1] = tx
    self.translation[2] = ty
    self.translation[3] = tz
    self:updateMatrix()
end

-- rotate given one 3d vector
-- using euler angles
function model:setRotation(rx,ry,rz)
    self.rotation[1] = rx
    self.rotation[2] = ry
    self.rotation[3] = rz
    self.rotation[4] = nil
    self:updateMatrix()
end

-- create a quaternion from an axis and an angle
function model:setAxisAngleRotation(x,y,z,angle)
    x,y,z = vectorNormalize(x,y,z)
    angle = angle / 2

    self.rotation[1] = x * math.sin(angle)
    self.rotation[2] = y * math.sin(angle)
    self.rotation[3] = z * math.sin(angle)
    self.rotation[4] = math.cos(angle)

    self:updateMatrix()
end

-- rotate given one quaternion
function model:setQuaternionRotation(x,y,z,w)
    self.rotation[1] = x
    self.rotation[2] = y
    self.rotation[3] = z
    self.rotation[4] = w
    self:updateMatrix()
end

-- resize model's matrix based on a given 3d vector
function model:setScale(sx,sy,sz)
    self.scale[1] = sx
    self.scale[2] = sy or sx
    self.scale[3] = sz or sx
    self:updateMatrix()
end

-- update the model's transformation matrix
function model:updateMatrix()
    self.matrix:setTransformationMatrix(self.translation, self.rotation, self.scale)
end

-- align's the model matrix to a given point
-- up vector is assumed to be normalized
function model:lookAtFrom(pos, target, up)
    local pos = pos or self.translation
    self.matrix:lookAtFrom(pos, target, up or {0,0,1}, self.scale)
end

function model:lookAt(target, up)
    self.matrix:lookAtFrom(self.translation, target, up or {0,0,1}, self.scale)
end




-- draw the model
-- PlayNav: the caller wraps its pass in love.graphics.push("all") / pop
function model:draw(shader)
    local shader = shader or self.shader
    local previousShader = love.graphics.getShader()
    love.graphics.setShader(shader)
    shader:send("modelMatrix", self.matrix)
    shader:send("viewMatrix", camera.viewMatrix)
    shader:send("projectionMatrix", camera.projectionMatrix)
    if shader:hasUniform "isCanvasEnabled" then
        shader:send("isCanvasEnabled", love.graphics.getCanvas() ~= nil)
    end
    love.graphics.draw(self.mesh)
    love.graphics.setShader(previousShader)
end

-- PlayNav: the ffi compression (model:compress) and the collision helpers are left out:
-- mods get no ffi, and the arena needs no collisions

return newModel
