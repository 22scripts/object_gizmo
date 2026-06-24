local model = `prop_mp_cone_02`
RegisterCommand('testGizmo', function()
    local offset = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 3
    lib.requestModel(model)
    local obj = CreateObject(model, offset.x, offset.y, offset.z, false, false, false)
    local data = exports[GetCurrentResourceName()]:useGizmo(obj)


    if data.result == 'cancel' and DoesEntityExist(obj) then
        DeleteEntity(obj)
    end
    lib.print.info(data)
end)

