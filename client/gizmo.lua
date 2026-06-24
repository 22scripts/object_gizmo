lib.locale()

local function dbgPlacement(msg)
    if GetConvarInt('object_gizmo:debugPlacement', 0) ~= 1 then return end
    print(msg)
end

local CONFIG = {
    axisLength        = 0.7,
    axisLengthMin     = 0.15,
    axisHeadSize      = 0.08,

    planeFracMin      = 0.10,
    planeFracMax      = 0.50,
    ringRadius        = 0.65,
    pickAxisThreshold      = 0.018,
    pickPlaneEdgeThreshold = 0.012,
    pickRingThreshold      = 0.016
}

local COLORS = {
    x        = { r = 220, g = 40,  b = 40  },
    y        = { r = 40,  g = 100, b = 220 },
    z        = { r = 40,  g = 200, b = 70  },
    plane_xy = { r = 0,   g = 210, b = 210 },
    plane_xz = { r = 210, g = 0,   b = 210 },
    plane_yz = { r = 210, g = 210, b = 0   },
    selected = { r = 255, g = 255, b = 255 }
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
    lastUiTick = 0,
    ratio = 1.0,
    scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 },
    modifiedEntities = {},
    initialStates = {}
}

local RATIO_MIN, RATIO_MAX, RATIO_DEFAULT = 0.05, 5.0, 1.0
local RATIO_SCROLL_FACTOR = 0.001

local GIZMO_KEYS = {
    toggle       = 45,
    freecam      = 23,
    hideCursor   = 47,
    cancel       = 177,
    confirm      = 191,
    ratio        = 14,
    snap         = 21,
    duplicate    = 26,
    delete       = 214,
    scaleModifier = 36
}

local SCALE_DRAG_SENSITIVITY = 0.25
local SCALE_OFFSET_MIN, SCALE_OFFSET_MAX = -0.99, 15.0

local GizmoScaleform = nil

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
    local right   = v3(1.0 - (yy + zz), xy + wz, xz - wy)
    local forward = v3(xy - wz, 1.0 - (xx + zz), yz + wx)
    local up      = v3(xz + wy, yz - wx, 1.0 - (xx + yy))
    return forward, right, up
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
    local rot    = getActiveCamRot()
    local fov    = (LF_GizmoCamera and LF_GizmoCamera.GetFov and LF_GizmoCamera.GetFov()) or GetGameplayCamFov()
    local aspect = GetAspectRatio(false)
    local pitch  = math.rad(rot.x)
    local yaw    = math.rad(rot.z)

    local forward = normalize(v3(
        -math.sin(yaw) * math.cos(pitch),
         math.cos(yaw) * math.cos(pitch),
         math.sin(pitch)
    ))
    local right = normalize(cross(forward, v3(0.0, 0.0, 1.0)))
    if length(right) < 0.0001 then right = v3(1.0, 0.0, 0.0) end
    local up = normalize(cross(right, forward))

    local nx      = (mouse.x - 0.5) * 2.0
    local ny      = -((mouse.y - 0.5) * 2.0)
    local tanHalfV = math.tan(math.rad(fov * 0.5))
    local tanHalfH = tanHalfV * aspect

    local rayDir = normalize(add(
        add(forward, mul(right, nx * tanHalfH)),
        mul(up, ny * tanHalfV)
    ))

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
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        local ok, forward, right, up = pcall(GetEntityMatrix, entity)
        if ok and forward and right and up then
            return {
                x = normalize(v3(right.x, right.y, right.z)),
                y = normalize(v3(forward.x, forward.y, forward.z)),
                z = normalize(v3(up.x, up.y, up.z))
            }
        end
    end
    return {
        x = v3(1.0, 0.0, 0.0),
        y = v3(0.0, 1.0, 0.0),
        z = v3(0.0, 0.0, 1.0)
    }
end

local function getGizmoScale(center)
    local cam = getActiveCamCoord()
    local dist = #(center - cam)
    return math.max(0.3, dist * 0.08)
end

local function buildDrawData(center, scale, handles, selectedId, dragHandle)
    local items = {}

    for i = 1, #handles do
        local h = handles[i]

        if dragHandle and h.id ~= dragHandle.id then
            goto continue
        end

        local isSel = selectedId == h.id
        local c = isSel and COLORS.selected or (h.color or COLORS.z)

        if h.kind == 'axis' then
            local aLen = h.axisLength or (CONFIG.axisLength * scale)
            local s1 = toScreen(center)
            local endPos = add(center, mul(h.axis, aLen))
            local s2 = toScreen(endPos)
            if s1 and s2 then
                items[#items + 1] = {
                    id = h.id, kind = 'axis',
                    x1 = s1.x, y1 = s1.y,
                    x2 = s2.x, y2 = s2.y,
                    r = c.r, g = c.g, b = c.b, sel = isSel,

                    guideline = dragHandle ~= nil
                }
            end

        elseif h.kind == 'plane' then

            local aLen = h.axisLength or (CONFIG.axisLength * scale)
            local fMin = CONFIG.planeFracMin * aLen
            local fMax = CONFIG.planeFracMax * aLen
            local p1 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMin))))
            local p2 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMin))))
            local p3 = toScreen(add(center, add(mul(h.axisA, fMax), mul(h.axisB, fMax))))
            local p4 = toScreen(add(center, add(mul(h.axisA, fMin), mul(h.axisB, fMax))))
            if p1 and p2 and p3 and p4 then
                items[#items + 1] = {
                    id = h.id, kind = 'plane',
                    c = { {x=p1.x,y=p1.y},{x=p2.x,y=p2.y},{x=p3.x,y=p3.y},{x=p4.x,y=p4.y} },
                    r = c.r, g = c.g, b = c.b, sel = isSel
                }
            end

        elseif h.kind == 'ring' then
            local radius    = CONFIG.ringRadius * scale
            local helper    = math.abs(h.axis.z) < 0.95 and v3(0.0, 0.0, 1.0) or v3(0.0, 1.0, 0.0)
            local tangent   = normalize(cross(h.axis, helper))
            local bitangent = normalize(cross(h.axis, tangent))
            local steps     = 32
            local pts       = {}
            for s = 0, steps - 1 do
                local a   = (s / steps) * math.pi * 2.0
                local p3d = add(center, add(mul(tangent, math.cos(a) * radius), mul(bitangent, math.sin(a) * radius)))
                local sp  = toScreen(p3d)
                if sp then
                    pts[#pts + 1] = { x = sp.x, y = sp.y }
                end
            end
            if #pts > 2 then
                items[#items + 1] = {
                    id = h.id, kind = 'ring',
                    pts = pts,
                    r = c.r, g = c.g, b = c.b, sel = isSel
                }
            end
        end

        ::continue::
    end

    return items
end

local function getTranslateHandles(center, axes, scale, axisLengths)
    local cam   = getActiveCamCoord()
    local toCam = normalize(sub(cam, center))

    local sX = dot(toCam, axes.x) >= 0.0 and 1.0 or -1.0
    local sY = dot(toCam, axes.y) >= 0.0 and 1.0 or -1.0
    local sZ = dot(toCam, axes.z) >= 0.0 and 1.0 or -1.0

    local lenX = axisLengths and axisLengths.x or (CONFIG.axisLength * scale)
    local lenY = axisLengths and axisLengths.y or (CONFIG.axisLength * scale)
    local lenZ = axisLengths and axisLengths.z or (CONFIG.axisLength * scale)

    return {
        { id = 'axis_x',   kind = 'axis',  axis  = mul(axes.x, sX),   axisLength = lenX, color = COLORS.x },
        { id = 'axis_y',   kind = 'axis',  axis  = mul(axes.y, sY),   axisLength = lenY, color = COLORS.y },
        { id = 'axis_z',   kind = 'axis',  axis  = mul(axes.z, sZ),   axisLength = lenZ, color = COLORS.z },
        { id = 'plane_xy', kind = 'plane', axisA = mul(axes.x, sX), axisB = mul(axes.y, sY), axisLength = math.max(lenX, lenY), color = COLORS.plane_xy },
        { id = 'plane_xz', kind = 'plane', axisA = mul(axes.x, sX), axisB = mul(axes.z, sZ), axisLength = math.max(lenX, lenZ), color = COLORS.plane_xz },
        { id = 'plane_yz', kind = 'plane', axisA = mul(axes.y, sY), axisB = mul(axes.z, sZ), axisLength = math.max(lenY, lenZ), color = COLORS.plane_yz }
    }
end

local function getRotateHandles(center, axes)
    local cam   = getActiveCamCoord()
    local toCam = normalize(sub(cam, center))

    local sX = dot(toCam, axes.x) >= 0.0 and 1.0 or -1.0
    local sY = dot(toCam, axes.y) >= 0.0 and 1.0 or -1.0
    local sZ = dot(toCam, axes.z) >= 0.0 and 1.0 or -1.0

    return {
        { id = 'ring_x', kind = 'ring', axis = mul(axes.x, sX), color = COLORS.x },
        { id = 'ring_y', kind = 'ring', axis = mul(axes.y, sY), color = COLORS.y },
        { id = 'ring_z', kind = 'ring', axis = mul(axes.z, sZ), color = COLORS.z }
    }
end

local function pickHandle(center, scale, handles)
    local mx, my = mouse.x, mouse.y
    local best, bestDist

    local function tryUpdate(handle, dist)
        if not bestDist or dist < bestDist then
            bestDist = dist
            best     = handle
        end
    end

    for i = 1, #handles do
        local handle = handles[i]

        if handle.kind == 'axis' then
            local aLen   = handle.axisLength or (CONFIG.axisLength * scale)
            local s1     = toScreen(center)
            local endPos = add(center, mul(handle.axis, aLen))
            local s2     = toScreen(endPos)
            if s1 and s2 then
                local dist = screenDistanceToSegment(mx, my, s1.x, s1.y, s2.x, s2.y)
                if dist <= CONFIG.pickAxisThreshold then
                    tryUpdate(handle, dist)
                end
            end

        elseif handle.kind == 'plane' then
            local aLen = handle.axisLength or (CONFIG.axisLength * scale)
            local fMin = CONFIG.planeFracMin * aLen
            local fMax = CONFIG.planeFracMax * aLen
            local p1 = toScreen(add(center, add(mul(handle.axisA, fMin), mul(handle.axisB, fMin))))
            local p2 = toScreen(add(center, add(mul(handle.axisA, fMax), mul(handle.axisB, fMin))))
            local p3 = toScreen(add(center, add(mul(handle.axisA, fMax), mul(handle.axisB, fMax))))
            local p4 = toScreen(add(center, add(mul(handle.axisA, fMin), mul(handle.axisB, fMax))))
            if p1 and p2 and p3 and p4 then
                if pointInQuad(mx, my, p1, p2, p3, p4) then

                    tryUpdate(handle, 0.0)
                else

                    local d1 = screenDistanceToSegment(mx, my, p1.x, p1.y, p2.x, p2.y)
                    local d2 = screenDistanceToSegment(mx, my, p2.x, p2.y, p3.x, p3.y)
                    local d3 = screenDistanceToSegment(mx, my, p3.x, p3.y, p4.x, p4.y)
                    local d4 = screenDistanceToSegment(mx, my, p4.x, p4.y, p1.x, p1.y)
                    local edgeDist = math.min(d1, d2, d3, d4)
                    if edgeDist <= CONFIG.pickPlaneEdgeThreshold then
                        tryUpdate(handle, edgeDist)
                    end
                end
            end

        elseif handle.kind == 'ring' then
            local radius    = CONFIG.ringRadius * scale
            local helper    = math.abs(handle.axis.z) < 0.95 and v3(0.0, 0.0, 1.0) or v3(0.0, 1.0, 0.0)
            local tangent   = normalize(cross(handle.axis, helper))
            local bitangent = normalize(cross(handle.axis, tangent))
            local steps     = 40
            local lastScreen = nil
            local minDist    = nil

            for s = 0, steps do
                local a      = (s / steps) * math.pi * 2.0
                local point  = add(center, add(mul(tangent, math.cos(a) * radius), mul(bitangent, math.sin(a) * radius)))
                local screen = toScreen(point)
                if screen and lastScreen then
                    local dist = screenDistanceToSegment(mx, my, lastScreen.x, lastScreen.y, screen.x, screen.y)
                    if (not minDist) or dist < minDist then minDist = dist end
                end
                if screen then lastScreen = screen end
            end

            if minDist and minDist <= CONFIG.pickRingThreshold then
                tryUpdate(handle, minDist)
            end
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
    local title = (state.gizmoFlag and locale('gizmo_flag_' .. state.gizmoFlag)) or locale('gizmo_title')
    SendNUIMessage({
        action = 'toggle',
        active = true,
        view = state.view or 'gizmo',
        labels = {
            title        = title,
            modeTranslate = locale('translate_mode'),
            modeRotate   = locale('rotate_mode'),
            confirm      = locale('done_editing'),
            cancel       = locale('cancel_editing'),
            snap         = locale('snap_to_ground'),
            hint         = locale('gizmo_hint')
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
        if state.cursorHidden then
            SetNuiFocus(false, false)
        else
            SetNuiFocus(true, true)
        end

    elseif state.cursorHidden then
        SetNuiFocus(false, false)
    else
        SetNuiFocus(true, true)
    end
end

local function setView(view)
    if view ~= 'gizmo' and view ~= 'freecam' then return end
    if state.view == view then return end

    state.view = view
    state.cursorHidden = (view == 'freecam')
    state.hovered = nil
    state.dragging = nil
    mouse.down = false
    mouse.justPressed = false
    mouse.justReleased = false

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

local function forceClose()
    state.active = false
    state.dragging = nil
    state.hovered = nil
    state.view = 'gizmo'
    state.cursorHidden = false
    state.entity = 0
    if LF_GizmoCamera and LF_GizmoCamera.Stop then
        LF_GizmoCamera.Stop()
    end
    SendNUIMessage({ action = 'toggle', active = false })
    SetNuiFocus(false, false)
    if GizmoScaleform then
        SetScaleformMovieAsNoLongerNeeded(GizmoScaleform)
        GizmoScaleform = nil
    end
end

local function setScaleformParams(scaleform, data)
    if not scaleform or not data then return end
    for _, v in ipairs(data) do
        PushScaleformMovieFunction(scaleform, v.name)
        if v.param then
            for _, par in ipairs(v.param) do
                if type(par) == "number" then
                    if math.floor(par) == par then
                        PushScaleformMovieFunctionParameterInt(par)
                    else
                        PushScaleformMovieFunctionParameterFloat(par)
                    end
                elseif type(par) == "boolean" then
                    PushScaleformMovieFunctionParameterBool(par)
                elseif type(par) == "string" then
                    PushScaleformMovieFunctionParameterString(par)
                end
            end
        end
        PopScaleformMovieFunctionVoid()
    end
end

local function buildGizmoScaleformData()

    local entries = {}
    local function add(control, label) entries[#entries + 1] = { control, label } end

    if state.view == 'gizmo' and state.cursorHidden then

        add(GIZMO_KEYS.cancel,     locale('gizmo_key_cancel'))
        add(GIZMO_KEYS.confirm,    locale('gizmo_key_confirm'))
        add(GIZMO_KEYS.hideCursor, locale('gizmo_key_show_cursor'))
        add(GIZMO_KEYS.freecam,    locale('gizmo_key_freecam'))
    else
        local toggleLabel  = state.mode == 'translate' and locale('rotate_mode') or locale('translate_mode')
        local freecamLabel = state.view == 'gizmo' and locale('gizmo_key_freecam') or locale('gizmo_key_gizmo')
        local ratioLabel
        if state.view == 'freecam' then
            local speed = (LF_GizmoCamera and LF_GizmoCamera.GetSpeed and LF_GizmoCamera.GetSpeed()) or 1.0
            ratioLabel = ("Vitesse cam: %s"):format(string.format("%.2f", speed))
        else
            ratioLabel = ("Ratio : %s"):format(string.format("%.2f", state.ratio))
        end

        add(GIZMO_KEYS.cancel,  locale('gizmo_key_cancel'))
        add(GIZMO_KEYS.confirm, locale('gizmo_key_confirm'))
        add(GIZMO_KEYS.toggle,  toggleLabel)
        add(GIZMO_KEYS.freecam, freecamLabel)
        add(GIZMO_KEYS.ratio,   ratioLabel)
        add(GIZMO_KEYS.snap,    locale('gizmo_key_snap'))
        if state.mode == 'translate' and state.view == 'freecam' then
            add(GIZMO_KEYS.scaleModifier, locale('gizmo_key_scale_modifier'))
        end
        if state.onDuplicate or (state.allowDuplicate and state.duplicateHandler) then
            add(GIZMO_KEYS.duplicate, locale('gizmo_key_duplicate'))
        end
        if state.onDelete or (state.allowDelete and state.deleteHandler) then
            add(GIZMO_KEYS.delete, locale('gizmo_key_delete'))
        end
        local gLabel = (state.view == 'freecam' and state.cursorHidden) and locale('gizmo_key_show_cursor') or locale('gizmo_key_hide_cursor')
        add(GIZMO_KEYS.hideCursor, gLabel)
    end

    local data = {
        { name = "CLEAR_ALL", param = {} },
        { name = "TOGGLE_MOUSE_BUTTONS", param = { 0 } },
        { name = "CREATE_CONTAINER", param = {} },
    }
    for i, e in ipairs(entries) do
        data[#data + 1] = { name = "SET_DATA_SLOT", param = { i - 1, GetControlInstructionalButton(2, e[1], 0), e[2] } }
    end
    data[#data + 1] = { name = "DRAW_INSTRUCTIONAL_BUTTONS", param = { -1 } }
    return data
end

local function createGizmoScaleform()
    local scaleform = RequestScaleformMovie("INSTRUCTIONAL_BUTTONS")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    setScaleformParams(scaleform, buildGizmoScaleformData())
    return scaleform
end

local function clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function normalizeDegrees360(a)
    a = (a % 360.0) + 0.0
    if a < 0.0 then a = a + 360.0 end
    return a
end

local function rotationForDisplay(rx, ry, rz)
    return normalizeDegrees360(rx), normalizeDegrees360(ry), normalizeDegrees360(rz)
end

local function updateMouseFromGame()
    local dx = GetDisabledControlNormal(0, 1)
    local dy = GetDisabledControlNormal(0, 2)
    mouse.x = clamp01(mouse.x + (dx * 0.012))
    mouse.y = clamp01(mouse.y + (dy * 0.012))

    mouse.justPressed = IsDisabledControlJustPressed(0, 24)
    mouse.justReleased = IsDisabledControlJustReleased(0, 24)

    if mouse.justPressed then
        mouse.down = true
    elseif mouse.justReleased then
        mouse.down = false
    end
end

local function vecLen(v)
    if type(v) == 'table' then
        local x = v.x or v[1]
        local y = v.y or v[2]
        local z = v.z or v[3]
        if x and y and z then
            return math.sqrt(x * x + y * y + z * z)
        end
    end
    return 1.0
end

local function vecScale(v, s)
    local x = v.x or v[1] or 0
    local y = v.y or v[2] or 0
    local z = v.z or v[3] or 0
    return { x = x * s, y = y * s, z = z * s }
end

local function vecNorm(v)
    local L = vecLen(v)
    if L < 0.0001 then return { x = 1, y = 0, z = 0 } end
    local x = (v.x or v[1]) / L
    local y = (v.y or v[2]) / L
    local z = (v.z or v[3]) / L
    return { x = x, y = y, z = z }
end

local function getOrientationBasisFromEntity(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil, nil, nil end
    local okM, fM, rM, uM = pcall(GetEntityMatrix, ent)
    if not okM or not fM or not rM or not uM then return nil, nil, nil end
    local function V(t)
        local x = t.x or t[1]
        local y = t.y or t[2]
        local z = t.z or t[3]
        if x == nil or y == nil or z == nil then return nil end
        return vecNorm({ x = x, y = y, z = z })
    end
    return V(fM), V(rM), V(uM)
end

local function rotationToBasis(rotX, rotY, rotZ)
    local yaw   = math.rad(rotZ)
    local pitch = math.rad(rotX)
    local roll  = math.rad(rotY)
    local fx = -math.sin(yaw) * math.cos(pitch)
    local fy =  math.cos(yaw) * math.cos(pitch)
    local fz =  math.sin(pitch)
    local forward = vecNorm({ x = fx, y = fy, z = fz })
    local rx = fy * 1.0 - fz * 0.0
    local ry = fz * 0.0 - fx * 1.0
    local rz = fx * 0.0 - fy * 0.0
    local right = vecNorm({ x = rx, y = ry, z = rz })
    local ux = right.y * fz - right.z * fy
    local uy = right.z * fx - right.x * fz
    local uz = right.x * fy - right.y * fx
    local up = vecNorm({ x = ux, y = uy, z = uz })

    local cr, sr = math.cos(roll), math.sin(roll)
    local rightRolled = { x = right.x * cr + up.x * sr, y = right.y * cr + up.y * sr, z = right.z * cr + up.z * sr }
    local upRolled = { x = -right.x * sr + up.x * cr, y = -right.y * sr + up.y * cr, z = -right.z * sr + up.z * cr }
    return forward, vecNorm(rightRolled), vecNorm(upRolled)
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
    else
        local s = math.sqrt(1.0 + m33 - m11 - m22) * 2.0
        return quatNew((m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s)
    end
end

local function basisToEulerOrder2(forward, right, up)

    local fz = forward.z
    if fz > 1.0 then fz = 1.0 elseif fz < -1.0 then fz = -1.0 end
    local pitch = math.asin(fz)
    local yaw, roll
    if math.abs(fz) > 0.99999 then

        roll = 0.0
        yaw = math.atan(-right.x, right.y)
    else
        yaw = math.atan(-forward.x, forward.y)
        roll = math.atan(right.z, up.z)
    end
    return math.deg(pitch), math.deg(roll), math.deg(yaw)
end

local function eulerOrder2ToQuat(rxDeg, ryDeg, rzDeg)
    local fwd, right, up = rotationToBasis(rxDeg or 0.0, ryDeg or 0.0, rzDeg or 0.0)
    return basisToQuat(fwd, right, up)
end

local function quatToEulerOrder2(q)
    local fwd, right, up = quatToBasisStd(q)
    return basisToEulerOrder2(fwd, right, up)
end

local function SetEntityScaleMatrix(entity, scaleX, scaleY, scaleZ)
    if not DoesEntityExist(entity) then return end
    local targetEntity = entity
    if GetEntityType(entity) == 1 then
        if IsPedInAnyVehicle(entity, false) then
            targetEntity = GetVehiclePedIsIn(entity, false)
        elseif DoesEntityExist(GetEntityAttachedTo(entity)) then
            targetEntity = GetEntityAttachedTo(entity)
        end
    end
    local pos = GetEntityCoords(targetEntity)

    local forward, right, up = getOrientationBasisFromEntity(targetEntity)
    if not forward or not right or not up then
        local rot = GetEntityRotation(targetEntity, 2)
        forward, right, up = rotationToBasis(rot.x, rot.y, rot.z)
    end
    right   = vecScale(right, scaleX)
    forward = vecScale(forward, scaleY)
    up      = vecScale(up, scaleZ)
    local ok = pcall(function()
        SetEntityMatrix(targetEntity,
            forward.x, forward.y, forward.z,
            right.x, right.y, right.z,
            up.x, up.y, up.z,
            pos.x, pos.y, pos.z
        )
    end)

end

local function setEntityScaleSafe(entity, scaleValue)
    local s = math.max(0.01, scaleValue + 0.0)
    SetEntityScaleMatrix(entity, s, s, s)
end

local function applyEntityScale(entity, scaleState)
    local g = scaleState.global or 0.0
    local x = scaleState.x or 0.0
    local y = scaleState.y or 0.0
    local z = scaleState.z or 0.0
    local scaleX = math.max(0.01, 1.0 + g + x)
    local scaleY = math.max(0.01, 1.0 + g + y)
    local scaleZ = math.max(0.01, 1.0 + g + z)
    SetEntityScaleMatrix(entity, scaleX, scaleY, scaleZ)
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

local function handleKeyboardControls()
    if IsDisabledControlJustPressed(0, GIZMO_KEYS.freecam) then
        setView(state.view == 'gizmo' and 'freecam' or 'gizmo')
    end

    if state.view == 'freecam' then
        if IsDisabledControlJustPressed(0, GIZMO_KEYS.hideCursor) then
            state.cursorHidden = not state.cursorHidden
            setNuiCursorState()
        elseif IsDisabledControlJustPressed(0, 241) and LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then
            LF_GizmoCamera.AdjustSpeed(-120)
        elseif IsDisabledControlJustPressed(0, 242) and LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then
            LF_GizmoCamera.AdjustSpeed(120)
        end

        if IsDisabledControlJustPressed(0, 348) and LF_GizmoCamera and LF_GizmoCamera.ResetSpeed then
            LF_GizmoCamera.ResetSpeed()
        end

        if IsDisabledControlJustPressed(0, 157) then
            setMode('translate')
        elseif IsDisabledControlJustPressed(0, 158) then
            setMode('rotate')
        elseif IsDisabledControlJustPressed(0, GIZMO_KEYS.toggle) then
            setMode(state.mode == 'translate' and 'rotate' or 'translate')
        end
    end

    if state.view == 'gizmo' then
        if IsDisabledControlJustPressed(0, GIZMO_KEYS.hideCursor) then
            state.cursorHidden = not state.cursorHidden
            setNuiCursorState()
        elseif not state.cursorHidden then
            if IsDisabledControlJustPressed(0, 157) then
                setMode('translate')
            elseif IsDisabledControlJustPressed(0, 158) then
                setMode('rotate')
            elseif IsDisabledControlJustPressed(0, GIZMO_KEYS.toggle) then
                setMode(state.mode == 'translate' and 'rotate' or 'translate')
            end
        end
    end

    if state.entity ~= 0 and DoesEntityExist(state.entity)
        and (state.view == 'gizmo' and not state.cursorHidden or state.view == 'freecam')
        and IsDisabledControlJustPressed(0, GIZMO_KEYS.snap)
    then
        PlaceObjectOnGroundProperly_2(state.entity)
        if state.scale then
            applyEntityScale(state.entity, state.scale)
        end
    end

    if (state.onDuplicate or (state.allowDuplicate and state.duplicateHandler)) and state.entity ~= 0 and DoesEntityExist(state.entity)
        and (state.view == 'gizmo' and not state.cursorHidden or state.view == 'freecam')
        and IsDisabledControlJustPressed(0, GIZMO_KEYS.duplicate)
    then
        dbgPlacement('[lfobject_gizmo DUPLICATE] Touche C pressée: entity=' .. tostring(state.entity) .. ' view=' .. tostring(state.view))
        local scale = state.scale and { g = state.scale.global or 0, x = state.scale.x or 0, y = state.scale.y or 0, z = state.scale.z or 0 } or nil

        local savedAllowed = state.allowedEntities
        local newEntity
        if state.onDuplicate then
            newEntity = state.onDuplicate(state.entity, scale)
        elseif state.duplicateHandler and GetResourceState(state.duplicateHandler) == 'started' and exports[state.duplicateHandler] and exports[state.duplicateHandler].GizmoDuplicate then
            newEntity = exports[state.duplicateHandler]:GizmoDuplicate(state.entity, scale)
        end

        if savedAllowed and state.allowedEntities ~= savedAllowed then
            state.allowedEntities = savedAllowed
        end
        dbgPlacement('[lfobject_gizmo DUPLICATE] retour: newEntity=' .. tostring(newEntity) .. ' DoesExist=' .. tostring(newEntity and DoesEntityExist(newEntity)))
        if newEntity and newEntity ~= 0 and DoesEntityExist(newEntity) then
            if state.allowedEntities then
                state.allowedEntities[newEntity] = true
            end
            switchEntity(newEntity)
            dbgPlacement('[lfobject_gizmo DUPLICATE] Switch effectué vers entity=' .. tostring(newEntity))
        end
    end

    if (state.onDelete or (state.allowDelete and state.deleteHandler)) and state.entity ~= 0 and DoesEntityExist(state.entity)
        and (state.view == 'gizmo' and not state.cursorHidden or state.view == 'freecam')
        and IsDisabledControlJustPressed(0, GIZMO_KEYS.delete)
    then
        local deleted = false
        if state.onDelete then
            deleted = state.onDelete(state.entity)
        elseif state.deleteHandler and GetResourceState(state.deleteHandler) == 'started' and exports[state.deleteHandler] and type(exports[state.deleteHandler].GizmoDelete) == 'function' then
            deleted = exports[state.deleteHandler]:GizmoDelete(state.entity)
        end
        if deleted then
            finish('cancel')
        end
    end

    if IsDisabledControlJustPressed(0, GIZMO_KEYS.confirm) then
        finish('confirm')
    elseif IsDisabledControlJustPressed(0, GIZMO_KEYS.cancel) then
        finish('cancel')
    end
end

local function clampScaleOffset(v)
    if v < SCALE_OFFSET_MIN then return SCALE_OFFSET_MIN end
    if v > SCALE_OFFSET_MAX then return SCALE_OFFSET_MAX end
    return v
end

local function getModelExtent(entity, comp, scaleState)
    local model = GetEntityModel(entity)
    if not model or model == 0 then return 0.1 end
    local minD, maxD = GetModelDimensions(model)
    if not minD or not maxD then return 0.1 end
    local extent
    if comp == 'x' then extent = maxD.x - minD.x
    elseif comp == 'y' then extent = maxD.y - minD.y
    else extent = maxD.z - minD.z
    end
    extent = math.max(0.001, extent)
    if scaleState then
        local g = scaleState.global or 0.0
        local o = (comp == 'x') and (scaleState.x or 0.0) or (comp == 'y') and (scaleState.y or 0.0) or (scaleState.z or 0.0)
        extent = extent * (1.0 + g + o)
    end
    return extent
end

local function getPropAxisLengths(entity, scaleState)
    if not entity or entity == 0 or not DoesEntityExist(entity) or IsEntityAPed(entity) then return nil end
    local extX = getModelExtent(entity, 'x', scaleState)
    local extY = getModelExtent(entity, 'y', scaleState)
    local extZ = getModelExtent(entity, 'z', scaleState)
    local minLen = CONFIG.axisLengthMin
    return {
        x = math.max(minLen, extX * 0.5),
        y = math.max(minLen, extY * 0.5),
        z = math.max(minLen, extZ * 0.5)
    }
end

local function applyDrag()
    if not state.dragging then return end
    local drag = state.dragging
    local camPos, rayDir = getCamRay()

    local ratio = state.ratio or 1.0

    if drag.scaleDrag and state.scale and drag.initialScale then
        if drag.kind == 'axis' then
            local comp = drag.scaleAxis
            if not comp then return end
            local baseExtent = getModelExtent(state.entity, comp, nil)
            local scaledExtent = getModelExtent(state.entity, comp, state.scale)
            local basePos = sub(drag.startPos, mul(drag.axis, scaledExtent * 0.5))
            local n = cross(rayDir, drag.axis)
            local planeNorm = (length(n) >= 0.0001) and normalize(cross(n, drag.axis)) or nil
            local hit = planeNorm and rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
            if not hit then
                local farPoint = add(camPos, mul(rayDir, 50.0))
                hit = farPoint
            end
            local hitT = dot(sub(hit, basePos), drag.axis)
            local scaleVal = hitT / baseExtent
            local g = state.scale.global or 0.0
            state.scale[comp] = clampScaleOffset(scaleVal - 1.0 - g)
            applyEntityScale(state.entity, state.scale)
            SendNUIMessage({ action = 'setScale', global = state.scale.global, x = state.scale.x, y = state.scale.y, z = state.scale.z })
        elseif drag.kind == 'plane' and drag.scaleAxes then
            if not drag.initialHit then return end
            local planeNorm = normalize(cross(drag.axisA, drag.axisB))
            local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
            local delta
            if hit then
                delta = sub(hit, drag.initialHit)
            else
                local farPoint = add(camPos, mul(rayDir, 50.0))
                delta = sub(farPoint, drag.initialHit)
            end
            local deltaA = dot(delta, drag.axisA) * ratio * SCALE_DRAG_SENSITIVITY
            local deltaB = dot(delta, drag.axisB) * ratio * SCALE_DRAG_SENSITIVITY
            local c1, c2 = drag.scaleAxes[1], drag.scaleAxes[2]
            if c1 then state.scale[c1] = clampScaleOffset((drag.initialScale[c1] or 0.0) + deltaA) end
            if c2 then state.scale[c2] = clampScaleOffset((drag.initialScale[c2] or 0.0) + deltaB) end
            applyEntityScale(state.entity, state.scale)
            SendNUIMessage({ action = 'setScale', global = state.scale.global, x = state.scale.x, y = state.scale.y, z = state.scale.z })
        end
        return
    end

    if drag.kind == 'axis' then

        if not drag.initialT then return end
        local n = cross(rayDir, drag.axis)
        if length(n) < 0.0001 then return end
        local planeNorm = normalize(cross(n, drag.axis))
        local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
        if not hit then return end

        local t1 = dot(sub(hit, drag.startPos), drag.axis)
        local deltaT = (t1 - drag.initialT) * ratio
        local newPos = add(drag.startPos, mul(drag.axis, deltaT))
        SetEntityCoordsNoOffset(state.entity, newPos.x, newPos.y, newPos.z, true, true, true)
        drag._dbgAxisFrames = (drag._dbgAxisFrames or 0) + 1
        if drag._dbgAxisFrames <= 2 or drag._dbgAxisFrames % 25 == 0 then
            local r = GetEntityRotation(state.entity, 2)
            dbgPlacement(('[lfobject_gizmo DEBUG translate axis=%s frame=%s newPos=%.4f,%.4f,%.4f rot=%.4f,%.4f,%.4f'):format(
                tostring(drag.id), tostring(drag._dbgAxisFrames), newPos.x, newPos.y, newPos.z, r.x, r.y, r.z))
        end

    elseif drag.kind == 'plane' then

        if not drag.initialHit then return end
        local planeNorm = normalize(cross(drag.axisA, drag.axisB))
        local hit = rayPlaneIntersect(camPos, rayDir, drag.startPos, planeNorm)
        if not hit then return end
        local delta = sub(hit, drag.initialHit)
        local newPos = add(drag.startPos, mul(delta, ratio))
        SetEntityCoordsNoOffset(state.entity, newPos.x, newPos.y, newPos.z, true, true, true)
        drag._dbgPlaneFrames = (drag._dbgPlaneFrames or 0) + 1
        if drag._dbgPlaneFrames <= 2 or drag._dbgPlaneFrames % 25 == 0 then
            local r = GetEntityRotation(state.entity, 2)
            dbgPlacement(('[lfobject_gizmo DEBUG translate plane=%s frame=%s newPos=%.4f,%.4f,%.4f rot=%.4f,%.4f,%.4f'):format(
                tostring(drag.id), tostring(drag._dbgPlaneFrames), newPos.x, newPos.y, newPos.z, r.x, r.y, r.z))
        end

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
        if dot(cross(prev, toHit), drag.localAxis) < 0 then
            deltaAngle = -deltaAngle
        end

        drag.prevHit = toHit
        drag.totalAngle = drag.totalAngle + deltaAngle * ratio

        local qDelta = quatFromAxisAngle(drag.localAxis, drag.totalAngle)
        local qNew   = quatNormalize(quatMul(qDelta, drag.startQuat))

        local fwd, right, up = quatToBasisStd(qNew)
        local pos = GetEntityCoords(state.entity)
        local scX, scY, scZ = 1.0, 1.0, 1.0
        if state.scale then
            local g = state.scale.global or 0.0
            scX = math.max(0.01, 1.0 + g + (state.scale.x or 0.0))
            scY = math.max(0.01, 1.0 + g + (state.scale.y or 0.0))
            scZ = math.max(0.01, 1.0 + g + (state.scale.z or 0.0))
        end
        pcall(SetEntityMatrix, state.entity,
            fwd.x   * scY, fwd.y   * scY, fwd.z   * scY,
            right.x * scX, right.y * scX, right.z * scX,
            up.x    * scZ, up.y    * scZ, up.z    * scZ,
            pos.x, pos.y, pos.z)

        drag._dbgRingFrames = (drag._dbgRingFrames or 0) + 1
        local totalDeg = math.deg(drag.totalAngle)
        local lastLogDeg = drag._dbgLastLogDeg or 1e9
        if drag._dbgRingFrames <= 2 or math.abs(totalDeg - lastLogDeg) >= 1.0 then
            drag._dbgLastLogDeg = totalDeg
            local rxQ, ryQ, rzQ = quatToEulerOrder2(qNew)
            local after = GetEntityRotation(state.entity, 2)
            dbgPlacement(('[lfobject_gizmo DEBUG ring=%s frame=%s totalDeg=%.3f quatEuler=%.4f,%.4f,%.4f getEuler=%.4f,%.4f,%.4f'):format(
                tostring(drag.id), tostring(drag._dbgRingFrames), totalDeg,
                rxQ, ryQ, rzQ, after.x, after.y, after.z))
        end
    end
end

local function beginDrag(handle)
    if not handle then return end
    local data = {
        id   = handle.id,
        kind = handle.kind
    }

    local scaleDragAllowed = (state.mode == 'translate' and state.view == 'freecam' and state.scale and not IsEntityAPed(state.entity)
        and (handle.kind == 'axis' or handle.kind == 'plane')
        and IsDisabledControlPressed(0, GIZMO_KEYS.scaleModifier))
    if scaleDragAllowed then
        data.scaleDrag = true
        data.initialScale = {
            global = state.scale.global or 0.0,
            x = state.scale.x or 0.0,
            y = state.scale.y or 0.0,
            z = state.scale.z or 0.0
        }
        if handle.kind == 'axis' then
            if handle.id == 'axis_x' then data.scaleAxis = 'x'
            elseif handle.id == 'axis_y' then data.scaleAxis = 'y'
            elseif handle.id == 'axis_z' then data.scaleAxis = 'z'
            end
        else
            if handle.id == 'plane_xy' then data.scaleAxes = { 'x', 'y' }
            elseif handle.id == 'plane_xz' then data.scaleAxes = { 'x', 'z' }
            elseif handle.id == 'plane_yz' then data.scaleAxes = { 'y', 'z' }
            end
        end
    end

    if handle.kind == 'axis' then
        data.axis     = handle.axis
        data.startPos = GetEntityCoords(state.entity)
        local camPos, rayDir = getCamRay()
        local n = cross(rayDir, handle.axis)
        if length(n) >= 0.0001 then
            local planeNorm = normalize(cross(n, handle.axis))
            local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, planeNorm)
            if hit then
                data.initialT = dot(sub(hit, data.startPos), handle.axis)
            end
        end
    elseif handle.kind == 'plane' then
        data.axisA    = handle.axisA
        data.axisB    = handle.axisB
        data.startPos = GetEntityCoords(state.entity)
        local camPos, rayDir = getCamRay()
        local planeNorm = normalize(cross(handle.axisA, handle.axisB))
        local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, planeNorm)
        if hit then
            data.initialHit = hit
        end
    else

        data.localAxis  = normalize(handle.axis)
        data.startPos   = GetEntityCoords(state.entity)
        local startRot  = GetEntityRotation(state.entity, 2)
        data.startQuat  = quatNormalize(eulerOrder2ToQuat(startRot.x, startRot.y, startRot.z))
        data.totalAngle = 0.0

        dbgPlacement(('[lfobject_gizmo DEBUG beginDrag ring=%s startEuler=%.4f,%.4f,%.4f localAxis=%.4f,%.4f,%.4f'):format(
            tostring(handle.id), startRot.x, startRot.y, startRot.z,
            data.localAxis.x, data.localAxis.y, data.localAxis.z))

        local camPos, rayDir = getCamRay()
        local hit = rayPlaneIntersect(camPos, rayDir, data.startPos, data.localAxis)
        if hit then
            local toHit = sub(hit, data.startPos)
            if length(toHit) > 0.0001 then
                data.startHit = normalize(toHit)
            end
        else

            local proj = sub(rayDir, mul(data.localAxis, dot(rayDir, data.localAxis)))
            if length(proj) > 0.0001 then
                data.startHit = normalize(proj)
            end
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
        if state.view == 'gizmo' or state.view == 'freecam' then setMode('translate') end
    elseif action == 'mode_rotate' then
        if state.view == 'gizmo' or state.view == 'freecam' then setMode('rotate') end
    elseif action == 'mode_toggle' then
        if state.view == 'gizmo' or state.view == 'freecam' then
            setMode(state.mode == 'translate' and 'rotate' or 'translate')
        end
    elseif action == 'mode_freecam' then
        setView(state.view == 'gizmo' and 'freecam' or 'gizmo')
    elseif action == 'confirm' then
        finish('confirm')
    elseif action == 'cancel' then
        finish('cancel')
    elseif action == 'snap' then
        if state.entity ~= 0 and DoesEntityExist(state.entity)
            and ((state.view == 'gizmo' and not state.cursorHidden) or state.view == 'freecam')
        then
            PlaceObjectOnGroundProperly_2(state.entity)
            if state.scale then
                applyEntityScale(state.entity, state.scale)
            end
        end
    elseif action == 'duplicate' then
        dbgPlacement('[lfobject_gizmo DUPLICATE] Action duplicate reçue (NUI): allowDuplicate=' .. tostring(state.allowDuplicate) .. ' handler=' .. tostring(state.duplicateHandler) .. ' entity=' .. tostring(state.entity))
        if (state.onDuplicate or (state.allowDuplicate and state.duplicateHandler)) and state.entity ~= 0 and DoesEntityExist(state.entity)
            and ((state.view == 'gizmo' and not state.cursorHidden) or state.view == 'freecam')
        then
            local scale = state.scale and { g = state.scale.global or 0, x = state.scale.x or 0, y = state.scale.y or 0, z = state.scale.z or 0 } or nil
            local savedAllowed = state.allowedEntities
            local newEntity
            if state.onDuplicate then
                newEntity = state.onDuplicate(state.entity, scale)
            elseif state.duplicateHandler and GetResourceState(state.duplicateHandler) == 'started' and exports[state.duplicateHandler] and exports[state.duplicateHandler].GizmoDuplicate then
                newEntity = exports[state.duplicateHandler]:GizmoDuplicate(state.entity, scale)
            end
            if savedAllowed and state.allowedEntities ~= savedAllowed then
                state.allowedEntities = savedAllowed
            end
            dbgPlacement('[lfobject_gizmo DUPLICATE] retour (NUI): newEntity=' .. tostring(newEntity))
            if newEntity and newEntity ~= 0 and DoesEntityExist(newEntity) then
                if state.allowedEntities then
                    state.allowedEntities[newEntity] = true
                end
                switchEntity(newEntity)
            end
        end
    elseif action == 'delete' then
        if (state.onDelete or (state.allowDelete and state.deleteHandler)) and state.entity ~= 0 and DoesEntityExist(state.entity)
            and ((state.view == 'gizmo' and not state.cursorHidden) or state.view == 'freecam')
        then
            local deleted = false
            if state.onDelete then
                deleted = state.onDelete(state.entity)
            elseif state.deleteHandler and GetResourceState(state.deleteHandler) == 'started' and exports[state.deleteHandler] and type(exports[state.deleteHandler].GizmoDelete) == 'function' then
                deleted = exports[state.deleteHandler]:GizmoDelete(state.entity)
            end
            if deleted then
                finish('cancel')
            end
        end
    elseif action == 'ratio_delta' then
        local delta = tonumber(data.delta) or 0
        if state.view == 'freecam' then
            if LF_GizmoCamera and LF_GizmoCamera.AdjustSpeed then
                LF_GizmoCamera.AdjustSpeed(delta)
            end
        else
            state.ratio = state.ratio - delta * RATIO_SCROLL_FACTOR
            state.ratio = math.max(RATIO_MIN, math.min(RATIO_MAX, state.ratio))
        end
    elseif action == 'ratio_reset' then
        if state.view == 'freecam' then
            if LF_GizmoCamera and LF_GizmoCamera.ResetSpeed then
                LF_GizmoCamera.ResetSpeed()
            end
        else
            state.ratio = RATIO_DEFAULT
        end
    elseif action == 'toggle_cursor' then
        if state.view == 'gizmo' or state.view == 'freecam' then
            state.cursorHidden = not state.cursorHidden
            setNuiCursorState()
        end
    end

    cb(1)
end)

RegisterNUICallback('gizmoSetPosition', function(data, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) then
        cb(1)
        return
    end
    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
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
    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
    if x ~= nil and y ~= nil and z ~= nil then
        SetEntityRotation(state.entity, x + 0.0, y + 0.0, z + 0.0, 2, true)
        if state.scale then
            applyEntityScale(state.entity, state.scale)
        end
        local after = GetEntityRotation(state.entity, 2)
        dbgPlacement(('[lfobject_gizmo DEBUG NUI gizmoSetRotation set=%.4f,%.4f,%.4f getEuler=%.4f,%.4f,%.4f'):format(
            x, y, z, after.x, after.y, after.z))
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
    if state.scale then
        applyEntityScale(state.entity, state.scale)
    end
    cb(1)
end)

RegisterNUICallback('gizmoSetScale', function(data, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) then
        cb(1)
        return
    end
    local g, x, y, z = tonumber(data.global), tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if g ~= nil then state.scale.global = g end
    if x ~= nil then state.scale.x      = x end
    if y ~= nil then state.scale.y      = y end
    if z ~= nil then state.scale.z      = z end
    applyEntityScale(state.entity, state.scale)
    cb(1)
end)

RegisterNUICallback('gizmoResetScale', function(_, cb)
    if not state.active or not state.entity or not DoesEntityExist(state.entity) then
        cb(1)
        return
    end
    state.scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }
    setEntityScaleSafe(state.entity, 1.0)
    SendNUIMessage({ action = 'resetScale' })
    cb(1)
end)

local function freecamRaycast()
    if not cameraIsActive() then
        return nil
    end
    local camPos = LF_GizmoCamera.GetCoord()
    local camRot = LF_GizmoCamera.GetRot()

    local yaw   = math.rad(camRot.z)
    local pitch = math.rad(camRot.x)
    local fx = -math.sin(yaw) * math.cos(pitch)
    local fy =  math.cos(yaw) * math.cos(pitch)
    local fz =  math.sin(pitch)

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
        if etype == 3 and entityHit ~= ped then
            return entityHit
        end
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
    if not IsEntityAPed(ent) then

        SetEntityDrawOutlineShader(1)
        SetEntityDrawOutline(ent, true)
    else
        SetEntityAlpha(ent, 200)
    end
end

local function saveEntityState(ent, into)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end
    local pivot = GetEntityCoords(ent)
    local rot = GetEntityRotation(ent, 2)
    into[ent] = {
        position = pivot,
        rotation = rot,
        taille = state.scale and { g = state.scale.global or 0, x = state.scale.x or 0, y = state.scale.y or 0, z = state.scale.z or 0 } or { g = 0, x = 0, y = 0, z = 0 }
    }
    local baseStr = 'n/a'
    if GetResourceState('lfPropsPlacer') == 'started' then
        local ok, t = pcall(function()
            return exports['lfPropsPlacer']:GetEntityBaseCoordsTable(ent)
        end)
        if ok and t and t.x then
            baseStr = ('%.4f,%.4f,%.4f'):format(t.x, t.y, t.z)
        end
    end
    dbgPlacement(('[lfobject_gizmo DEBUG saveEntityState] ent=%s pivot=%.4f,%.4f,%.4f base[%s] euler=%.4f,%.4f,%.4f'):format(
        tostring(ent), pivot.x, pivot.y, pivot.z, baseStr, rot.x, rot.y, rot.z))
end

function switchEntity(newEntity)
    local old = state.entity
    if old == newEntity then return end

    if old and old ~= 0 and DoesEntityExist(old) then
        saveEntityState(old, state.modifiedEntities)
    end

    restoreEntity(old)

    state.entity = newEntity or 0
    state.hovered = nil
    state.dragging = nil
    state.scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }

    if newEntity and newEntity ~= 0 and DoesEntityExist(newEntity) then
        if not state.initialStates[newEntity] then
            state.initialStates[newEntity] = {
                position = GetEntityCoords(newEntity),
                rotation = GetEntityRotation(newEntity, 2),
                scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }
            }
        end
        prepareEntity(newEntity)
    end

    SendNUIMessage({ action = 'resetScale' })
end

local function gizmoLoop(entity)
    state.view   = 'gizmo'
    state.cursorHidden = false
    openUi()
    state.hovered = nil
    state.dragging = nil
    state.ratio  = RATIO_DEFAULT
    state.scale  = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }
    state.modifiedEntities = {}
    state.initialStates = {}

    GizmoScaleform = createGizmoScaleform()

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        state.initialStates[entity] = {
            position = GetEntityCoords(entity),
            rotation = GetEntityRotation(entity, 2),
            scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }
        }
    end

    prepareEntity(entity)

    local firstIter = true
    while state.active do
        Wait(0)

        local currentEntity = state.entity
        local hasEntity = currentEntity ~= 0 and DoesEntityExist(currentEntity)

        if firstIter then firstIter = false end

        if state.view == 'gizmo' and not hasEntity then
            break
        end

        local blockMovement = (state.view == 'freecam') or (state.view == 'gizmo' and not state.cursorHidden)

        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 23, true)
        DisableControlAction(0, 47, true)
        DisableControlAction(0, GIZMO_KEYS.cancel, true)
        DisableControlAction(0, GIZMO_KEYS.scaleModifier, true)
        if state.onDuplicate or (state.allowDuplicate and state.duplicateHandler) then
            DisableControlAction(0, GIZMO_KEYS.duplicate, true)
        end
        if state.onDelete or (state.allowDelete and state.deleteHandler) then
            DisableControlAction(0, GIZMO_KEYS.delete, true)
        end
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
            if LF_GizmoCamera and LF_GizmoCamera.Update then
                LF_GizmoCamera.Update()
            end
            if state.cursorHidden then
                mouse.x = 0.5
                mouse.y = 0.5
                mouse.justPressed = IsDisabledControlJustPressed(0, 24)
                mouse.justReleased = IsDisabledControlJustReleased(0, 24)
                if mouse.justPressed then
                    mouse.down = true
                elseif mouse.justReleased then
                    mouse.down = false
                end
            end
        elseif state.view == 'gizmo' and state.cursorHidden then
            updateMouseFromGame()
        end

        if GizmoScaleform then
            setScaleformParams(GizmoScaleform, buildGizmoScaleformData())
            DrawScaleformMovieFullscreen(GizmoScaleform, 255, 255, 255, 255, 0)
        end

        local drawItems = {}
        local selectedId = ''
        local entityPos = hasEntity and GetEntityCoords(currentEntity) or v3(0.0, 0.0, 0.0)
        local entityRot = hasEntity and GetEntityRotation(currentEntity, 2) or v3(0.0, 0.0, 0.0)

        local rdx, rdy, rdz = rotationForDisplay(entityRot.x, entityRot.y, entityRot.z)

        if hasEntity and (not state.cursorHidden or state.view == 'freecam') then
            local center = entityPos
            local scale = getGizmoScale(center)
            local axes = getAxes(currentEntity)
            local axisLengths
            if state.mode == 'translate' and state.view == 'freecam' and state.scale and not IsEntityAPed(currentEntity)
                and IsDisabledControlPressed(0, GIZMO_KEYS.scaleModifier)
            then
                axisLengths = getPropAxisLengths(currentEntity, state.scale)
            end
            local handles = state.mode == 'translate' and getTranslateHandles(center, axes, scale, axisLengths) or getRotateHandles(center, axes)

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
                state.hovered = pickHandle(center, scale, handles)
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

                        if state.allowedEntities then
                            dbgPlacement('[lfobject_gizmo] Clic freecam: hitEntity=' .. tostring(hitEntity) .. ' filterOk=' .. tostring(filterOk) .. ' allowed=' .. tostring(state.allowedEntities[hitEntity] == true or state.allowedEntities[tostring(hitEntity)] == true))
                        end
                        if filterOk then
                            switchEntity(hitEntity)
                        end
                    else
                        if not state.entityFilter and not state.allowedEntities then
                            switchEntity(0)
                        end
                    end
                end
            elseif mouse.justReleased then

                if state.dragging and state.dragging.kind == 'ring' and hasEntity then
                    local d = state.dragging
                    local after = GetEntityRotation(currentEntity, 2)
                    local heading = GetEntityHeadingFromEulers(currentEntity)
                    dbgPlacement(('[lfobject_gizmo DEBUG ring=%s END totalDeg=%.3f euler=%.4f,%.4f,%.4f physHeading=%.4f'):format(
                        tostring(d.id), math.deg(d.totalAngle or 0.0),
                        after.x, after.y, after.z, heading))
                end
                state.dragging = nil
            end

            if mouse.down and state.dragging then
                applyDrag()

                if state.dragging and state.dragging.scaleDrag and state.scale and hasEntity and not IsEntityAPed(currentEntity) then
                    applyEntityScale(currentEntity, state.scale)
                end
            end

            selectedId = state.dragging and state.dragging.id or (state.hovered and state.hovered.id or '')
            drawItems = buildDrawData(center, scale, handles, selectedId, state.dragging)
        elseif not hasEntity and state.view == 'freecam' and not state.lockEntity then
            if mouse.justPressed then
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
                        if filterOk then
                            switchEntity(hitEntity)
                        end
                    end
            end
            if mouse.justReleased then
                mouse.down = false
            end
        end

        SendNUIMessage({
            action   = 'draw',
            items    = drawItems,
            cursor   = { x = mouse.x, y = mouse.y },
            view     = state.view,
            centerCursor = state.view == 'freecam' and state.cursorHidden,
            hideGizmo = (state.view == 'gizmo' and state.cursorHidden) or not hasEntity,
            mode     = state.mode,
            selected = selectedId,
            position = { x = entityPos.x, y = entityPos.y, z = entityPos.z },
            rotation = { x = rdx, y = rdy, z = rdz }
        })

        mouse.justPressed  = false
        mouse.justReleased = false
    end

    if GizmoScaleform then
        SetScaleformMovieAsNoLongerNeeded(GizmoScaleform)
        GizmoScaleform = nil
    end

    if LF_GizmoCamera and LF_GizmoCamera.Stop then
        LF_GizmoCamera.Stop()
    end

    if state.entity ~= 0 and state.entity ~= entity then
        restoreEntity(state.entity)
    end

    restoreEntity(entity)

    closeUi()
end

local function useGizmo(entity, options)
    if state.active then
        return {
            handle = entity,
            position = GetEntityCoords(entity),
            rotation = GetEntityRotation(entity, 2),
            result = 'busy'
        }
    end

    if not DoesEntityExist(entity) then
        return {
            handle = entity,
            position = v3(0.0, 0.0, 0.0),
            rotation = v3(0.0, 0.0, 0.0),
            result = 'invalid'
        }
    end

    local opts = options or {}
    local mode = opts.mode or (opts.lockEntity and 'user' or 'admin')
    if opts.lockEntity ~= nil then
        state.lockEntity = opts.lockEntity == true
    else
        state.lockEntity = (mode == 'user' and type(opts.entityFilter) ~= 'function' and not (type(opts.allowedEntities) == 'table'))
    end
    state.entityFilter = type(opts.entityFilter) == 'function' and opts.entityFilter or nil
    state.allowedEntities = type(opts.allowedEntities) == 'table' and opts.allowedEntities or nil
    state.onDuplicate = type(opts.onDuplicate) == 'function' and opts.onDuplicate or nil
    state.allowDuplicate = opts.allowDuplicate == true and type(opts.duplicateHandler) == 'string' and opts.duplicateHandler or nil
    state.duplicateHandler = state.allowDuplicate and opts.duplicateHandler or nil
    state.onDelete = type(opts.onDelete) == 'function' and opts.onDelete or nil
    state.allowDelete = opts.allowDelete == true and type(opts.deleteHandler) == 'string' and opts.deleteHandler or nil
    state.deleteHandler = state.allowDelete and opts.deleteHandler or nil
    if state.allowDuplicate and state.duplicateHandler then
        dbgPlacement('[lfobject_gizmo DUPLICATE] useGizmo: allowDuplicate + duplicateHandler=' .. tostring(state.duplicateHandler) .. ' (touche C disponible)')
    end
    if state.onDelete or (state.allowDelete and state.deleteHandler) then
        dbgPlacement('[lfobject_gizmo DELETE] useGizmo: onDelete ou deleteHandler disponible (touche Suppr)')
    end

    state.gizmoFlag = type(opts.gizmoFlag) == 'string' and opts.gizmoFlag or nil

    state.active = true
    state.entity = entity
    state.mode = 'translate'
    state.view = 'gizmo'
    state.result = 'cancel'

    if type(opts.initialScale) == 'table' then
        local s = opts.initialScale
        state.scale = { global = s.global or s.g or 0.0, x = s.x or 0.0, y = s.y or 0.0, z = s.z or 0.0 }
    else
        state.scale = { global = 0.0, x = 0.0, y = 0.0, z = 0.0 }
    end
    state.initialPos = GetEntityCoords(entity)
    state.initialRot = GetEntityRotation(entity, 2)
    dbgPlacement(('[lfobject_gizmo DEBUG useGizmo START ent=%s pivot=%.4f,%.4f,%.4f euler=%.4f,%.4f,%.4f'):format(
        tostring(entity), state.initialPos.x, state.initialPos.y, state.initialPos.z,
        state.initialRot.x, state.initialRot.y, state.initialRot.z))
    state.lastUiTick = 0

    gizmoLoop(entity)
    state.active = false

    if state.result == 'confirm' then
        if state.entity and state.entity ~= 0 and DoesEntityExist(state.entity) then
            saveEntityState(state.entity, state.modifiedEntities)
        end
    elseif state.result == 'cancel' then
        for ent, init in pairs(state.initialStates or {}) do
            if DoesEntityExist(ent) then
                SetEntityCoordsNoOffset(ent, init.position.x, init.position.y, init.position.z, true, true, true)
                SetEntityRotation(ent, init.rotation.x, init.rotation.y, init.rotation.z, 2, true)
                if init.scale then
                    applyEntityScale(ent, init.scale)
                else
                    setEntityScaleSafe(ent, 1.0)
                end
            end
        end
    end

    local modifications = {}
    if state.result == 'confirm' and state.modifiedEntities then
        for ent, data in pairs(state.modifiedEntities) do
            if DoesEntityExist(ent) then
                modifications[#modifications + 1] = {
                    entity = ent,
                    position = data.position,
                    rotation = data.rotation,
                    taille = data.taille or { g = 0, x = 0, y = 0, z = 0 }
                }
            end
        end
    end

    if state.result == 'confirm' then
        dbgPlacement('[lfobject_gizmo DEBUG useGizmo confirm] modifications count=' .. tostring(#modifications))
        for i, m in ipairs(modifications) do
            local p, r = m.position, m.rotation
            dbgPlacement(('[lfobject_gizmo DEBUG useGizmo mod[%s] ent=%s pivot_saved=%.4f,%.4f,%.4f rot_saved=%.4f,%.4f,%.4f taille g=%s'):format(
                tostring(i), tostring(m.entity),
                p and p.x or -1, p and p.y or -1, p and p.z or -1,
                r and r.x or -1, r and r.y or -1, r and r.z or -1,
                tostring(m.taille and m.taille.g)))
        end
        local ent = entity
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            local pivot = GetEntityCoords(ent)
            local euler = GetEntityRotation(ent, 2)
            dbgPlacement(('[lfobject_gizmo DEBUG useGizmo confirm LIVE ent=%s pivot=%.4f,%.4f,%.4f euler=%.4f,%.4f,%.4f'):format(
                tostring(ent), pivot.x, pivot.y, pivot.z, euler.x, euler.y, euler.z))
        end
    end

    local output = {
        handle = entity,
        position = DoesEntityExist(entity) and GetEntityCoords(entity) or state.initialPos,
        rotation = DoesEntityExist(entity) and GetEntityRotation(entity, 2) or state.initialRot,
        result = state.result,
        taille = state.scale and { g = state.scale.global or 0, x = state.scale.x or 0, y = state.scale.y or 0, z = state.scale.z or 0 } or nil,
        modifications = modifications
    }

    state.entity = 0
    state.view = 'gizmo'
    state.hovered = nil
    state.dragging = nil
    state.lockEntity = false
    state.entityFilter = nil
    state.allowedEntities = nil
    state.onDuplicate = nil
    state.allowDuplicate = nil
    state.duplicateHandler = nil
    state.onDelete = nil
    state.allowDelete = nil
    state.deleteHandler = nil
    state.gizmoFlag = nil
    return output
end

exports('useGizmo', useGizmo)

exports('isGizmoActive', function()
    return state.active == true
end)

exports('isActive', function()
    return state.active == true
end)

exports('applyEntityScale', function(entity, scaleState)
    if not entity or not DoesEntityExist(entity) or not scaleState then return end
    local g = scaleState.global or scaleState.g or 0.0
    local x = scaleState.x or 0.0
    local y = scaleState.y or 0.0
    local z = scaleState.z or 0.0
    applyEntityScale(entity, { global = g, x = x, y = y, z = z })
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceClose()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    forceClose()
end)

