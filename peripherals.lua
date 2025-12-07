-- peripherals.lua
local M = {}

function M.getPeripheral(name)
    if type(name) ~= "string" then
        return nil, "peripheral name must be a string"
    end

    if peripheral.isPresent(name) then
        return peripheral.wrap(name), nil
    else
        return nil, "peripheral '" .. name .. "' not found"
    end
end

function M.getPeripheralByType(typeName)
    if type(typeName) ~= "string" then
        return nil, "peripheral type must be a string"
    end

    local periph = peripheral.find(typeName)
    if periph then
        return periph, nil
    else
        return nil, "no peripheral of type '" .. typeName .. "' found"
    end
end

return M   -- REQUIRED
