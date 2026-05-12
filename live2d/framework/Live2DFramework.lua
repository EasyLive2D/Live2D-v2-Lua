local Live2DFramework = {}

Live2DFramework.__platformManager = nil

function Live2DFramework.getPlatformManager()
    return Live2DFramework.__platformManager
end

function Live2DFramework.setPlatformManager(platformManager)
    Live2DFramework.__platformManager = platformManager
end

return Live2DFramework
