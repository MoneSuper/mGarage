local VehicleTypes = {
    ['car'] = { 'automobile', 'bicycle', 'bike', 'quadbike', 'trailer', 'amphibious_quadbike', 'amphibious_automobile' },
    ['boat'] = { 'submarine', 'submarinecar', 'boat' },
    ['air'] = { 'blimp', 'heli', 'plane' },
}

local SpawnClearArea = function(data)
    local player = GetPlayerPed(data.player)
    local playerpos = GetEntityCoords(player)
    local selectedCoords, isClear = nil, false

    if #data.coords == 1 then
        local v = data.coords[1]
        return { coords = vec4(v.x, v.y, v.z, v.w), clear = true }
    end

    for attempt = 1, 5 do
        for _, v in ipairs(data.coords) do
            local spawnPos = vector3(v.x, v.y, v.z)
            local distanceToPlayer = #(playerpos - spawnPos)

            if distanceToPlayer < (selectedCoords and #(playerpos - vector3(selectedCoords.x, selectedCoords.y, selectedCoords.z)) or math.huge) then
                local clearOfVehicles = true
                for _, vehicle in pairs(GetAllVehicles()) do
                    if #(spawnPos - GetEntityCoords(vehicle)) <= data.distance then
                        clearOfVehicles = false
                        break
                    end
                end

                if clearOfVehicles and distanceToPlayer > 2 then
                    selectedCoords, isClear = vec4(v.x, v.y, v.z, v.w), true
                end
            end
        end

        if selectedCoords then break end
    end

    return { coords = selectedCoords, clear = isClear }
end




lib.callback.register('mGarage:Interact', function(source, action, data, vehicle)
    local retval = nil

    local Player = Core.Player(source)

    if action == 'get' then
        local vehicles = {}

        local PlyVehicles = Vehicles.GetAllVehicles(source, false, true)

        if PlyVehicles then
            for i = 1, #PlyVehicles do
                local row = PlyVehicles[i]
                row.isOwner = row.owner == Player.identifier() or row.license == Player.identifier()
                if data.garagetype == 'garage' and not row.pound or not row.pound == 0 then
                    if not row.job == data.job then
                        break
                    end
                    if data.isShared then
                        table.insert(vehicles, row)
                    else
                        if data.name == row.parking then
                            if type(data.carType) == 'table' or VehicleTypes[row.type] then
                                if VehicleTypes[row.type] then
                                    for _, carType in ipairs(data.carType) do
                                        if lib.table.contains(VehicleTypes[row.type], carType) then
                                            table.insert(vehicles, row)
                                            break
                                        end
                                    end
                                else
                                    if lib.table.contains(data.carType, row.type) then
                                        table.insert(vehicles, row)
                                    end
                                end
                            elseif data.carType == row.type or lib.table.contains(VehicleTypes[row.type], data.carType) then
                                table.insert(vehicles, row)
                            end
                        end
                    end
                elseif data.garagetype == 'impound' then
                    if data.isShared then
                        table.insert(vehicles, row)
                    else
                        if data.name == row.parking then
                            if type(data.carType) == 'table' or VehicleTypes[row.type] then
                                if VehicleTypes[row.type] then
                                    for _, carType in ipairs(data.carType) do
                                        if lib.table.contains(VehicleTypes[row.type], carType) then
                                            table.insert(vehicles, row)
                                            break
                                        end
                                    end
                                else
                                    if lib.table.contains(data.carType, row.type) then
                                        table.insert(vehicles, row)
                                    end
                                end
                            elseif data.carType == row.type or lib.table.contains(VehicleTypes[row.type], data.carType) then
                                table.insert(vehicles, row)
                            end
                        end
                    end
                end
            end
        end

        retval = { vehicles = vehicles, job = Player.GetJob() }
    elseif action == 'spawn' then
        local vehicle = Vehicles.GetVehicleId(data.vehicleid)

        if vehicle then
            local coords = SpawnClearArea({
                coords = data.garage.spawnpos,
                distance = 2.0,
                player = source
            })

            if not coords.clear then
                Player.Notify({
                    title = data.name,
                    description = 'No Spawn Point',
                    type = 'error',
                })
                return false
            end

            vehicle.coords = coords.coords

            vehicle.vehicle = json.decode(vehicle.vehicle)
            if data.garage.intocar then
                vehicle.intocar = source
            end

            local vehicledata, action = Vehicles.CreateVehicle(vehicle)

            if not action then return false end

            action.RetryVehicle(coords.coords)

            if Config.CarkeysItem then
                Vehicles.ItemCarKeys(source, 'add', vehicle.plate)
            end
            retval = true
        end
    elseif action == 'saveCar' then
        local entity = NetworkGetEntityFromNetworkId(data.entity)
        local Vehicle = Vehicles.GetVehicle(entity)
        local VehicleType = GetVehicleType(entity)

        if type(data.carType) == 'table' then
            if not lib.table.contains(data.carType, VehicleType) then
                return false
            end
        elseif data.carType == VehicleType then
            return false
        end

        if Vehicle then
            local metadata = Vehicle.GetMetadata('customGarage')
            if metadata then
                if Config.CarkeysItem then
                    Vehicles.ItemCarKeys(source, 'delete', Vehicle.plate)
                end
                return Vehicle.DeleteVehicle(false)
            end
            if type(Vehicle.keys) == 'string' then
                Vehicle.keys = json.decode(Vehicle.keys)
            end

            if data.job then
                if not (data.job == Vehicle.job) then
                    return false
                end
            end
            if Vehicle.owner == Player.identifier() or Vehicle.keys[Player.identifier()] then
                if Config.CarkeysItem then
                    Vehicles.ItemCarKeys(source, 'delete', Vehicle.plate)
                end
                return Vehicle.StoreVehicle(data.name, data.props)
            else
                Player.Notify({
                    title = data.name,
                    description = Text[Config.Lang].notYourVehicle,
                    type = 'error',
                })
            end
        else
            local row = MySQL.single.await(Querys.queryStore1, { data.plate })

            if not row then
                return false,

                    Player.Notify({
                        title = data.name,
                        description = Text[Config.Lang].notYourVehicle,
                        type = 'error',
                    })
            end

            if data.job then
                if not (data.job == row.job) then
                    return false
                end
            end

            if row and row.owner == Player.identifier() or row.keys and row.keys[Player.identifier()] then
                MySQL.update(Querys.queryStore2, { data.name, json.encode(data.props), VehicleType, data.plate },
                    function(affectedRows)
                        if affectedRows then
                            DeleteEntity(entity)
                            if Config.CarkeysItem then
                                Vehicles.ItemCarKeys(source, 'remove', data.plate)
                            end
                        end
                    end)
            else
                Player.Notify({
                    title = data.name,
                    description = Text[Config.Lang].notYourVehicle,
                    type = 'error',
                })
            end
        end
    elseif action == 'setimpound' then
        local composed = nil
        if data.hourEndPound and data.dateEndPound then
            local timestamphour = math.floor(data.hourEndPound / 1000)
            local hour = os.date('%H:%M', timestamphour)
            local timestamp = math.floor(data.dateEndPound / 1000)
            local date = os.date('%Y/%m/%d', timestamp)
            composed = ('%s %s'):format(date, hour)
        end
        local infoimpound = {
            reason = data.reason,
            price = data.price,
            impoundDate = os.date("%Y/%m/%d %H:%M:%S", os.time()),
            endPound = composed
        }

        local entity = NetworkGetEntityFromNetworkId(data.entity)
        local Vehicle = Vehicles.GetVehicle(entity)
        if Vehicle then
            Vehicle.ImpoundVehicle(data.garage, infoimpound.price, infoimpound.reason, infoimpound.time,
                infoimpound.endPound)
        else
            DeleteEntity(entity)
        end
    elseif action == 'impound' then
        local vehicle = Vehicles.GetVehicleId(data.vehicleid)
        if vehicle then
            local metadata = json.decode(vehicle.metadata)
            local infoimpound = metadata.pound
            local PlayerMoney = Player.getMoney(data.paymentMethod)
            if infoimpound.endPound then
                local year, month, day, hour, min = infoimpound.endPound:match("(%d+)/(%d+)/(%d+) (%d+):(%d+)")

                if year and month and day and hour and min then
                    local endPoundDate = os.time({
                        year = year,
                        month = month,
                        day = day,
                        hour = hour,
                        min = min
                    })

                    local currentDate = os.time()
                    if currentDate < endPoundDate then
                        local timeDifference = endPoundDate - currentDate
                        local days = math.floor(timeDifference / (24 * 60 * 60))
                        local hours = math.floor((timeDifference % (24 * 60 * 60)) / (60 * 60))
                        local minutes = math.floor((timeDifference % (60 * 60)) / 60)
                        Player.Notify({
                            title = data.garage.name,
                            description = (Text[Config.Lang].ImpoundOption13):format(days, hours, minutes),
                            type = 'error',
                        })
                        return false
                    end
                end
            end


            if PlayerMoney.money >= infoimpound.price then
                local coords = SpawnClearArea({ coords = data.garage.spawnpos, distance = 2.0, player = source })

                if coords.clear then
                    vehicle.coords = coords.coords
                    Player.RemoveMoney(data.paymentMethod, infoimpound.price)
                    vehicle.vehicle = json.decode(vehicle.vehicle)
                    local entity, action = Vehicles.CreateVehicle(vehicle)
                    action.RetryImpound(data.garage.defaultGarage, vehicle.coords)

                    if Config.CarkeysItem then
                        Vehicles.ItemCarKeys(source, 'add', vehicle.plate)
                    end

                    if data.garage.society then
                        Core.SetSotcietyMoney(data.garage.society, infoimpound.price)
                    end
                    Player.Notify({
                        title = data.garage.name,
                        description = (Text[Config.Lang].impound1):format(infoimpound.price),
                        type = 'success',
                    })
                    retval = true
                else
                    Player.Notify({
                        title = data.garage.name,
                        description = Text[Config.Lang].noSpawnPos,
                        type = 'warning',
                    })
                    retval = false
                end
            else
                Player.Notify({
                    title = data.garage.name,
                    description = Text[Config.Lang].impound2,
                    type = 'warning',
                })
                retval = false
            end
        end
    elseif action == 'changeimpound' then
        local vehicle = Vehicles.GetVehicleByPlateDB(data)
        if vehicle then
            local metadata = json.decode(vehicle.metadata)
            if metadata.pound then
                if metadata.pound.endPound then
                    metadata.pound.endPound = nil
                    MySQL.update('UPDATE owned_vehicles SET metadata = ? WHERE plate = ?', {
                        json.encode(metadata), data
                    })
                    retval = true
                    Player.Notify({
                        title = 'Garage Unpound',
                        description = Text[Config.Lang].ImpoundOption11,
                        type = 'success',
                    })
                else
                    Player.Notify({
                        title = 'Garage Unpound',
                        description = Text[Config.Lang].ImpoundOption8,
                        type = 'error',
                    })
                    retval = false
                end
            else
                Player.Notify({
                    title = 'Garage Unpound',
                    description = Text[Config.Lang].ImpoundOption9,
                    type = 'error',
                })
                retval = false
            end
        else
            Player.Notify({
                title = 'Garage Unpound',
                description = (Text[Config.Lang].ImpoundOption10):format(data),
                type = 'error',
            })
            retval = false
        end
    elseif action == 'setBlip' then
        local vehicle = Vehicles.GetVehicleByPlate(data.plate)
        if vehicle then
            retval = GetEntityCoords(vehicle.entity)
        end
    elseif action == 'spawncustom' then
        local model = data.vehicle.model
        local garageName = data.garage.name

        local job = (data.garage.job == false) and nil or data.garage.job

        local plate = Vehicles.GeneratePlate()

        local platePrefix = data.garage.platePrefix

        if platePrefix and #platePrefix > 0 then
            if #platePrefix < 4 then
                platePrefix = string.format("%-4s", platePrefix)
            end
            plate = platePrefix:upper() .. string.sub(plate, 5)
        end



        local coords = SpawnClearArea({
            coords = data.garage.spawnpos,
            distance = 2.0,
            player = source
        })

        if not coords.clear then
            Player.Notify({
                title = data.name,
                description = 'No Spawn Point',
                type = 'error',
            })
            return false
        end

        local CreateVehicleData = {
            temporary = false,
            job = job,
            setOwner = false,
            intocar = data.garage.intocar and source,
            owner = Player.identifier(),
            coords = coords.coords,
            vehicle = {
                model = model,
                plate = plate,
                fuelLevel = 100,
            },
        }

        Vehicles.CreateVehicle(CreateVehicleData, function(data, Vehicle)
            if Config.CarkeysItem then
                Vehicles.ItemCarKeys(source, 'add', Vehicle.plate)
            else
                Vehicle.AddKey(source)
            end
            Vehicle.SetMetadata('customGarage', garageName)
        end)

        return true
    elseif action == 'saveCustomCar' then
        local entity = NetworkGetEntityFromNetworkId(data.entity)
        local Vehicle = Vehicles.GetVehicle(entity)
        if Vehicle then
            local metadata = Vehicle.GetMetadata('customGarage')
            local job = Player.GetJob()

            if metadata == data.name and Vehicle.owner == Player.identifier() or job.name == Vehicle.job then
                Vehicle.DeleteVehicle(false)
                if Config.CarkeysItem then
                    Vehicles.ItemCarKeys(source, 'delete', Vehicle.plate)
                end
                retval = true
            else
                retval = false
            end
        else
            retval = false
        end
    end
    return retval
end)




RegisterServerEvent('mGarage:Server:TaskLeaveVehicle', function(peds)
    for k, v in pairs(peds) do
        TriggerClientEvent('mGarage:Client:TaskLeaveVehicle', v)
    end
end)
