--- Belt effect materials for crops the base game has none for.
--
-- The crop belt effects (MorphPositionEffect with materialType belt_cropDirt / belt_cropClean) take their
-- material from g_materialManager per fill type whenever the belt starts (setEffectTypeInfo). The base game
-- only ships these for sugar beet, beetroot, potato and onion; for any other crop the belts stay empty.
--
-- Each <fillType> entry below names the mod's belt textures for one crop. If the crop has no material
-- yet, the game's sugar beet belt material (same shader and settings) is cloned with these textures and
-- registered for the crop, so the effects pick it up exactly like a base game material. Registered
-- materials are shared, so this runs once per crop however many vehicles are loaded.
--
-- A cloned material that no shape uses is freed by the engine, and the belt then fails with
-- "Unknown entity id ... in method 'setMaterial'" (seen in game 2026-10-19: empty belts with carrots).
-- So every cloned material is put on a hidden copy of one of the vehicle's shapes, kept under one hidden
-- holder node in the scene root for the whole session (it stays when the vehicle is sold). Each holder is a
-- childless shape (clone() copies the whole subtree). State from an earlier savegame load is dropped.
--
-- As a safety net, MorphPositionEffect.setEffectTypeInfo is extended: if a belt effect ends up without the
-- registered material for one of these crops, the material is put on its mesh directly.
--
--     <proBeltMaterials>
--         <fillType name="PEA" dirt="effects/belt/pea/peaDirt_diffuse.dds" clean="effects/belt/pea/peaClean_diffuse.dds"
--                   normal="effects/belt/pea/pea_normal.dds" specular="effects/belt/pea/pea_specular.dds"/>
--     </proBeltMaterials>

ProBeltMaterials = {}

ProBeltMaterials.MATERIAL_INDEX = 1
-- game crop whose belt materials are cloned, in order of preference
ProBeltMaterials.DONOR_FILL_TYPES = {"SUGARBEET", "POTATO", "BEETROOT", "ONION"}
-- materials registered by this script: fillTypeIndex -> materialType (upper case) -> materialId
ProBeltMaterials.materials = {}
ProBeltMaterials.loggedFixes = {}
-- hidden node holding one shape per cloned material, so the engine keeps the materials
ProBeltMaterials.holderNode = nil

function ProBeltMaterials.prerequisitesPresent(specializations)
    return true
end

function ProBeltMaterials.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("ProBeltMaterials")

    local key = "vehicle.proBeltMaterials.fillType(?)"
    schema:register(XMLValueType.STRING, key .. "#name", "Fill type name", nil, true)
    schema:register(XMLValueType.STRING, key .. "#dirt", "belt_cropDirt diffuse texture")
    schema:register(XMLValueType.STRING, key .. "#clean", "belt_cropClean diffuse texture")
    schema:register(XMLValueType.STRING, key .. "#normal", "Normal map (both belts)")
    schema:register(XMLValueType.STRING, key .. "#specular", "Specular map (both belts)")

    schema:setXMLSpecializationType()
end

function ProBeltMaterials.registerEventListeners(vehicleType)
    -- onLoad: the vehicle's shapes exist by then (needed to keep the materials), and the belts only look up
    -- their material when they start running, so registering here is early enough
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ProBeltMaterials)
end

function ProBeltMaterials:onLoad(savegame)
    self.xmlFile:iterate("vehicle.proBeltMaterials.fillType", function(_, key)
        local fillTypeName = self.xmlFile:getValue(key .. "#name")
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
        if fillTypeIndex == nil then
            Logging.xmlWarning(self.xmlFile, "Unknown fill type '%s' in '%s'", tostring(fillTypeName), key)
            return
        end

        local normal = ProBeltMaterials.getFilename(self, key .. "#normal")
        local specular = ProBeltMaterials.getFilename(self, key .. "#specular")
        ProBeltMaterials.addMaterial(self, fillTypeIndex, "BELT_CROPDIRT", ProBeltMaterials.getFilename(self, key .. "#dirt"), normal, specular)
        ProBeltMaterials.addMaterial(self, fillTypeIndex, "BELT_CROPCLEAN", ProBeltMaterials.getFilename(self, key .. "#clean"), normal, specular)
    end)
end

function ProBeltMaterials.getFilename(vehicle, key)
    local filename = vehicle.xmlFile:getValue(key)
    if filename == nil then
        return nil
    end

    return Utils.getFilename(filename, vehicle.baseDirectory)
end

--- First shape below a node (depth first), used as the template for the holder shapes.
-- clone() copies a node's whole subtree (see PlaceableGreenhouse.lua), so a shape WITHOUT children is
-- preferred; cloning the first shape found (the main component) copied the whole machine every time.
local function findShape(node, leafOnly)
    if getHasClassId(node, ClassIds.SHAPE) and (not leafOnly or getNumOfChildren(node) == 0) then
        return node
    end
    for i = 0, getNumOfChildren(node) - 1 do
        local shape = findShape(getChildAt(node, i), leafOnly)
        if shape ~= nil then
            return shape
        end
    end
    return nil
end

--- Forgets everything from an earlier game session.
-- g_materialManager starts empty on every savegame load (AbstractManager.unloadMapData -> initDataStructures
-- creates a new materials table), but this script's own tables live on as long as the mod Lua does. Without
-- this, materials of an unloaded session could be put on a belt after quitting to the menu and loading again.
function ProBeltMaterials.checkSession()
    if ProBeltMaterials.sessionMaterials == g_materialManager.materials then
        return
    end

    ProBeltMaterials.sessionMaterials = g_materialManager.materials
    ProBeltMaterials.materials = {}
    ProBeltMaterials.loggedFixes = {}

    local holder = ProBeltMaterials.holderNode
    if holder ~= nil and entityExists(holder) and getName(holder) == "proBeltMaterialHolder" then
        delete(holder)
    end
    ProBeltMaterials.holderNode = nil
end

--- Puts the material on a hidden shape so the engine does not free it.
function ProBeltMaterials.keepMaterial(vehicle, materialId)
    if ProBeltMaterials.holderNode == nil or not entityExists(ProBeltMaterials.holderNode) then
        ProBeltMaterials.holderNode = createTransformGroup("proBeltMaterialHolder")
        link(getRootNode(), ProBeltMaterials.holderNode)
        setVisibility(ProBeltMaterials.holderNode, false)
    end

    local template = findShape(vehicle.rootNode, true) or findShape(vehicle.rootNode, false)
    if template == nil then
        Logging.warning("ProBeltMaterials: no shape found on '%s' to hold the belt materials", tostring(vehicle.configFileName))
        return false
    end

    local shape = clone(template, false, false, false)
    link(ProBeltMaterials.holderNode, shape)
    -- fallback template had children: drop the copied subtree, only the shape itself is needed
    for i = getNumOfChildren(shape) - 1, 0, -1 do
        delete(getChildAt(shape, i))
    end
    setMaterial(shape, materialId, 0)
    return true
end

function ProBeltMaterials.addMaterial(vehicle, fillTypeIndex, materialType, diffuse, normal, specular)
    ProBeltMaterials.checkSession()
    local index = ProBeltMaterials.MATERIAL_INDEX
    -- already registered: by us for an earlier vehicle, or by the game / another mod
    if diffuse == nil or g_materialManager:getMaterial(fillTypeIndex, materialType, index) ~= nil then
        return
    end

    local materialId
    for _, donorName in ipairs(ProBeltMaterials.DONOR_FILL_TYPES) do
        local donorIndex = g_fillTypeManager:getFillTypeIndexByName(donorName)
        materialId = g_materialManager:getMaterial(donorIndex, materialType, index)
        if materialId ~= nil then
            break
        end
    end

    if materialId == nil then
        Logging.warning("ProBeltMaterials: no base game '%s' material found to clone", materialType)
        return
    end

    materialId = setMaterialDiffuseMapFromFile(materialId, diffuse, true, true, false)
    if normal ~= nil then
        materialId = setMaterialNormalMapFromFile(materialId, normal, true, false, false)
    end
    if specular ~= nil then
        materialId = setMaterialGlossMapFromFile(materialId, specular, true, false, false)
    end

    if not ProBeltMaterials.keepMaterial(vehicle, materialId) then
        return -- an unheld material would be freed and break the belt, so the crop keeps no material
    end

    g_materialManager:addMaterial(fillTypeIndex, g_materialManager:getMaterialTypeByName(materialType), index, materialId)

    if ProBeltMaterials.materials[fillTypeIndex] == nil then
        ProBeltMaterials.materials[fillTypeIndex] = {}
    end
    ProBeltMaterials.materials[fillTypeIndex][materialType] = materialId

    Logging.info("ProBeltMaterials: registered %s belt material for %s (%s)", materialType,
        tostring(g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)), diffuse)
end

--- Puts the registered crop material on a belt effect's mesh if it doesn't carry it already.
function ProBeltMaterials.applyToEffect(effect, fillType)
    ProBeltMaterials.checkSession()
    local materials = ProBeltMaterials.materials[fillType]
    if materials == nil or effect.materialType == nil or effect.node == nil or not entityExists(effect.node) then
        return false
    end

    local materialType = string.upper(tostring(effect.materialType))
    local materialId = materials[materialType]
    if materialId == nil then
        return false
    end

    if getMaterial(effect.node, 0) ~= materialId then
        setMaterial(effect.node, materialId, 0)

        local logKey = tostring(fillType) .. materialType
        if not ProBeltMaterials.loggedFixes[logKey] then
            ProBeltMaterials.loggedFixes[logKey] = true
            Logging.info("ProBeltMaterials: put the %s %s material on belt effect '%s'",
                tostring(g_fillTypeManager:getFillTypeNameByIndex(fillType)), materialType, getName(effect.node))
        end
    end

    return true
end

-- FS25 hands the crop to an effect with setEffectTypeInfo (FS22: setFillType)
if MorphPositionEffect ~= nil and MorphPositionEffect.setEffectTypeInfo ~= nil then
    MorphPositionEffect.setEffectTypeInfo = Utils.overwrittenFunction(MorphPositionEffect.setEffectTypeInfo, function(self, superFunc, fillType, ...)
        local success = superFunc(self, fillType, ...)
        if ProBeltMaterials.applyToEffect(self, fillType) then
            return true
        end

        return success
    end)
else
    Logging.warning("ProBeltMaterials: MorphPositionEffect.setEffectTypeInfo not found, belt safety net not installed")
end
