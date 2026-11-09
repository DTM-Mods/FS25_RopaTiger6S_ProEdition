--- Window tint for the cab glass, picked in the shop.
--
-- The cab glass is alpha blended and its see-through amount comes from the alpha channel of its
-- diffuse texture, so a tint has to swap that texture; a color or shader parameter cannot change it.
-- Each designConfiguration may name a tinted texture in a <windowTint filename="..."/> child. On load,
-- the glass material is cloned with that texture through setMaterialDiffuseMapFromFile and set on every
-- shape below the configured root node that uses it. A configuration without the child keeps the
-- original clear glass.
--
-- The model has no usable material slot names, so the glass is found by its textures: the diffuse map
-- and the detail diffuse map file names must contain the configured strings. The window frame plastic
-- shares the diffuse map but has a different detail map, so it keeps its look.
--
--     <windowTint diffuseMap="window_diffuse" detailDiffuseMap="clear_diffuse" node="tiger6_front_component1"/>
--     <designConfigurations title="Window Tint">
--         <designConfiguration name="Clear" price="0"/>
--         <designConfiguration name="Dark" price="1500">
--             <windowTint filename="textures/windowTintDark_diffuse.dds"/>
--         </designConfiguration>
--     </designConfigurations>

WindowTint = {}

function WindowTint.prerequisitesPresent(specializations)
    return true
end

function WindowTint.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("WindowTint")

    schema:register(XMLValueType.STRING, "vehicle.windowTint#diffuseMap", "Part of the glass diffuse map file name", "window_diffuse")
    schema:register(XMLValueType.STRING, "vehicle.windowTint#detailDiffuseMap", "Part of the glass detail diffuse map file name", "clear_diffuse")
    schema:register(XMLValueType.NODE_INDEX, "vehicle.windowTint#node", "Only glass below this node is tinted (default: whole vehicle)")
    schema:register(XMLValueType.STRING, "vehicle.designConfigurations.designConfiguration(?).windowTint#filename", "Tinted glass diffuse texture (alpha sets how much the tint blocks)")

    schema:setXMLSpecializationType()
end

function WindowTint.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", WindowTint)
end

function WindowTint:onLoadFinished(savegame)
    local configId = self.configurations["design"]
    if configId == nil then
        return
    end

    local configKey = string.format("vehicle.designConfigurations.designConfiguration(%d).windowTint", configId - 1)
    local filename = self.xmlFile:getValue(configKey .. "#filename")
    if filename == nil then
        return
    end
    filename = Utils.getFilename(filename, self.baseDirectory)

    local diffuseMap = string.lower(self.xmlFile:getValue("vehicle.windowTint#diffuseMap", "window_diffuse"))
    local detailDiffuseMap = string.lower(self.xmlFile:getValue("vehicle.windowTint#detailDiffuseMap", "clear_diffuse"))
    local rootNode = self.xmlFile:getValue("vehicle.windowTint#node", nil, self.components, self.i3dMappings)

    local rootNodes = {}
    if rootNode ~= nil then
        table.insert(rootNodes, rootNode)
    else
        for _, component in ipairs(self.components) do
            table.insert(rootNodes, component.node)
        end
    end

    local tint = {
        filename = filename,
        diffuseMap = diffuseMap,
        detailDiffuseMap = detailDiffuseMap,
        isGlass = {},       -- materialId -> bool
        tinted = {},        -- original materialId -> tinted materialId
        numTinted = 0
    }

    for _, node in ipairs(rootNodes) do
        WindowTint.tintRec(node, tint)
    end

    if tint.numTinted == 0 then
        Logging.xmlWarning(self.xmlFile, "Window tint: no glass with diffuse map '%s' and detail diffuse map '%s' found", diffuseMap, detailDiffuseMap)
    end
end

function WindowTint.isGlassMaterial(materialId, tint)
    local isGlass = tint.isGlass[materialId]
    if isGlass == nil then
        local diffuse = getMaterialDiffuseMapFilename(materialId)
        local detailDiffuse = getMaterialCustomMapFilename(materialId, "detailDiffuse")
        isGlass = diffuse ~= nil and detailDiffuse ~= nil
            and string.find(string.lower(diffuse), tint.diffuseMap, 1, true) ~= nil
            and string.find(string.lower(detailDiffuse), tint.detailDiffuseMap, 1, true) ~= nil
        tint.isGlass[materialId] = isGlass
    end

    return isGlass
end

function WindowTint.tintRec(node, tint)
    if getHasClassId(node, ClassIds.SHAPE) then
        for i = 0, getNumOfMaterials(node) - 1 do
            local materialId = getMaterial(node, i)
            if WindowTint.isGlassMaterial(materialId, tint) then
                local newMaterialId = tint.tinted[materialId]
                if newMaterialId == nil then
                    newMaterialId = setMaterialDiffuseMapFromFile(materialId, tint.filename, true, true, false)
                    tint.tinted[materialId] = newMaterialId
                    tint.isGlass[newMaterialId] = false
                end

                setMaterial(node, newMaterialId, i)
                tint.numTinted = tint.numTinted + 1
            end
        end
    end

    for i = 0, getNumOfChildren(node) - 1 do
        WindowTint.tintRec(getChildAt(node, i), tint)
    end
end
