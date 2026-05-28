local model = `prop_mp_cone_02`

RegisterCommand('testGizmo', function()
    local offset = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 3.0
    lib.requestModel(model)
    local obj = CreateObject(model, offset.x, offset.y, offset.z, false, false, false)

    local data = exports[GetCurrentResourceName()]:useGizmo(obj, {
        lockEntity = true,
        title = 'Test FGizmo',
        allowFreecam = true,
        onDuplicate = function(ent)
            local coords = GetEntityCoords(ent)
            local rot = GetEntityRotation(ent, 2)
            local copy = CreateObject(GetEntityModel(ent), coords.x + 1.0, coords.y, coords.z, false, false, false)
            SetEntityRotation(copy, rot.x, rot.y, rot.z, 2, true)
            lib.notify({ title = 'FGizmo', description = 'Duplicate callback', type = 'inform' })
            return copy
        end,
        onDelete = function(ent)
            DeleteEntity(ent)
            lib.notify({ title = 'FGizmo', description = 'Delete callback', type = 'inform' })
            return true
        end,
    })

    if data.result == 'cancel' and DoesEntityExist(obj) then
        DeleteEntity(obj)
    end

    lib.print.info(data)
end)
