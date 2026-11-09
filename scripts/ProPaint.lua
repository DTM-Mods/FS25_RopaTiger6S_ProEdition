--- Paints the vehicle with a shop color configuration without relying on material slot names.
--
-- The base game color configurations find the paint through material slot names stored in the
-- .i3d.shapes file. These models carry no usable slot names, so the configured color never reaches
-- the body. Instead, each <paint> entry names the colorScale the paint material has in the i3d; every
-- shape material with that colorScale gets the selected color through VehicleMaterial:applyToMaterial,
-- the same call the base game uses when a slot name matches.
--
--     <proPaint>
--         <paint colorScale="1.11 0.616 0"/>                        full paint (template + color)
--         <paint colorScale="0.9914 0.687 0" colorOnly="true"/>     color only, keeps the i3d finish
--         <paint colorScale="..." configName="designColor"/>        another color configuration
--         <paint colorScale="..." nodes="beltA beltB"/>             only shapes with these names
--         <paint colorScale="..." excludeNodes="interior_vis"/>     every shape except these
--     </proPaint>
--
-- A shape material is painted by the first <paint> that matches it.

ProPaint = {}

function ProPaint.prerequisitesPresent(specializations)
    return true
end

function ProPaint.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("ProPaint")

    schema:register(XMLValueType.STRING, "vehicle.proPaint.paint(?)#colorScale", "colorScale of the paint material in the i3d (omit with nodes to paint every material)")
    schema:register(XMLValueType.BOOL, "vehicle.proPaint.paint(?)#skipFirst", "Do nothing while the first color of the configuration is selected", false)
    schema:register(XMLValueType.BOOL, "vehicle.proPaint.paint(?)#colorOnly", "Only apply the color, keep the rest of the i3d material", false)
    schema:register(XMLValueType.STRING, "vehicle.proPaint.paint(?)#configName", "Color configuration to paint with", "baseColor")
    schema:register(XMLValueType.STRING, "vehicle.proPaint.paint(?)#nodes", "Only paint shapes with these names (space separated)")
    schema:register(XMLValueType.STRING, "vehicle.proPaint.paint(?)#excludeNodes", "Never paint shapes with these names (space separated)")
    schema:register(XMLValueType.STRING, "vehicle.proPaint.paint(?)#detailMap", "Only paint materials whose detail diffuse map filename contains this text (e.g. plasticPainted)")

    schema:setXMLSpecializationType()
end

function ProPaint.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", ProPaint)
end

function ProPaint:onLoadFinished(savegame)
    local paints = {}
    self.xmlFile:iterate("vehicle.proPaint.paint", function(_, key)
        local nodes = ProPaint.getNameSet(self.xmlFile:getValue(key .. "#nodes"))
        local colorStr = self.xmlFile:getValue(key .. "#colorScale")
        local color = colorStr ~= nil and string.getVector(colorStr) or nil
        if (colorStr ~= nil or nodes == nil) and (color == nil or #color < 3) then
            Logging.xmlWarning(self.xmlFile, "Invalid colorScale '%s' in '%s'", tostring(colorStr), key)
            return
        end

        local configName = self.xmlFile:getValue(key .. "#configName", "baseColor")
        if self.xmlFile:getValue(key .. "#skipFirst", false) and (self.configurations[configName] or 1) == 1 then
            return
        end

        local material = VehicleConfigurationItemColor.getMaterialByColorConfiguration(self, configName)
        if material ~= nil then
            table.insert(paints, {
                color = color,
                material = material,
                colorOnly = self.xmlFile:getValue(key .. "#colorOnly", false),
                nodes = nodes,
                detailMap = self.xmlFile:getValue(key .. "#detailMap"),
                excludeNodes = ProPaint.getNameSet(self.xmlFile:getValue(key .. "#excludeNodes"))
            })
        end
    end)

    if #paints == 0 then
        return
    end

    -- collect first and paint afterwards: applying a template swaps detail maps, which creates new materials
    local targets = {}
    for _, component in ipairs(self.components) do
        ProPaint.collectTargets(component.node, paints, targets)
    end

    for _, target in ipairs(targets) do
        target.paint.material:applyToMaterial(target.node, target.materialIndex, target.paint.colorOnly)
    end
end

function ProPaint.getNameSet(str)
    if str == nil then
        return nil
    end

    local set = {}
    for _, name in ipairs(string.split(str, " ")) do
        if name ~= "" then
            set[name] = true
        end
    end
    return set
end

function ProPaint.hasDetailMap(materialId, text)
    local filename = getMaterialCustomMapFilename(materialId, "detailDiffuse")
    return filename ~= nil and string.find(filename, text, 1, true) ~= nil
end

function ProPaint.collectTargets(node, paints, targets)
    -- wheels (WheelVisual nodes) are painted by the rim color configuration; the default rim paint shares
    -- the body's colorScale, so without this the rims would always follow the main color
    if getName(node) == "visualWheel" then
        return
    end

    if getHasClassId(node, ClassIds.SHAPE) and getHasShaderParameter(node, "colorScale") then
        local name = getName(node)
        for i = 0, getNumOfMaterials(node) - 1 do
            local materialId = getMaterial(node, i)
            local r, g, b = getMaterialCustomParameter(materialId, "colorScale")
            if r ~= nil and g ~= nil and b ~= nil then
                for _, paint in ipairs(paints) do
                    local color = paint.color
                    if (paint.nodes == nil or paint.nodes[name])
                        and (paint.excludeNodes == nil or not paint.excludeNodes[name])
                        and (paint.detailMap == nil or ProPaint.hasDetailMap(materialId, paint.detailMap))
                        and (color == nil or math.abs(r - color[1]) < 0.001 and math.abs(g - color[2]) < 0.001 and math.abs(b - color[3]) < 0.001) then
                        table.insert(targets, {node = node, materialIndex = i, paint = paint})
                        break
                    end
                end
            end
        end
    end

    for i = 0, getNumOfChildren(node) - 1 do
        ProPaint.collectTargets(getChildAt(node, i), paints, targets)
    end
end
