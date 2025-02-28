-- Just boxes

local _box = std.object {
  _type = "Box",
  height= 0,
  depth= 0,
  width= 0,
  misfit = false,
  type="special",
  explicit = false,
  discardable = false,
  value=nil,
  __tostring = function (str) return str.type end,
  __concat = function (a, b) return tostring(a)..tostring(b) end,
  init = function (self) return self end,
  lineContribution = function (self)
    -- Regardless of the orientations, "width" is always in the
    -- writingDirection, and "height" is always in the "pageDirection"
    return self.misfit and self.height or self.width
  end
}

function _box:outputYourself () SU.error(self.type.." with no output routine") end
function _box:toText ()  return self.type end
function _box:isBox ()   return self.type=="hbox" or self.type == "alternative" or self.type == "nnode" or self.type=="vbox" end
function _box:isNnode () return self.type=="nnode" end
function _box:isGlue ()  return self.type == "glue" end
function _box:isVglue ()  return self.type == "vglue" end
function _box:isUnshaped ()  return self.type == "unshaped" end
function _box:isAlternative ()  return self.type == "alternative" end
function _box:isVbox ()  return self.type == "vbox" end
function _box:isMigrating ()  return self.migrating end
function _box:isPenalty ()  return self.type == "penalty" end
function _box:isDiscretionary ()  return self.type == "discretionary" end

function _box:isKern ()  return self.type == "kern" end

-- Hboxes

local _hbox = _box {
  type = "hbox",
  __tostring = function (this)
    return "H<" .. tostring(this.width) .. ">^" .. tostring(this.height) .. "-" .. tostring(this.depth) .. "v"
  end,
  scaledWidth = function (self, line)
    local scaledWidth = self:lineContribution()
    if type(scaledWidth) ~= "table" then return scaledWidth end
    if line.ratio < 0 and type(self.width) == "table" and self.width.shrink > 0 then
      scaledWidth = scaledWidth + self.width.shrink * line.ratio
    elseif line.ratio > 0 and type(self.width) == "table" and  self.width.stretch > 0 then
      scaledWidth = scaledWidth + self.width.stretch * line.ratio
    end
    return scaledWidth.length
  end,
  outputYourself = function (self, typesetter, line)
    if not self.value.glyphString then return end
    if typesetter.frame:writingDirection() == "RTL" then
      typesetter.frame:advanceWritingDirection(self:scaledWidth(line))
    end
    SILE.outputter.moveTo(typesetter.frame.state.cursorX, typesetter.frame.state.cursorY)
    SILE.outputter.setFont(self.value.options)
    SILE.outputter.outputHbox(self.value, self:scaledWidth(line))
    if typesetter.frame:writingDirection() ~= "RTL" then
      typesetter.frame:advanceWritingDirection(self:scaledWidth(line))
    end
  end
}

-- Native nodes (clever hboxes)

local _nnode = _hbox {
  type = "nnode",
  text = "",
  language = "",
  pal = nil,
  nodes = {},
  __tostring = function (this)
    return "N<" .. tostring(this.width) .. ">^" .. this.height .. "-" .. this.depth .. "v(" .. this:toText() .. ")";
  end,
  init = function (self)
    if 0 == self.depth then self.depth = math.max(0, table.unpack(SU.map(function (node) return node.depth end, self.nodes))) end
    if 0 == self.height then self.height = math.max(0, table.unpack(SU.map(function (node) return node.height end, self.nodes))) end
    if 0 == self.width then self.width = SU.sum(SU.map(function (node) return node.width end, self.nodes)) end
    return self
    end,
  outputYourself = function (self, typesetter, line)
    if self.parent and not self.parent.hyphenated then
      if not self.parent.used then
        self.parent:outputYourself(typesetter, line)
      end
      self.parent.used = true
      return
    end
    for _, node in ipairs(self.nodes) do node:outputYourself(typesetter, line) end
  end,
  toText = function (self) return self.text end
}

local _unshaped = _nnode {
  type = "unshaped",
  __tostring = function (this)
    return "U(" .. this:toText() .. ")";
  end,
  shape = function (this)
    local node =  SILE.shaper:createNnodes(this.text, this.options)
    for i=1, #node do
      node[i].parent = this.parent
    end
    return node
  end,
  width = nil,
  outputYourself = function (_)
    SU.error("An unshaped node made it to output", true)
  end,
  __index = function (_, k)
    if k == "width" then SU.error("Can't get width of unshaped node", true) end
  end
}

-- Discretionaries

local _disc = _hbox {
  type = "discretionary",
  prebreak = {},
  postbreak = {},
  replacement = {},
  used = false,
  prebw = nil,
  __tostring = function (this)
      return "D(" .. SU.concat(this.prebreak, "") .. "|" .. SU.concat(this.postbreak, "") .."|" .. SU.concat(this.replacement, "") .. ")";
  end,
  toText = function (self) return self.used and "-" or "_" end,
  outputYourself = function (self, typesetter, line)
    if self.used then
      local i = 1
      while (line.nodes[i]:isGlue() and line.nodes[i].value == "lskip")
          or line.nodes[i] == SILE.nodefactory.zeroHbox do
        i = i+1
      end
      if (line.nodes[i] == self) then
        for _, node in ipairs(self.postbreak) do node:outputYourself(typesetter, line) end
      else
        for _, node in ipairs(self.prebreak) do node:outputYourself(typesetter, line) end
      end
    else
      for _, node in ipairs(self.replacement) do node:outputYourself(typesetter, line) end
    end
  end,
  prebreakWidth = function (self)
    if self.prebw then return self.prebw end
    local width = 0
    for _, node in pairs(self.prebreak) do width = width + node.width end
    self.prebw = width
    return width
  end,
  postbreakWidth = function (self)
    if self.postbw then return self.postbw end
    local width = 0
    for _, node in pairs(self.postbreak) do width = width + node.width end
    self.postbw = width
    return width
  end,
  replacementWidth = function (self)
    if self.replacew then return self.replacew end
    local width = 0
    for _, node in pairs(self.replacement) do width = width + node.width end
    self.replacew = width
    return width
  end,
  prebreakHeight = function (self)
    if self.prebh then return self.prebh end
    local width = 0
    for _, node in pairs(self.prebreak) do if node.height > width then width = node.height end end
    self.prebh = width
    return width
  end,
  postbreakHeight = function (self)
    if self.postbh then return self.postbh end
    local width = 0
    for _, node in pairs(self.postbreak) do if node.height > width then width = node.height end end
    self.postbh = width
    return width
  end,
  replacementHeight = function (self)
    if self.replaceh then return self.replaceh end
    local width = 0
    for _, node in pairs(self.replacement) do if node.height > width then width = node.height end end
    self.replaceh = width
    return width
  end,
}

-- Alternatives

local _alt = _hbox {
  type = "alternative",
  options = {},
  selected = nil,
  __tostring = function (self)
    return "A(" .. SU.concat(self.options, " / ") .. ")"
  end,
  minWidth = function (self)
    local min = self.options[1].width
    for i = 2, #self.options do
      if self.options[i].width < min then min = self.options[i].width end
    end
    return min
  end,
  deltas = function (self)
    local minWidth = self:minWidth()
    local rv = {}
    for i = 1, #self.options do rv[#rv+1] = self.options[i].width - minWidth end
    return rv
  end,
  outputYourself = function (self, typesetter, line)
    if self.selected then
      self.options[self.selected]:outputYourself(typesetter, line)
    end
  end,
}

-- Glue
local _glue = _box {
  _type = "Glue",
  type = "glue",
  discardable = true,
  __tostring = function (this)
    return (this.explicit and "E:" or "") .. "G<" .. tostring(this.width) .. ">"
  end,
  toText = function () return " " end,
  outputYourself = function (self, typesetter, line)
    local scaledWidth = self.width.length
    if line.ratio and line.ratio < 0 and self.width.shrink > 0 then
      scaledWidth = scaledWidth + self.width.shrink * line.ratio
    elseif line.ratio and line.ratio > 0 and self.width.stretch > 0 then
      scaledWidth = scaledWidth + self.width.stretch * line.ratio
    end
    typesetter.frame:advanceWritingDirection(scaledWidth)
  end
}
local _kern = _glue {
  _type = "Kern",
  type = "kern",
  discardable = false,
  __tostring = function (this)
    return "K<" .. tostring(this.width) .. ">"
  end,
}

-- VGlue
local _vglue = _box {
  type = "vglue",
  _type = "VGlue",
  discardable = true,
  __tostring = function (this)
    return (this.explicit and "E:" or "") .. "VG<" .. tostring(this.height) .. ">";
  end,
  setGlue = function (self, adjustment)
    self.height.length = SILE.toAbsoluteMeasurement(self.height.length) + adjustment
    self.height.stretch = 0
    self.height.shrink = 0
  end,
  outputYourself = function (_, typesetter, line)
    local depth = line.depth
    depth = depth + SILE.toAbsoluteMeasurement(line.height)
    if type(depth) == "table" then depth = depth.length end
    typesetter.frame:advancePageDirection(depth)
  end,
  unbox = function (self) return { self } end
}

local _vkern = _vglue {
  _type = "VKern",
  type = "vkern",
  discardable = false,
  __tostring = function (this)
    return "VK<" .. tostring(this.height) .. ">"
  end,
}


-- Penalties
local _penalty = _box {
  type = "penalty",
  discardable = true,
  width = SILE.length.new({}),
  flagged = 0,
  penalty = 0,
  __tostring = function (this)
    return "P(" .. this.flagged .. "|" .. this.penalty .. ")";
  end,
  outputYourself = function () end,
  toText = function () return "(!)" end,
  unbox = function (self) return {self} end
}

-- Vbox
local _vbox = _box {
  type = "vbox",
  nodes = {},
  __tostring = function (this)
    return "VB<" .. tostring(this.height) .. "|" .. this:toText() .. "v"..tostring(this.depth)..")";
  end,
  init = function (self)
    self.depth = 0
    self.height = 0
    for i=1, #(self.nodes) do
      local node = self.nodes[i]
      local height = type(node.height) == "table" and node.height.length or node.height
      local depth = type(node.depth) == "table" and node.depth.length or node.depth
      self.depth = (depth > self.depth) and depth or self.depth
      self.height = (height > self.height) and height or self.height
    end
    return self
  end,
  toText = function (self)
    return "VB[" .. SU.concat(SU.map(function (node) return node:toText().."" end, self.nodes), "") .. "]"
  end,
  outputYourself = function (self, typesetter, line)
    local advanceamount = self.height
    if type(advanceamount) == "table" then advanceamount = advanceamount.length end
    typesetter.frame:advancePageDirection(advanceamount)
    local initial = true
    for _, node in pairs(self.nodes) do
      if initial and (node:isGlue() or node:isPenalty()) then
        -- do nothing
      else
        initial = false
        node:outputYourself(typesetter, line)
      end
    end
    if self.depth then typesetter.frame:advancePageDirection(self.depth) end
    typesetter.frame:newLine()
  end,
  unbox = function (self)
    for i = 1, #self.nodes do
      if self.nodes[i]:isVbox() or self.nodes[i]:isVglue() then return self.nodes end
    end
    return {self}
  end,
  append = function (self, box)
    local nodes = box
    if not box then SU.error("nil box given", true) end
    if nodes.type then
      nodes = box:unbox()
    end
    local height = self.height + self.depth
    local lastdepth = 0
    for i = 1, #nodes do
      table.insert(self.nodes, nodes[i])
      height = height + nodes[i].height + nodes[i].depth
      if nodes[i]:isVbox() then lastdepth = nodes[i].depth end
    end
    self.ratio = 1
    self.height = height - lastdepth
    self.depth = lastdepth
  end
}


local _migrating = _hbox {
  material = {},
  value = {},
  nodes = {},
  migrating = true,
  __tostring = function (this)
    return "<M: "..this.material .. ">"
  end
}

SILE.nodefactory = {}

function SILE.nodefactory.newHbox(spec) return _hbox(spec) end
function SILE.nodefactory.newNnode(spec) return _nnode(spec):init() end
function SILE.nodefactory.newUnshaped(spec)
  local u = _unshaped(spec)
  u.width = nil
  return u
end

function SILE.nodefactory.newDisc(spec) return _disc(spec) end
function SILE.nodefactory.newAlternative(spec) return _alt(spec) end

function SILE.nodefactory.newGlue(spec)
  if type(spec) == "table" then return std.tree.clone(_glue(spec)) end
  if type(spec) == "string" then return _glue({width = SILE.length.parse(spec)}) end
  SU.error("Unparsable glue spec "..spec)
end
function SILE.nodefactory.newKern(spec)
  if type(spec) == "table" then return std.tree.clone(_kern(spec)) end
  if type(spec) == "string" then return _kern({width = SILE.length.parse(spec)}) end
  SU.error("Unparsable kern spec "..spec)
end
function SILE.nodefactory.newVglue(spec)
  if type(spec) == "table" then return std.tree.clone(_vglue(spec)) end
  if type(spec) == "string" then return _vglue({height = SILE.length.parse(spec)}) end
  SU.error("Unparsable glue spec "..spec)
end
function SILE.nodefactory.newVKern(spec)
  if type(spec) == "table" then return std.tree.clone(_vkern(spec)) end
  if type(spec) == "string" then return _vkern({height = SILE.length.parse(spec)}) end
  SU.error("Unparsable kern spec "..spec)
end
function SILE.nodefactory.newPenalty(spec)  return std.tree.clone(_penalty(spec)) end
function SILE.nodefactory.newDiscretionary(spec)  return _disc(spec) end
function SILE.nodefactory.newVbox(spec)  return _vbox(spec):init() end
function SILE.nodefactory.newMigrating(spec)  return _migrating(spec) end

-- This infinity needs to be smaller than an actual infinity but bigger than the infinite stretch
-- added by the typesetter. See https://github.com/sile-typesetter/sile/issues/227
local inf = 1e13
SILE.nodefactory.zeroGlue = SILE.nodefactory.newGlue({width = SILE.length.new({length = 0})})
SILE.nodefactory.hfillGlue = SILE.nodefactory.newGlue({width = SILE.length.new({length = 0, stretch = inf})})
SILE.nodefactory.vfillGlue = SILE.nodefactory.newVglue({height = SILE.length.new({length = 0, stretch = inf})})
SILE.nodefactory.hssGlue = SILE.nodefactory.newGlue({width = SILE.length.new({length = 0, stretch = inf, shrink = inf})})
SILE.nodefactory.vssGlue = SILE.nodefactory.newVglue({height = SILE.length.new({length = 0, stretch = inf, shrink = inf})})
SILE.nodefactory.zeroHbox = SILE.nodefactory.newHbox({ width = SILE.length.new({length = 0, stretch = 0, shrink = 0}), value = {glyph = 0} });
SILE.nodefactory.zeroVglue = SILE.nodefactory.newVglue({height = SILE.length.new({length = 0, stretch = 0, shrink = 0}) })

return SILE.nodefactory
