-- written by groverbuger for g3d
-- MIT license
-- PlayNav: vendored from https://github.com/groverburger/g3d at 639120acd754dc5c34402e41eb1687b1a5a3ffa8
-- (g3d 1.6.0) with the changes marked "PlayNav:" - mods cannot `require` their own files, so
-- this file is run by src/training/arena3d.lua with (use, shader): use(name) runs this folder's
-- <name>.lua with the g3d table as its argument; the shader is built (and checked) by the
-- caller. objloader, collisions and the ffi compression are left out.

--[[
         __       __
       /'__`\    /\ \
   __ /\_\L\ \   \_\ \
 /'_ `\/_/_\_<_  /'_` \
/\ \L\ \/\ \L\ \/\ \L\ \
\ \____ \ \____/\ \___,_\
 \/___L\ \/___/  \/__,_ /
   /\____/
   \_/__/
--]]

local use, shader = ...

local g3d = {
    _VERSION     = "g3d 1.6.0",
    _DESCRIPTION = "Simple and easy 3D engine for LÖVE.",
    _URL         = "https://github.com/groverburger/g3d",
    _LICENSE     = [[
        MIT License

        Copyright (c) 2026 groverburger

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
    ]],
}

-- PlayNav: the sibling loader in place of require(g3d.path .. ".x")
g3d.use = use

-- the shader is what does the heavy lifting, displaying 3D meshes on your 2D monitor
-- PlayNav: built by the caller from this folder's g3d.vert source (newShader by path cannot see
-- mod files); it may be nil, the caller then passing its own to model:draw
g3d.shader = shader
g3d.vectors = use("vectors", g3d)
g3d.newMatrix = use("matrices", g3d)
g3d.camera = use("camera", g3d)
g3d.newModel = use("model", g3d)
g3d.camera.updateProjectionMatrix()
g3d.camera.updateViewMatrix()

-- PlayNav: no global love.graphics.setDepthMode here - it would leak into the engine's 2D
-- drawing; the caller sets depth for its own pass only

return g3d
