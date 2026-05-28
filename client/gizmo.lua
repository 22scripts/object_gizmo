lib.locale()

local DEBUG_CONVAR = 'fgizmo:debugPlacement'

local function dbgPlacement(message)
    if GetConvarInt(DEBUG_CONVAR, 0) ~= 1 then return end
    print(('[FGizmo] %s'):format(message))
end

local CONFIG = {
    axisLength = 0.7,
    planeFracMin = 0.10,
    planeFracMax = 0.50,
    ringRadius = 0.65,
    pickAxisThreshold = 0.018,
    pickPlaneEdgeThreshold = 0.012,
    pickRingThreshold = 0.016
}

local COLORS = {
    x = { r = 220, g = 40, b = 40 },
    y = { r = 40, g = 100, b = 220 },
    z = { r = 40, g = 200, b = 70 },
    plane_xy = { r = 0, g = 210, b = 210 },
    plane_xz = { r = 210, g = 0, b = 210 },
    plane_yz = { r = 210, g = 210, b = 0 },
    selected = { r = 255, g = 255, b = 255 }
}

local RATIO_MIN, RATIO_MAX, RATIO_DEFAULT = 0.05, 5.0, 1.0
local RATIO_SCROLL_FACTOR = 0.001

local GIZMO_KEYS = {
    toggle = 45,
    freecam = 23,
    hideCursor = 47,
    cancel = 177,
    confirm = 191,
    ratio = 14,
    snap = 21,
    duplicate = 26,
    delete = 214
}

local state = {
    active = false,
    entity = 0,
    mode = 'translate',
    view = 'gizmo',
    cursorHidden = false,
    result = 'cancel',
    hovered = nil,
    dragging = nil,
    initialPos = nil,
    initialRot = nil,
    ratio = RATIO_DEFAULT,
    modifiedEntities = {},
    initialStates = {},
    lockEntity = true,
    entityFilter = nil,
    allowedEntities = nil,
    onDuplicate = nil,
    onDelete = nil,
    title = nil,
    allowFreecam = true
}

local gizmoScaleform = nil
local switchEntity

local mouse = {
    x = 0.5,
    y = 0.5,
    down = false,
    justPressed = false,
    justReleased = false
}

local function cameraIsActive()
    return LF_GizmoCamera and LF_GizmoCamera.IsActive and LF_GizmoCamera.IsActive()
end

local function getActiveCamCoord()
    if cameraIsActive() and LF_GizmoCamera.GetCoord then
        return LF_GizmoCamera.GetCoord()
    end
    return GetGameplayCamCoord()
end

local function getActiveCamRot()
    if cameraIsActive() and LF_GizmoCamera.GetRot then
        return LF_GizmoCamera.GetRot()
    end
    return GetGameplayCamRot(2)
end

local function v3(x, y, z)
    return vector3(x + 0.0, y + 0.0, z + 0.0)
end

local function add(a, b)
    return v3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function sub(a, b)
    return v3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function mul(a, s)
    return v3(a.x * s, a.y * s, a.z * s)
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return v3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function length(v)
    return math.sqrt(dot(v, v))
end

local function normalize(v)
    local len = length(v)
    if len <= 0.00001 then
        return v3(0.0, 0.0, 0.0)
    end
    return mul(v, 1.0 / len)
end

local function clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function normalizeDegrees360(value)
    value = (value % 360.0) + 0.0
    if value < 0.0 then value = value + 360.0 end
    return value
end

local function rotationForDisplay(rx, ry, rz)
    return normalizeDegrees360(rx), normalizeDegrees360(ry), normalizeDegrees360(rz)
end

local function quatNew(x, y, z, w)
    return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 1.0 }
end

local function quatFromAxisAngle(axis, angleRad)
    local len = length(axis)
    if len < 0.00001 then return quatNew(0.0, 0.0, 0.0, 1.0) end
    local invLen = 1.0 / len
    local nx, ny, nz = axis.x * invLen, axis.y * invLen, axis.z * invLen
    local half = angleRad * 0.5
    local s = math.sin(half)
    return quatNew(nx * s, ny * s, nz * s, math.cos(half))
end

local function quatMul(a, b)
    return quatNew(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    )
end

local function quatNormalize(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 0.00001 then return quatNew(0.0, 0.0, 0.0, 1.0) end
    local inv = 1.0 / n
    return quatNew(q.x * inv, q.y * inv, q.z * inv, q.w * inv)
end

local function quatToBasisStd(q)
    local x, y, z, w = q.x, q.y, q.z, q.w
    local x2, y2, z2 = x + x, y + y, z + z
    local xx, yy, zz = x * x2, y * y2, z * z2
    local xy, xz, yz = x * y2, x * z2, y * z2
    local wx, wy, wz = w * x2, w * y2, w * z2
    local right = v3(1.0 - (yy + zz), xy + wz, xz - wy)
    local forward = v3(xy - wz, 1.0 - (xx + zz), yz + wx)
    local up = v3(xz + wy, yz - wx, 1.0 - (xx + yy))
    return forward, right, up
end

local function rotationToBasis(rotX, rotY, rotZ)
    local yaw = math.rad(rotZ)
    local pitch = math.rad(rotX)
    local roll = math.rad(rotY)

    local forward = normalize(v3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch)
    ))
    local right = normalize(cross(forward, v3(0.0, 0.0, 1.0)))
    if length(right) < 0.0001 then right = v3(1.0, 0.0, 0.0) end
    local up = normalize(cross(right, forward))

    local cr, sr = math.cos(roll), math.sin(roll)
    local rightRolled = v3(right.x * cr + up.x * sr, right.y * cr + up.y * sr, right.z * cr + up.z * sr)
    local upRolled = v3(-right.x * sr + up.x * cr, -right.y * sr + up.y * cr, -right.z * sr + up.z * cr)
    return forward, normalize(rightRolled), normalize(upRolled)
end

local function basisToQuat(forward, right, up)
    local m11, m12, m13 = right.x, forward.x, up.x
    local m21, m22, m23 = right.y, forward.y, up.y
    local m31, m32, m33 = right.z, forward.z, up.z
    local trace = m11 + m22 + m33
    if trace > 0.0 then
        local s = math.sqrt(trace + 1.0) * 2.0
        return quatNew((m32 - m23) / s, (m13 - m31) / s, (m21 - m12) / s, 0.25 * s)
    elseif m11 > m22 and m11 > m33 then
        local s = math.sqrt(1.0 + m11 - m22 - m33) * 2.0
        return quatNew(0.25 * s, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s)
    elseif m22 > m33 then
        local s = math.sqrt(1.0 + m22 - m11 - m33) * 2.0
        return quatNew((m12 + m21) / s, 0.25 * s, (m23 + m32) / s, (m13 - m31) / s)
    end
    local s = math.sqrt(1.0 + m33 - m11 - m22) * 2.0
    return quatNew((m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s)
end

local function basisToEulerOrder2(forward, right)
    local fz = math.max(-1.0, math.min(1.0, forward.z))
    local pitch = math.asin(fz)
    local yaw, roll
    if math.abs(fz) > 0.99999 then
        roll = 0.0
        yaw = math.atan(-right.x, right.y)
    else
        yaw = math.atan(-forward.x, forward.y)
        local up = normalize(cross(right, forward))
        roll = math.atan(right.z, up.z)
    end
    return math.deg(pitch), math.deg(roll), math.deg(yaw)
end

local function eulerOrder2ToQuat(rxDeg, ryDeg, rzDeg)
    local fwd, right, up = rotationToBasis(rxDeg or 0.0, ryDeg or 0.0, rzDeg or 0.0)
    return basisToQuat(fwd, right, up)
end

local function quatToEulerOrder2(q)
    local fwd, right = quatToBasisStd(q)
    return basisToEulerOrder2(fwd, right)
end

local function screenDistanceToSegment(px, py, x1, y1, x2, y2)
    local vx, vy = x2 - x1, y2 - y1
    local wx, wy = px - x1, py - y1
    local lenSq = vx * vx + vy * vy
    if lenSq <= 0.0000001 then
        local dx, dy = px - x1, py - y1
        return math.sqrt(dx * dx + dy * dy), 0.0
    end
    local t = (wx * vx + wy * vy) / lenSq
    if t < 0.0 then t = 0.0 end
    if t > 1.0 then t = 1.0 end
    local projX, projY = x1 + vx * t, y1 + vy * t
    local dx, dy = px - projX, py - projY
    return math.sqrt(dx * dx + dy * dy), t
end

local function pointInTriangle(px, py, ax, ay, bx, by, cx, cy)
    local v0x, v0y = cx - ax, cy - ay
    local v1x, v1y = bx - ax, by - ay
    local v2x, v2y = px - ax, py - ay
    local dot00 = v0x * v0x + v0y * v0y
    local dot01 = v0x * v1x + v0y * v1y
    local dot02 = v0x * v2x + v0y * v2y
    local dot11 = v1x * v1x + v1y * v1y
    local dot12 = v1x * v2x + v1y * v2y
    local invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01)
    local u = (dot11 * dot02 - dot01 * dot12) * invDenom
    local v = (dot00 * dot12 - dot01 * dot02) * invDenom
    return (u >= 0.0) and (v >= 0.0) and (u + v < 1.0)
end

local function pointInQuad(px, py, p1, p2, p3, p4)
    return pointInTriangle(px, py, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y)
        or pointInTriangle(px, py, p1.x, p1.y, p3.x, p3.y, p4.x, p4.y)
end

local function toScreen(worldPos)
    if cameraIsActive() and LF_GizmoCamera.WorldToScreen then
        return LF_GizmoCamera.WorldToScreen(worldPos)
    end
    local ok, sx, sy = GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
    if not ok then return nil end
    return { x = sx, y = sy }
end

local function getCamRay()
    local rot = getActiveCamRot()
    local fov = (LF_GizmoCamera and LF_GizmoCamera.GetFov and LF_GizmoCamera.GetFov()) or GetGameplayCamFov()
    local aspect = GetAspectRatio(false)
    local pitch = math.rad(rot.x)
    local yaw = math.rad(rot.z)
    local forward = normalize(v3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch)
    ))
    local right = normalize(cross(forward, v3(0.0, 0.0, 1.0)))
    if length(right) < 0.0001 then right = v3(1.0, 0.0, 0.0) end
    local up = normalize(cross(right, forward))
    local nx = (mouse.x - 0.5) * 2.0
    local ny = -((mouse.y - 0.5) * 2.0)
    local tanHalfV = math.tan(math.rad(fov * 0.5))
    local tanHalfH = tanHalfV * aspect
    local rayDir = normalize(add(add(forward, mul(right, nx * tanHalfH)), mul(up, ny * tanHalfV)))
    return getActiveCamCoord(), rayDir
end

local function rayPlaneIntersect(rayOrigin, rayDir, planePoint, planeNormal)
    local denom = dot(rayDir, planeNormal)
    if math.abs(denom) < 0.00001 then return nil end
    local t = dot(sub(planePoint, rayOrigin), planeNormal) / denom
    if t < 0.01 then return nil end
    return add(rayOrigin, mul(rayDir, t))
end

local function getAxes(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return { x = v3(1.0, 0.0, 0.0), y = v3(0.0, 1.0, 0.0), z = v3(0.0, 0.0, 1.0) }
    end
    local rot = GetEntityRotation(entity, 2)
    local forward, right, up = rotationToBasis(rot.x, rot.y, rot.z)
    return { x = right, y = forward, z = up }
end

local function getGizmoScale(center)
    local cam = getActiveCamCoord()
    local dist = #(center - cam)
    return math.max(0.3, dist * 0.08)
end

local function getTranslateHandles(center, axes, scale)
    local cam = getActiveCamCoord()
    local toCam = normalize(sub(cam, center))
    local sx = dot(toCam, axes.x) >= 0.0 and 1.0 or -1.0
    local sy = dot(toCam, axes.y) >= 0.0 and 1.0 or -1.0
    local sz = dot(toCam, axes.z) >= 0.0 and 1.0 or -1.0
    local len = CONFIG.axisLength * scale
    return {
        { id = 'axis_x', kind = 'axis', axis = mul(axes.x, sx), axisLength = len, color = COLORS.x },
        { id = 'axis_y', kind = 'axis', axis = mul(axes.y, sy), axisLength = len, color = COLORS.y },
        { id = 'axis_z', kind = 'axis', axis = mul(axes.z, sz), axisLength = len, color = COLORS.z },
        { id = 'plane_xy', kind = 'plane', axisA = mul(axes.x, sx), axisB = mul(axes.y, sy), axisLength = len, color = COLORS.plane_xy },
        { id = 'plane_xz', kind = 'plane', axisA = mul(axes.x, sx), axisB = mul(axes.z, sz), axisLength = len, color = COLORS.plane_xz },
        { id = 'plane_yz', kind = 'plane', axisA = mul(axes.y, sy), axisB = mul(axes.z, sz), axisLength = len, color = COLORS.plane_yz }
    }
end

local function getRotateHandles(center, axes)
    local cam = getActiveCamCoord()
    local toCam = normalize(sub(cam, center))
    local sx = dot(toCam, axes.x) >= 0.0 and 1.0 or -1.0
    local sy = dot(toCam, axes.y) >= 0.0 and 1.0 or -1.0
    local sz = dot(toCam, axes.z) >= 0.0 and 1.0 or -1.0
    return {
        { id = 'ring_x', kind = 'ring', axis = mul(axes.x, sx), color = COLORS.x },
        { id = 'ring_y', kind = 'ring', axis = mul(axes.y, sy), color = COLORS.y },
        { id = 'ring_z', kind = 'ring', axis = mul(axes.z, sz), color = COLORS.z }
    }
end

local function buildDrawData(center, scale, handles, selectedId, dragHandle)
    local items = {}
    for i = 1, #handles do
        local h = handles[i]
        if dragHandle and h.id ~= dragHandle.id then goto continue end
        local isSel = selectedId == h.id
        local c = isSel and COLORS.selected or (h.color or COLORS.z)

        if h.kind == 'axis' then
            local len = h.axisLength or (CONFIG.axisLength * scale)
            local s1 = toScreen(center)
            local s2 = toScreen(add(center, mul(h.axis, len)))
            if s1 and s2 then
                items[#items + 1] = {
                    id = h.id, kind = 'axis',
                    x1 = s1.x, y1 = s1.y, x2 = s2.x, y2 = s2.y,
                    r = c.r, g = c.g, b = c.b, sel = isSel, guideline = dragHandle ~= nil
                }
            end
        elseif h.kind == 'plane' then
            local len = h.axisLength or (CONFIG.axisLength * scale)
            local fMin = CONFIG.planeFracMin * len
            local fMax = CONFIG.planeFracMax * len
            local p1 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMin))))
            local p2 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMin))))
            local p3 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMax))))
            local p4 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMax))))
            if p1 and p2 and p3 and p4 then
                items[#items + 1] = {
                    id = h.id, kind = 'plane',
                    c = { { x = p1.x, y = p1.y }, { x = p2.x, y = p2.y }, { x = p3.x, y = p3.y }, { x = p4.x, y = p4.y } },
                    r = c.r, g = c.g, b = c.b, sel = isSel
                }
            end
        elseif h.kind == 'ring' then
            local radius = CONFIG.ringRadius * scale
            local helper = math.abs(h.axis.z) < 0.95 and v3(0.0, 0.0, 1.0) or v3(0.0, 1.0, 0.0)
            local tangent = normalize(cross(h.axis, helper))
            local bitangent = normalize(cross(h.axis, tangent))
            local pts = {}
            local steps = 32
            for s = 0, steps - 1 do
                local a = (s / steps) * math.pi * 2.0
                local p = add(center, add(mul(tangent, math.cos(a) * radius), mul(bitangent, math.sin(a) * radius)))
                local sp = toScreen(p)
                if sp then pts[#pts + 1] = { x = sp.x, y = sp.y } end
            end
            if #pts > 2 then
                items[#items + 1] = { id = h.id, kind = 'ring', pts = pts, r = c.r, g = c.g, b = c.b, sel = isSel }
            end
        end
        ::continue::
    end
    return items
end

local function pickHandle(center, scale, handles)
    local mx, my = mouse.x, mouse.y
    local best, bestDist
    local function tryUpdate(handle, dist)
        if not bestDist or dist < bestDist then
            bestDist = dist
            best = handle
        end
    end

    for i = 1, #handles do
        local h = handles[i]
        if h.kind == 'axis' then
            local len = h.axisLength or (CONFIG.axisLength * scale)
            local s1 = toScreen(center)
            local s2 = toScreen(add(center, mul(h.axis, len)))
            if s1 and s2 then
                local dist = screenDistanceToSegment(mx, my, s1.x, s1.y, s2.x, s2.y)
                if dist <= CONFIG.pickAxisThreshold then tryUpdate(h, dist) end
            end
        elseif h.kind == 'plane' then
            local len = h.axisLength or (CONFIG.axisLength * scale)
            local fMin = CONFIG.planeFracMin * len
            local fMax = CONFIG.planeFracMax * len
            local p1 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMin))))
            local p2 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMin))))
            local p3 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMax))))
            local p4 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMax))))
            if p1 and p2 and p3 and p4 then
                if pointInQuad(mx, my, p1, p2, p3, p4) then
                    tryUpdate(h, 0.0)
                else
                    local d1 = screenDistanceToSegment(mx, my, p1.x, p1.y, p2.x, p2.y)
                    local d2 = screenDistanceToSegment(mx, my, p2.x, p2.y, p3.x, p3.y)
                    local d3 = screenDistanceToSegment(mx, my, p3.x, p3.y, p4.x, p4.y)
                    local d4 = screenDistanceToSegment(mx, my, p4.x, p4.y, p1.x, p1.y)
                    local edgeDist = math.min(d1, d2, d3, d4)
                    if edgeDist <= CONFIG.pickPlaneEdgeThreshold then tryUpdate(h, edgeDist) end
                end
            end
        elseif h.kind == 'ring' then
            local radius = CONFIG.ringRadius * scale
            local helper = math.abs(h.axis.z) < 0.95 and v3(0.0, 0.0, 1.0) or v3(0.0, 1.0, 0.0)
            local tangent = normalize(cross(h.axis, helper))
            local bitangent = normalize(cross(h.axis, tangent))
            local steps = 40
            local lastScreen, minDist = nil, nil
            for s = 0, steps do
                local a = (s / steps) * math.pi * 2.0
                local p = add(center, add(mul(tangent, math.cos(a) * radius), mul(bitangent, math.sin(a) * radius)))
                local screen = toScreen(p)
                if screen and lastScreen then
                    local dist = screenDistanceToSegment(mx, my, lastScreen.x, lastScreen.y, screen.x, screen.y)
                    if not minDist or dist < minDist then minDist = dist end
                end
                if screen then lastScreen = screen end
            end
            if minDist and minDist <= CONFIG.pickRingThreshold then tryUpdate(h, minDist) end
        end
    end
    return best
end

local function openUi()
    mouse.x = 0.5
    mouse.y = 0.5
    mouse.down = false
    mouse.justPressed = false
    mouse.justReleased = false
    SendNUIMessage({
        action = 'toggle',
        active = true,
        view = state.view or 'gizmo',
        labels = {
            title = state.title or locale('gizmo_title'),
            modeTranslate = locale('translate_mode'),
            modeRotate = locale('rotate_mode'),
            confirm = locale('done_editing'),
            cancel = locale('cancel_editing'),
            snap = locale('snap_to_ground'),
            hint = locale('gizmo_hint')
        }
    })
    SetNuiFocus(true, state.view ~= 'freecam')
end

local function closeUi()
    SendNUIMessage({ action = 'toggle', active = false })
    SetNuiFocus(false, false)
end

local function setNuiCursorState()
    if not state.active then
        SetNuiFocus(false, false)
        return
    end
    if state.view == 'freecam' then
        SetNuiFocus(not state.cursorHidden, not state.cursorHidden)
    else
        SetNuiFocus(not state.cursorHidden, not state.cursorHidden)
    end
end

local function setView(view)
    if view ~= 'gizmo' and view ~= 'freecam' then return end
    if view == 'freecam' and not state.allowFreecam then return end
    if state.view == view then return end

    state.view = view
    state.cursorHidden = (view == 'freecam')
    state.hovered = nil
    state.dragging = nil
    mouse.down, mouse.justPressed, mouse.justReleased = false, false, false

    if view == 'freecam' then
        local ped = cache.ped or PlayerPedId()
        local anchor = GetEntityCoords(ped)
        if LF_GizmoCamera and LF_GizmoCamera.Start then
            LF_GizmoCamera.Start(anchor)
        end
    else
        if LF_GizmoCamera and LF_GizmoCamera.Stop then
            LF_GizmoCamera.Stop()
        end
    end

    setNuiCursorState()
    SendNUIMessage({ action = 'setView', view = state.view })
end

local function setMode(mode)
    if mode ~= 'translate' and mode ~= 'rotate' then return end
    state.mode = mode
    state.hovered = nil
    state.dragging = nil
end

local function finish(result)
    state.result = result
    state.active = false
end

local function setScaleformParams(scaleform, data)
    if not scaleform or not data then return end
    for _, v in ipairs(data) do
        PushScaleformMovieFunction(scaleform, v.name)
        if v.param then
            for _, par in ipairs(v.param) do
                if type(par) == 'number' then
                    if math.floor(par) == par then PushScaleformMovieFunctionParameterInt(par) else PushScaleformMovieFunctionParameterFloat(par) end
                elseif type(par) == 'boolean' then
                    PushScaleformMovieFunctionParameterBool(par)
                elseif type(par) == 'string' then
                    PushScaleformMovieFunctionParameterString(par)
                end
            end
        end
        PopScaleformMovieFunctionVoid()
    end
end

local function buildGizmoScaleformData()
    local slots = {
        { name = 'CLEAR_ALL', param = {} },
        { name = 'TOGGLE_MOUSE_BUTTONS', param = { 0 } },
        { name = 'CREATE_CONTAINER', param = {} },
        { name = 'SET_DATA_SLOT', param = { 0, GetControlInstructionalButton(2, GIZMO_KEYS.toggle, 0), state.mode == 'translate' and locale('rotate_mode') or locale('translate_mode') } },
        { name = 'SET_DATA_SLOT', param = { 1, GetControlInstructionalButton(2, GIZMO_KEYS.cancel, 0), locale('gizmo_key_cancel') } },
        { name = 'SET_DATA_SLOT', param = { 2, GetControlInstructionalButton(2, GIZMO_KEYS.confirm, 0), locale('gizmo_key_confirm') } },
        { name = 'SET_DATA_SLOT', param = { 3, GetControlInstructionalButton(2, GIZMO_KEYS.ratio, 0), state.view == 'freecam' and 'Vitesse cam' or ('Ratio : ' .. string.format('%.2f', state.ratio)) } },
        { name = 'SET_DATA_SLOT', param = { 4, GetControlInstructionalButton(2, GIZMO_KEYS.snap, 0), locale('gizmo_key_snap') } }
    }
    local idx = 5
    if state.allowFreecam then
        local freecamLabel = state.view == 'gizmo' and locale('gizmo_key_freecam') or locale('gizmo_key_gizmo')
        slots[#slots + 1] = { name = 'SET_DATA_SLOT', param = { idx, GetControlInstructionalButton(2, GIZMO_KEYS.freecam, 0), freecamLabel } }
        idx = idx + 1
    end
    if state.onDuplicate then
        slots[#slots + 1] = { name = 'SET_DATA_SLOT', param = { idx, GetControlInstructionalButton(2, GIZMO_KEYS.duplicate, 0), locale('gizmo_key_duplicate') } }
        idx = idx + 1
    end
    if state.onDelete then
        slots[#slots + 1] = { name = 'SET_DATA_SLOT', param = { idx, GetControlInstructionalButton(2, GIZMO_KEYS.delete, 0), locale('gizmo_key_delete') } }
        idx = idx + 1
    end
    local cursorLabel = state.cursorHidden and locale('gizmo_key_show_cursor') or locale('gizmo_key_hide_cursor')
    slots[#slots + 1] = { name = 'SET_DATA_SLOT', param = { idx, GetControlInstructionalButton(2, GIZMO_KEYS.hideCursor, 0), cursorLabel } }
    slots[#slots + 1] = { name = 'DRAW_INSTRUCTIONAL_BUTTONS', param = { -1 } }
    return slots
end

local function createGizmoScaleform()
    local scaleform = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    setScaleformParams(scaleform, buildGizmoScaleformData())
    return scaleform
end

local function updateMouseFromGame()
    local dx = GetDisabledControlNormal(0, 1)
    local dy = GetDisabledControlNormal(0, 2)
    mouse.x = clamp01(mouse.x + (dx * 0.012))
    mouse.y = clamp01(mouse.y + (dy * 0.012))
    mouse.justPressed = IsDisabledControlJustPressed(0, 24)
    mouse.justReleased = IsDisabledControlJustReleased(0, 24)
    if mouse.justPressed then mouse.down = true elseif mouse.justReleased then mouse.down = false end
end

local function canInteractNow()
    return state.entity ~= 0 and DoesEntityExist(state.entity)
        and ((state.view == 'gizmo' and not state.cursorHidden) or state.view == 'freecam')
end

local function triggerDuplicate()
    if not state.onDuplicate or not canInteractNow() then return end
    local ok, newEntity = pcall(state.onDuplicate, state.entity)
    if not ok then
        dbgPlacement(('onDuplicate failed: %s'):format(tostring(newEntity)))
        return
    end
    if newEntity and newEntity ~= 0 and DoesEntityExist(newEntity) then
        if state.allowedEntities then
            state.allowedEntities[newEntity] = true
            state.allowedEntities[tostring(newEntity)] = true
        end
        switchEntity(newEntity)
    end
end

local function triggerDelete()
    if not state.onDelete or not canInteractNow() then return end
    local ok, deleted = pcall(state.onDelete, state.entity)
    if not ok then
        dbgPlacement(('onDelete failed: %s'):format(tostring(deleted)))
        return
    end
    if deleted then finish('cancel') end
end

local function handleKeyboardControls()
    if state.allowFreecam and IsDisabledControlJustPressed(0, GIZMO_KEYS.freecam) then
        setView(state.view == 'gizmo' and 'freecam' or 'gizmo')
    end

    if IsDisabledControlJustPressed(0, GIZMO_KEYS.hideCursor) then
        state.cursorHidden = not state.cursorHidden
        setNuiCursorState()
    end

    if (state.view == 'freecam') or (state.view == 'gizmo' and not state.cursorHidden) then
        if IsDisabledControlJustPressed(0, 157) then
            setMode('translate')
        elseif IsDisabledControlJustPressed(0, 158) then
            setMode('rotate')
        elseif IsDisabledControlJustPressed(0, GIZMO_KEYS.toggle) then
            setMode(state.mode == 'translate' and 'rotate' or 'translate')
        end
    end

    if canInteractNow() and IsDisabledControlJustPressed(0, GIZMO_KEYS.snap) then
        PlaceObjectOnGroundProperly_2(state.entity)
    end

    if state.view == 'freecam' then
        if IsDisabledControlJustPressed(0, 241) and LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then
            LF_GizmoCamera.AdjustSpeed(-120)
        elseif IsDisabledControlJustPressed(0, 242) and LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then
            LF_GizmoCamera.AdjustSpeed(120)
        end
        if IsDisabledControlJustPressed(0, 348) and LF_GizmoCamera and LF_GizmoCamera.ResetSpeed then
            LF_GizmoCamera.ResetSpeed()
        end
    end

    if state.onDuplicate and IsDisabledControlJustPressed(0, GIZMO_KEYS.duplicate) then triggerDuplicate() end
    if state.onDelete and IsDisabledControlJustPressed(0, GIZMO_KEYS.delete) then triggerDelete() end

    if IsDisabledControlJustPressed(0, GIZMO_KEYS.confirm) then
        finish('confirm')
    elseif IsDisabledControlJustPressed(0, GIZMO_KEYS.cancel) then
        finish('cancel')
    end
end

local function applyDrag()
    if not state.dragging then return end
    local drag = state.dragging
    local camPos, rayDir = getCamRay()
    local ratio = state.ratio or 1.0

    if drag.kind == 'axis' then
        if not drag.initialT then return end
        local n = cross(rayDir, drag.axis)
        if length(n) < 0.0001 then return end
        local planeNorm = normalize(cross(n, drag.axis))
        local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
        if not hit then return end
        local t1 = dot(sub(hit, drag.startPos), drag.axis)
        local newPos = add(drag.startPos, mul(drag.axis, (t1 - drag.initialT) * ratio))
        SetEntityCoordsNoOffset(state.entity, newPos.x, newPos.y, newPos.z, true, true, true)
    elseif drag.kind == 'plane' then
        if not drag.initialHit then return end
        local planeNorm = normalize(cross(drag.axisA, drag.axisB))
        local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
        if not hit then return end
        local delta = sub(hit, drag.initialHit)
        local newPos = add(drag.startPos, mul(delta, ratio))
        SetEntityCoordsNoOffset(state.entity, newPos.x, newPos.y, newPos.z, true, true, true)
    elseif drag.kind == 'ring' then
        if not drag.startHit or not drag.startQuat or not drag.localAxis then return end
        local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, drag.localAxis)
        local toHit
        if hit then
            toHit = sub(hit, drag.startPos)
            if length(toHit) < 0.0001 then return end
            toHit = normalize(toHit)
        else
            local proj = sub(rayDir, mul(drag.localAxis, dot(rayDir, drag.localAxis)))
            if length(proj) < 0.0001 then return end
            toHit = normalize(proj)
        end
        local prev = drag.prevHit or drag.startHit
        local cosA = math.max(-1.0, math.min(1.0, dot(prev, toHit)))
        local deltaAngle = math.acos(cosA)
        if dot(cross(prev, toHit), drag.localAxis) < 0 then deltaAngle = -deltaAngle end
        drag.prevHit = toHit
        drag.totalAngle = drag.totalAngle + deltaAngle * ratio
        local qDelta = quatFromAxisAngle(drag.localAxis, drag.totalAngle)
        local qNew = quatNormalize(quatMul(qDelta, drag.startQuat))
        local rx, ry, rz = quatToEulerOrder2(qNew)
        SetEntityRotation(state.entity, rx, ry, rz, 2, true)
    end
end

local function beginDrag(handle)
    if not handle then return end
    local data = { id = handle.id, kind = handle.kind }

    if handle.kind == 'axis' then
        data.axis = handle.axis
        data.startPos = GetEntityCoords(state.entity)
        local camPos, rayDir = getCamRay()
        local n = cross(rayDir, handle.axis)
        if length(n) >= 0.0001 then
            local planeNorm = normalize(cross(n, handle.axis))
            local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, planeNorm)
            if hit then data.initialT = dot(sub(hit, data.startPos), handle.axis) end
        end
    elseif handle.kind == 'plane' then
        data.axisA = handle.axisA
        data.axisB = handle.axisB
        data.startPos = GetEntityCoords(state.entity)
        local camPos, rayDir = getCamRay()
        local planeNorm = normalize(cross(handle.axisA, handle.axisB))
        local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, planeNorm)
        if hit then data.initialHit = hit end
    else
        data.localAxis = normalize(handle.axis)
        data.startPos = GetEntityCoords(state.entity)
        local startRot = GetEntityRotation(state.entity, 2)
        data.startQuat = quatNormalize(eulerOrder2ToQuat(startRot.x, startRot.y, startRot.z))
        data.totalAngle = 0.0
        local camPos, rayDir = getCamRay()
        local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, data.localAxis)
        if hit then
            local toHit = sub(hit, data.startPos)
            if length(toHit) > 0.0001 then data.startHit = normalize(toHit) end
        else
            local proj = sub(rayDir, mul(data.localAxis, dot(rayDir, data.localAxis)))
            if length(proj) > 0.0001 then data.startHit = normalize(proj) end
        end
    end

    state.dragging = data
end

RegisterNUICallback('gizmoMouseMove', function(data, cb)
    if state.view == 'freecam' and state.cursorHidden then
        cb(1)
        return
    end
    mouse.x = tonumber(data.x) or mouse.x
    mouse.y = tonumber(data.y) or mouse.y
    cb(1)
end)

RegisterNUICallback('gizmoMouseDown', function(_, cb)
    if state.active and (state.view ~= 'freecam' or not state.cursorHidden) and not mouse.down then
        mouse.down = true
        mouse.justPressed = true
    end
    cb(1)
end)

RegisterNUICallback('gizmoMouseUp', function(_, cb)
    if state.active and (state.view ~= 'freecam' or not state.cursorHidden) and mouse.down then
        mouse.down = false
        mouse.justReleased = true
    end
    cb(1)
end)

RegisterNUICallback('gizmoAction', function(data, cb)
    if not state.active then
        cb(1)
        return
    end
    local action = data.action
    if action == 'mode_translate' then
        setMode('translate')
    elseif action == 'mode_rotate' then
        setMode('rotate')
    elseif action == 'mode_toggle' then
        setMode(state.mode == 'translate' and 'rotate' or 'translate')
    elseif action == 'mode_freecam' then
        if state.allowFreecam then setView(state.view == 'gizmo' and 'freecam' or 'gizmo') end
    elseif action == 'confirm' then
        finish('confirm')
    elseif action == 'cancel' then
        finish('cancel')
    elseif action == 'snap' then
        if canInteractNow() then PlaceObjectOnGroundProperly_2(state.entity) end
    elseif action == 'duplicate' then
        triggerDuplicate()
    elseif action == 'delete' then
        triggerDelete()
    elseif action == 'ratio_delta' then
        local delta = tonumber(data.delta) or 0
        if state.view == 'freecam' then
            if LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then LF_GizmoCamera.AdjustSpeed(delta) end
        else
            state.ratio = state.ratio - delta * RATIO_SCROLL_FACTOR
            state.ratio = math.max(RATIO_MIN, math.min(RATIO_MAX, state.ratio))
        end
    elseif action == 'ratio_reset' then
        if state.view == 'freecam' then
            if LF_GizmoCamera and LF_GizmoCamera.ResetSpeed then LF_GizmoCamera.ResetSpeed() end
        else
            state.ratio = RATIO_DEFAULT
        end
    elseif action == 'toggle_cursor' then
        state.cursorHidden = not state.cursorHidden
        setNuiCursorState()
    end
    cb(1)
end)

RegisterNUICallback('gizmoSetPosition', function(data, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) then
        cb(1)
        return
    end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if x and y and z then
        SetEntityCoordsNoOffset(state.entity, x + 0.0, y + 0.0, z + 0.0, true, true, true)
    end
    cb(1)
end)

RegisterNUICallback('gizmoSetRotation', function(data, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) then
        cb(1)
        return
    end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if x ~= nil and y ~= nil and z ~= nil then
        SetEntityRotation(state.entity, x + 0.0, y + 0.0, z + 0.0, 2, true)
    end
    cb(1)
end)

RegisterNUICallback('gizmoResetPosition', function(_, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) or not state.initialPos then
        cb(1)
        return
    end
    local p = state.initialPos
    SetEntityCoordsNoOffset(state.entity, p.x, p.y, p.z, true, true, true)
    cb(1)
end)

RegisterNUICallback('gizmoResetRotation', function(_, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) or not state.initialRot then
        cb(1)
        return
    end
    local r = state.initialRot
    SetEntityRotation(state.entity, r.x, r.y, r.z, 2, true)
    cb(1)
end)

local function freecamRaycast()
    if not cameraIsActive() then return nil end
    local camPos = LF_GizmoCamera.GetCoord()
    local camRot = LF_GizmoCamera.GetRot()
    local yaw = math.rad(camRot.z)
    local pitch = math.rad(camRot.x)
    local fx = -math.sin(yaw) * math.cos(pitch)
    local fy = math.cos(yaw) * math.cos(pitch)
    local fz = math.sin(pitch)
    local range = 50.0
    local endX = camPos.x + fx * range
    local endY = camPos.y + fy * range
    local endZ = camPos.z + fz * range
    local ignoreEntity = (state.entity ~= 0 and DoesEntityExist(state.entity)) and state.entity or (cache.ped or PlayerPedId())
    local rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z, endX, endY, endZ, -1, ignoreEntity, 0)
    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)
    if hit == 1 and entityHit and entityHit ~= 0 and DoesEntityExist(entityHit) then
        local etype = GetEntityType(entityHit)
        local ped = cache.ped or PlayerPedId()
        if etype == 3 and entityHit ~= ped then return entityHit end
    end
    return nil
end

local function restoreEntity(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    SetEntityCollision(ent, true, true)
    if IsEntityAPed(ent) then
        SetEntityAlpha(ent, 255)
    else
        SetEntityDrawOutline(ent, false)
    end
end

local function prepareEntity(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    SetEntityCollision(ent, false, false)
    if IsEntityAPed(ent) then
        SetEntityAlpha(ent, 200)
    else
        SetEntityDrawOutlineShader(1)
        SetEntityDrawOutline(ent, true)
    end
end

local function saveEntityState(ent, into)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    into[ent] = {
        position = GetEntityCoords(ent),
        rotation = GetEntityRotation(ent, 2)
    }
end

switchEntity = function(newEntity)
    local old = state.entity
    if old == newEntity then return end

    if state.allowedEntities and old and old ~= 0 and DoesEntityExist(old) then
        saveEntityState(old, state.modifiedEntities)
    end

    restoreEntity(old)
    state.entity = newEntity or 0
    state.hovered = nil
    state.dragging = nil

    if newEntity and newEntity ~= 0 and DoesEntityExist(newEntity) then
        if state.allowedEntities and not state.initialStates[newEntity] then
            state.initialStates[newEntity] = {
                position = GetEntityCoords(newEntity),
                rotation = GetEntityRotation(newEntity, 2)
            }
        end
        prepareEntity(newEntity)
    end
end

local function forceClose()
    state.active = false
    state.dragging = nil
    state.hovered = nil
    state.view = 'gizmo'
    state.cursorHidden = false
    state.entity = 0
    if LF_GizmoCamera and LF_GizmoCamera.Stop then LF_GizmoCamera.Stop() end
    closeUi()
    if gizmoScaleform then
        SetScaleformMovieAsNoLongerNeeded(gizmoScaleform)
        gizmoScaleform = nil
    end
end

local function gizmoLoop(entity)
    state.view = 'gizmo'
    state.cursorHidden = false
    state.hovered = nil
    state.dragging = nil
    state.ratio = RATIO_DEFAULT
    state.modifiedEntities = {}
    state.initialStates = {}

    if state.allowedEntities and entity and entity ~= 0 and DoesEntityExist(entity) then
        state.initialStates[entity] = {
            position = GetEntityCoords(entity),
            rotation = GetEntityRotation(entity, 2)
        }
    end

    openUi()
    gizmoScaleform = createGizmoScaleform()
    prepareEntity(entity)

    while state.active do
        Wait(0)
        local currentEntity = state.entity
        local hasEntity = currentEntity ~= 0 and DoesEntityExist(currentEntity)
        if state.view == 'gizmo' and not hasEntity then break end

        local blockMovement = (state.view == 'freecam') or (state.view == 'gizmo' and not state.cursorHidden)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 23, true)
        DisableControlAction(0, 47, true)
        DisableControlAction(0, GIZMO_KEYS.cancel, true)
        if state.onDuplicate then DisableControlAction(0, GIZMO_KEYS.duplicate, true) end
        if state.onDelete then DisableControlAction(0, GIZMO_KEYS.delete, true) end

        if blockMovement then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 38, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            if state.view == 'freecam' then
                DisableControlAction(0, 45, true)
                DisableControlAction(0, 157, true)
                DisableControlAction(0, 158, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 263, true)
                DisableControlAction(0, 264, true)
            end
        end

        DisablePlayerFiring(cache.playerId, true)
        handleKeyboardControls()

        if state.view == 'freecam' then
            if LF_GizmoCamera and LF_GizmoCamera.Update then LF_GizmoCamera.Update() end
            if state.cursorHidden then
                mouse.x = 0.5
                mouse.y = 0.5
                mouse.justPressed = IsDisabledControlJustPressed(0, 24)
                mouse.justReleased = IsDisabledControlJustReleased(0, 24)
                if mouse.justPressed then mouse.down = true elseif mouse.justReleased then mouse.down = false end
            end
        elseif state.view == 'gizmo' and state.cursorHidden then
            updateMouseFromGame()
        end

        if gizmoScaleform then
            setScaleformParams(gizmoScaleform, buildGizmoScaleformData())
            DrawScaleformMovieFullscreen(gizmoScaleform, 255, 255, 255, 255, 0)
        end

        local drawItems = {}
        local selectedId = ''
        local entityPos = hasEntity and GetEntityCoords(currentEntity) or v3(0.0, 0.0, 0.0)
        local entityRot = hasEntity and GetEntityRotation(currentEntity, 2) or v3(0.0, 0.0, 0.0)
        local rdx, rdy, rdz = rotationForDisplay(entityRot.x, entityRot.y, entityRot.z)

        if hasEntity and (not state.cursorHidden or state.view == 'freecam') then
            local center = entityPos
            local gizmoScale = getGizmoScale(center)
            local axes = getAxes(currentEntity)
            local handles = state.mode == 'translate'
                and getTranslateHandles(center, axes, gizmoScale)
                or getRotateHandles(center, axes)

            if state.dragging and state.dragging.kind == 'ring' and state.dragging.localAxis then
                local frozen = state.dragging.localAxis
                for hi = 1, #handles do
                    local h = handles[hi]
                    if h.kind == 'ring' and h.id == state.dragging.id then
                        h.axis = frozen
                        break
                    end
                end
            end

            if not state.dragging then
                state.hovered = pickHandle(center, gizmoScale, handles)
            end

            if mouse.justPressed then
                if state.hovered then
                    beginDrag(state.hovered)
                elseif state.view == 'freecam' and not state.lockEntity then
                    local hitEntity = freecamRaycast()
                    if hitEntity then
                        local filterOk
                        if state.entityFilter then
                            filterOk = state.entityFilter(hitEntity)
                        elseif state.allowedEntities then
                            filterOk = state.allowedEntities[hitEntity] == true or state.allowedEntities[tostring(hitEntity)] == true
                        else
                            filterOk = true
                        end
                        if filterOk then switchEntity(hitEntity) end
                    elseif not state.entityFilter and not state.allowedEntities then
                        switchEntity(0)
                    end
                end
            elseif mouse.justReleased then
                state.dragging = nil
            end

            if mouse.down and state.dragging then
                applyDrag()
            end

            selectedId = state.dragging and state.dragging.id or (state.hovered and state.hovered.id or '')
            drawItems = buildDrawData(center, gizmoScale, handles, selectedId, state.dragging)
        elseif not hasEntity and state.view == 'freecam' and not state.lockEntity and mouse.justPressed then
            local hitEntity = freecamRaycast()
            if hitEntity then
                local filterOk
                if state.entityFilter then
                    filterOk = state.entityFilter(hitEntity)
                elseif state.allowedEntities then
                    filterOk = state.allowedEntities[hitEntity] == true or state.allowedEntities[tostring(hitEntity)] == true
                else
                    filterOk = true
                end
                if filterOk then switchEntity(hitEntity) end
            end
        end

        SendNUIMessage({
            action = 'draw',
            items = drawItems,
            cursor = { x = mouse.x, y = mouse.y },
            view = state.view,
            centerCursor = state.view == 'freecam' and state.cursorHidden,
            hideGizmo = (state.view == 'gizmo' and state.cursorHidden) or not hasEntity,
            mode = state.mode,
            selected = selectedId,
            position = { x = entityPos.x, y = entityPos.y, z = entityPos.z },
            rotation = { x = rdx, y = rdy, z = rdz }
        })

        mouse.justPressed = false
        mouse.justReleased = false
    end

    if gizmoScaleform then
        SetScaleformMovieAsNoLongerNeeded(gizmoScaleform)
        gizmoScaleform = nil
    end
    if LF_GizmoCamera and LF_GizmoCamera.Stop then LF_GizmoCamera.Stop() end
    if state.entity ~= 0 and state.entity ~= entity then restoreEntity(state.entity) end
    restoreEntity(entity)
    closeUi()
end

local function useGizmo(entity, options)
    if state.active then
        return {
            handle = entity,
            result = 'busy',
            position = DoesEntityExist(entity) and GetEntityCoords(entity) or v3(0.0, 0.0, 0.0),
            rotation = DoesEntityExist(entity) and GetEntityRotation(entity, 2) or v3(0.0, 0.0, 0.0),
            modifications = nil
        }
    end

    if not DoesEntityExist(entity) then
        return {
            handle = entity,
            result = 'invalid',
            position = v3(0.0, 0.0, 0.0),
            rotation = v3(0.0, 0.0, 0.0),
            modifications = nil
        }
    end

    local opts = options or {}
    state.entityFilter = type(opts.entityFilter) == 'function' and opts.entityFilter or nil
    state.allowedEntities = type(opts.allowedEntities) == 'table' and opts.allowedEntities or nil
    state.onDuplicate = type(opts.onDuplicate) == 'function' and opts.onDuplicate or nil
    state.onDelete = type(opts.onDelete) == 'function' and opts.onDelete or nil
    state.title = opts.title or locale('gizmo_title')
    state.allowFreecam = opts.allowFreecam ~= false

    if opts.lockEntity ~= nil then
        state.lockEntity = opts.lockEntity == true
    else
        state.lockEntity = (state.entityFilter == nil and state.allowedEntities == nil)
    end

    state.active = true
    state.entity = entity
    state.mode = 'translate'
    state.view = 'gizmo'
    state.result = 'cancel'
    state.initialPos = GetEntityCoords(entity)
    state.initialRot = GetEntityRotation(entity, 2)

    dbgPlacement(('Start entity=%s'):format(tostring(entity)))
    gizmoLoop(entity)
    state.active = false

    if state.result == 'confirm' then
        if state.allowedEntities and state.entity and state.entity ~= 0 and DoesEntityExist(state.entity) then
            saveEntityState(state.entity, state.modifiedEntities)
        end
    elseif state.result == 'cancel' and state.allowedEntities then
        for ent, init in pairs(state.initialStates or {}) do
            if DoesEntityExist(ent) then
                SetEntityCoordsNoOffset(ent, init.position.x, init.position.y, init.position.z, true, true, true)
                SetEntityRotation(ent, init.rotation.x, init.rotation.y, init.rotation.z, 2, true)
            end
        end
    elseif state.result == 'cancel' and DoesEntityExist(entity) then
        SetEntityCoordsNoOffset(entity, state.initialPos.x, state.initialPos.y, state.initialPos.z, true, true, true)
        SetEntityRotation(entity, state.initialRot.x, state.initialRot.y, state.initialRot.z, 2, true)
    end

    local modifications = nil
    if state.allowedEntities then
        modifications = {}
        if state.result == 'confirm' and state.modifiedEntities then
            for ent, data in pairs(state.modifiedEntities) do
                if DoesEntityExist(ent) then
                    modifications[#modifications + 1] = {
                        entity = ent,
                        position = data.position,
                        rotation = data.rotation
                    }
                end
            end
        end
    end

    local handle = (state.entity ~= 0 and DoesEntityExist(state.entity)) and state.entity or entity
    local output = {
        handle = handle,
        result = state.result,
        position = DoesEntityExist(handle) and GetEntityCoords(handle) or state.initialPos,
        rotation = DoesEntityExist(handle) and GetEntityRotation(handle, 2) or state.initialRot,
        modifications = modifications
    }

    state.entity = 0
    state.view = 'gizmo'
    state.hovered = nil
    state.dragging = nil
    state.lockEntity = true
    state.entityFilter = nil
    state.allowedEntities = nil
    state.onDuplicate = nil
    state.onDelete = nil
    state.title = nil
    state.allowFreecam = true
    state.modifiedEntities = {}
    state.initialStates = {}
    state.ratio = RATIO_DEFAULT

    return output
end

exports('useGizmo', useGizmo)
exports('isGizmoActive', function()
    return state.active == true
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceClose()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceClose()
end)
