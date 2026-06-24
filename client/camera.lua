LF_GizmoCamera = LF_GizmoCamera or {}

local Camera = LF_GizmoCamera

local state = {
    active = false,
    cam = nil,
    speed = 1.0,
    baseSpeed = 0.11,
    mouseSensitivity = 5.0,
    minSpeed = 0.2,
    maxSpeed = 8.0,
    radius = 15.0,
    anchor = nil
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function vecLen(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function normalize(v)
    local l = vecLen(v)
    if l < 0.0001 then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(v.x / l, v.y / l, v.z / l)
end

local function getCamCoords()
    if not state.cam or not DoesCamExist(state.cam) then return nil end
    return GetCamCoord(state.cam)
end

function Camera.IsActive()
    return state.active and state.cam and DoesCamExist(state.cam) or false
end

function Camera.GetCoord()
    local c = getCamCoords()
    if c then return c end
    return GetGameplayCamCoord()
end

function Camera.GetRot()
    if Camera.IsActive() then
        return GetCamRot(state.cam, 2)
    end
    return GetGameplayCamRot(2)
end

function Camera.GetFov()
    if Camera.IsActive() then
        return GetCamFov(state.cam)
    end
    return GetGameplayCamFov()
end


function Camera.WorldToScreen(worldPos)
    if not Camera.IsActive() then return nil end

    local camPos = GetCamCoord(state.cam)
    local camRot = GetCamRot(state.cam, 2)
    local fov    = GetCamFov(state.cam)
    local aspect = GetAspectRatio(false)

    local yaw   = math.rad(camRot.z)
    local pitch = math.rad(camRot.x)

    local fx = -math.sin(yaw) * math.cos(pitch)
    local fy =  math.cos(yaw) * math.cos(pitch)
    local fz =  math.sin(pitch)


    local rx, ry = fy, -fx
    local rlen = math.sqrt(rx * rx + ry * ry)
    if rlen < 0.0001 then rx, ry = 1.0, 0.0 else rx, ry = rx / rlen, ry / rlen end
    local rz = 0.0


    local ux = ry * fz - rz * fy
    local uy = rz * fx - rx * fz
    local uz = rx * fy - ry * fx
    local ulen = math.sqrt(ux * ux + uy * uy + uz * uz)
    if ulen > 0.0001 then ux, uy, uz = ux / ulen, uy / ulen, uz / ulen end

    local dx = worldPos.x - camPos.x
    local dy = worldPos.y - camPos.y
    local dz = worldPos.z - camPos.z

    local camX = dx * rx + dy * ry + dz * rz
    local camY = dx * ux + dy * uy + dz * uz
    local camZ = dx * fx + dy * fy + dz * fz

    if camZ <= 0.001 then return nil end

    local tanHalfV = math.tan(math.rad(fov * 0.5))
    local tanHalfH = tanHalfV * aspect

    local ndcX = camX / (camZ * tanHalfH)
    local ndcY = camY / (camZ * tanHalfV)

    local sx = 0.5 + ndcX * 0.5
    local sy = 0.5 - ndcY * 0.5

    if sx < -0.2 or sx > 1.2 or sy < -0.2 or sy > 1.2 then return nil end
    return { x = sx, y = sy }
end

function Camera.GetSpeed()
    return state.speed
end

function Camera.ResetSpeed()
    state.speed = 1.0
end

function Camera.AdjustSpeed(delta)
    state.speed = clamp(state.speed - delta * 0.0025, state.minSpeed, state.maxSpeed)
end

function Camera.Start(anchorCoords)
    if Camera.IsActive() then return true end

    state.anchor = anchorCoords or GetEntityCoords(PlayerPedId())
    local gameplayCamPos = GetGameplayCamCoord()
    local gameplayCamRot = GetGameplayCamRot(2)

    state.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    if not state.cam or not DoesCamExist(state.cam) then
        state.cam = nil
        return false
    end

    SetCamCoord(state.cam, gameplayCamPos.x, gameplayCamPos.y, gameplayCamPos.z)
    SetCamRot(state.cam, gameplayCamRot.x, gameplayCamRot.y, gameplayCamRot.z, 2)
    SetCamFov(state.cam, GetGameplayCamFov())
    SetCamActive(state.cam, true)
    RenderScriptCams(true, false, 0, true, true)

    state.active = true
    return true
end

function Camera.Stop()
    if state.cam and DoesCamExist(state.cam) then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(state.cam, false)
    end
    state.cam = nil
    state.active = false
    state.speed = 1.0
    state.anchor = nil
end

function Camera.Update()
    if not Camera.IsActive() then return end

    local camCoords = GetCamCoord(state.cam)
    local camRot = GetCamRot(state.cam, 2)

    local mouseX = GetDisabledControlNormal(0, 1) * state.mouseSensitivity
    local mouseY = GetDisabledControlNormal(0, 2) * state.mouseSensitivity

    local newRotX = clamp(camRot.x - mouseY, -89.0, 89.0)
    local newRotZ = camRot.z - mouseX

    SetCamRot(state.cam, newRotX, 0.0, newRotZ, 2)

    local moveSpeed = state.baseSpeed * state.speed
    local yaw = math.rad(newRotZ)
    local pitch = math.rad(newRotX)

    local forward = normalize(vector3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch)
    ))
    local right = normalize(vector3(
        -math.sin(yaw + math.pi / 2.0),
        math.cos(yaw + math.pi / 2.0),
        0.0
    ))

    local nextPos = vector3(camCoords.x, camCoords.y, camCoords.z)

    if IsDisabledControlPressed(0, 32) then
        nextPos = vector3(nextPos.x + forward.x * moveSpeed, nextPos.y + forward.y * moveSpeed, nextPos.z + forward.z * moveSpeed)
    end
    if IsDisabledControlPressed(0, 33) then
        nextPos = vector3(nextPos.x - forward.x * moveSpeed, nextPos.y - forward.y * moveSpeed, nextPos.z - forward.z * moveSpeed)
    end
    if IsDisabledControlPressed(0, 34) then
        nextPos = vector3(nextPos.x + right.x * moveSpeed, nextPos.y + right.y * moveSpeed, nextPos.z)
    end
    if IsDisabledControlPressed(0, 35) then
        nextPos = vector3(nextPos.x - right.x * moveSpeed, nextPos.y - right.y * moveSpeed, nextPos.z)
    end

    if IsDisabledControlPressed(0, 44) then
        nextPos = vector3(nextPos.x, nextPos.y, nextPos.z + moveSpeed)
    end
    if IsDisabledControlPressed(0, 38) then
        nextPos = vector3(nextPos.x, nextPos.y, nextPos.z - moveSpeed)
    end

    if state.anchor then
        local offset = vector3(nextPos.x - state.anchor.x, nextPos.y - state.anchor.y, nextPos.z - state.anchor.z)
        local d = vecLen(offset)
        if d > state.radius then
            local n = normalize(offset)
            nextPos = vector3(
                state.anchor.x + n.x * state.radius,
                state.anchor.y + n.y * state.radius,
                state.anchor.z + n.z * state.radius
            )
        end
    end

    SetCamCoord(state.cam, nextPos.x, nextPos.y, nextPos.z)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Camera.Stop()
end)

