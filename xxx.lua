local chest1 = peripheral.wrap("create:item_vault_1")
local chest2 = peripheral.wrap("minecraft:barrel_0")

-- Переместить из chest1 в chest2 (из 1-го слота, до 128 штук)
while true do
    chest1.pushItems(peripheral.getName(chest2), 1, 128)
end
