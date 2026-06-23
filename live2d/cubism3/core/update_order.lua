-- Model update order for Cubism 3
-- Ported from Mocari src/core/update_order.rs

local update_order = {}

-- ModelUpdateStep enum
local steps = {
    "PreUpdateDynamicFlags",
    "UpdateParameters",
    "UpdateParameterBindings",
    "UpdateBlendShapeParameterBindings",
    "UpdateKeyformBindings",
    "UpdateBlendShapeKeyformBindings",
    "ClampBlendShapeWeights",
    "UpdatePartsHierarchy",
    "UpdatePartKeyformCaches",
    "InterpolateParts",
    "UpdateDeformerHierarchy",
    "UpdateWarpDeformerKeyformCaches",
    "UpdateRotationDeformerKeyformCaches",
    "InterpolateWarpDeformers",
    "InterpolateRotationDeformers",
    "UpdateArtMeshHierarchy",
    "UpdateArtMeshKeyformCaches",
    "InterpolateArtMeshes",
    "UpdateGlueKeyformCaches",
    "InterpolateGlues",
    "UpdateOffscreenRenderingHierarchy",
    "UpdateOffscreenRenderingKeyformCaches",
    "InterpolateOffscreenRendering",
    "BlendParts",
    "BlendWarpDeformers",
    "BlendRotationDeformers",
    "BlendArtMeshes",
    "BlendGlues",
    "BlendOffscreenRendering",
    "TransformDeformers",
    "DeformerTransformArtMeshes",
    "TransformParts",
    "PartTransformArtMeshes",
    "AffectArtMeshes",
    "ReverseCoordinate",
    "CalculateRenderOrder",
    "PostUpdateDynamicFlags",
}

for i, name in ipairs(steps) do
    update_order[name] = i - 1 -- 0-indexed
end

update_order.SEMANTIC_ORDER = steps

function update_order.semantic_model_update_order()
    return steps
end

function update_order.should_affect_glues(glue_count)
    return glue_count > 0
end

function update_order.should_blend_glues(moc_version)
    return moc_version > 4
end

function update_order.should_run_offscreen_stage(moc_version)
    return moc_version > 5
end

return update_order
