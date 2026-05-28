const resourceName = (typeof GetParentResourceName === "function")
    ? GetParentResourceName()
    : "FGizmo";

// ─── DOM ────────────────────────────────────────────────────────────────────
const canvas     = document.getElementById("gizmo-canvas");
const ctx        = canvas.getContext("2d");
const root       = document.getElementById("root");
const titleEl    = document.getElementById("title");
const selectedEl = document.getElementById("selected-handle");
const posX       = document.getElementById("pos-x");
const posY       = document.getElementById("pos-y");
const posZ       = document.getElementById("pos-z");
const rotX       = document.getElementById("rot-x");
const rotY       = document.getElementById("rot-y");
const rotZ       = document.getElementById("rot-z");
const resetPosBtn   = document.getElementById("reset-position");
const resetRotBtn   = document.getElementById("reset-rotation");

// ─── Noms lisibles des handles ───────────────────────────────────────────────
const HANDLE_NAMES = {
    axis_x:   "Axe X (Rouge)",     axis_y:  "Axe Y (Bleu)",   axis_z:  "Axe Z (Vert)",
    plane_xy: "Plan XY — Sol",     plane_xz:"Plan XZ — Gauche", plane_yz:"Plan YZ — Droite",
    ring_x:   "Anneau X",          ring_y:  "Anneau Y",          ring_z:  "Anneau Z"
};

// ─── État ────────────────────────────────────────────────────────────────────
let isActive   = false;
let pendingDraw = null;

// ─── Canvas resize ────────────────────────────────────────────────────────────
function resizeCanvas() {
    canvas.width  = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener("resize", resizeCanvas);
resizeCanvas();

// ─── Helpers ─────────────────────────────────────────────────────────────────
function post(endpoint, payload = {}) {
    fetch(`https://${resourceName}/${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(payload)
    }).catch(() => {});
}

function px(nx) { return nx * canvas.width;  }
function py(ny) { return ny * canvas.height; }

function col(r, g, b, a = 1) { return `rgba(${r},${g},${b},${a})`; }

function formatNum(n) {
    return Number(n ?? 0).toFixed(2);
}

function setPositionInputs(v) {
    if (!v) return;
    posX.value = formatNum(v.x);
    posY.value = formatNum(v.y);
    posZ.value = formatNum(v.z);
}

function setRotationInputs(v) {
    if (!v) return;
    rotX.value = formatNum(v.x);
    rotY.value = formatNum(v.y);
    rotZ.value = formatNum(v.z);
}

function emitPosition() {
    const x = parseFloat(posX.value), y = parseFloat(posY.value), z = parseFloat(posZ.value);
    if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(z)) {
        post("gizmoSetPosition", { x, y, z });
    }
}

function emitRotation() {
    const x = parseFloat(rotX.value), y = parseFloat(rotY.value), z = parseFloat(rotZ.value);
    if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(z)) {
        post("gizmoSetRotation", { x, y, z });
    }
}

// ─── Canvas : dessin ─────────────────────────────────────────────────────────

function drawArrow(x1, y1, x2, y2, r, g, b, sel) {
    const lw      = sel ? 4.0 : 2.8;
    const headLen = sel ? 19.0  : 14.0;
    const angle   = Math.atan2(y2 - y1, x2 - x1);
    const color   = col(r, g, b);

    const tipX = x2;
    const tipY = y2;
    const stemGap = headLen * 0.65;
    const stemEndX = x2 - stemGap * Math.cos(angle);
    const stemEndY = y2 - stemGap * Math.sin(angle);

    ctx.save();

    if (sel) {
        ctx.shadowColor = color;
        ctx.shadowBlur  = 10;
    }

    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(stemEndX, stemEndY);
    ctx.strokeStyle = color;
    ctx.lineWidth   = lw;
    ctx.lineCap     = "round";
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(tipX, tipY);
    ctx.lineTo(
        tipX - headLen * Math.cos(angle - Math.PI / 5.5),
        tipY - headLen * Math.sin(angle - Math.PI / 5.5)
    );
    ctx.lineTo(
        tipX - headLen * Math.cos(angle + Math.PI / 5.5),
        tipY - headLen * Math.sin(angle + Math.PI / 5.5)
    );
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();

    ctx.restore();
}

function drawPlane(corners, r, g, b, sel) {
    if (!corners || corners.length < 4) return;
    const pts  = corners.map(p => [px(p.x), py(p.y)]);
    const c    = col(r, g, b);
    const lw   = sel ? 2.5 : 1.8;

    ctx.save();

    if (sel) {
        ctx.shadowColor = c;
        ctx.shadowBlur  = 8;
    }

    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
    ctx.fillStyle = col(r, g, b, sel ? 0.38 : 0.22);
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
    ctx.strokeStyle = c;
    ctx.lineWidth   = lw;
    ctx.stroke();

    ctx.restore();
}

function drawRing(points, r, g, b, sel) {
    if (!points || points.length < 3) return;
    const c  = col(r, g, b);
    const lw = sel ? 3.5 : 2.2;

    ctx.save();

    if (sel) {
        ctx.shadowColor = c;
        ctx.shadowBlur  = 10;
    }

    ctx.beginPath();
    ctx.moveTo(px(points[0].x), py(points[0].y));
    for (let i = 1; i < points.length; i++) {
        ctx.lineTo(px(points[i].x), py(points[i].y));
    }
    ctx.closePath();
    ctx.strokeStyle = c;
    ctx.lineWidth   = lw;
    ctx.lineJoin    = "round";
    ctx.stroke();

    ctx.restore();
}

function drawGuideline(x1, y1, x2, y2) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    const ndx = dx / len;
    const ndy = dy / len;
    const far = Math.max(canvas.width, canvas.height) * 3;

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x1 - ndx * far, y1 - ndy * far);
    ctx.lineTo(x1 + ndx * far, y1 + ndy * far);
    ctx.strokeStyle = "rgba(255,255,255,0.30)";
    ctx.lineWidth   = 1.0;
    ctx.stroke();
    ctx.restore();
}

function renderGizmo(data) {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (!data) return;

    const items = Array.isArray(data.items) ? data.items : [];
    if (items.length > 0) {
        for (const item of items) {
            if (item.kind === "axis" && item.guideline) {
                drawGuideline(px(item.x1), py(item.y1), px(item.x2), py(item.y2));
            }
        }

        const order = ["plane", "ring", "axis"];
        for (const kind of order) {
            for (const item of items) {
                if (item.kind !== kind) continue;

                if (kind === "axis") {
                    drawArrow(
                        px(item.x1), py(item.y1),
                        px(item.x2), py(item.y2),
                        item.r, item.g, item.b, item.sel
                    );
                } else if (kind === "plane") {
                    drawPlane(item.c, item.r, item.g, item.b, item.sel);
                } else if (kind === "ring") {
                    drawRing(item.pts, item.r, item.g, item.b, item.sel);
                }
            }
        }
    }

    if (data.centerCursor) {
        const cx = canvas.width * 0.5;
        const cy = canvas.height * 0.5;
        const s = 8;
        ctx.save();
        ctx.strokeStyle = "rgba(255,255,255,0.92)";
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(cx - s, cy);
        ctx.lineTo(cx + s, cy);
        ctx.moveTo(cx, cy - s);
        ctx.lineTo(cx, cy + s);
        ctx.stroke();
        ctx.restore();
    }
}

function renderLoop() {
    requestAnimationFrame(renderLoop);
    if (isActive && pendingDraw) {
        renderGizmo(pendingDraw);
    } else if (!isActive) {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
}
renderLoop();

window.addEventListener("message", (event) => {
    const data = event.data || {};

    if (data.action === "toggle") {
        isActive = !!data.active;
        root.classList.toggle("hidden", !isActive);
        if (!isActive) pendingDraw = null;
        if (isActive && data.labels) {
            titleEl.textContent = (data.labels.title || "GIZMO");
        }
        return;
    }

    if (data.action === "setView") return;

    if (data.action === "draw") {
        pendingDraw = data;
        selectedEl.textContent = `Sélection : ${HANDLE_NAMES[data.selected] || "—"}`;
        const posInputs = [posX, posY, posZ];
        const rotInputs = [rotX, rotY, rotZ];
        if (!posInputs.includes(document.activeElement)) {
            setPositionInputs(data.position);
        }
        if (!rotInputs.includes(document.activeElement)) {
            setRotationInputs(data.rotation);
        }
    }
});

document.addEventListener("mousemove", (e) => {
    if (!isActive) return;
    post("gizmoMouseMove", {
        x: e.clientX / window.innerWidth,
        y: e.clientY / window.innerHeight
    });
});
document.addEventListener("mousedown", (e) => {
    if (!isActive || e.button !== 0) return;
    if (e.target.closest("input") || e.target.closest("button")) return;
    post("gizmoMouseDown");
});
document.addEventListener("mouseup", (e) => {
    if (!isActive || e.button !== 0) return;
    if (e.target.closest("input") || e.target.closest("button")) return;
    post("gizmoMouseUp");
});

const coordInputs = [posX, posY, posZ, rotX, rotY, rotZ];
function isCoordInputFocused() {
    return coordInputs.includes(document.activeElement);
}

document.addEventListener("keydown", (e) => {
    if (!isActive) return;
    if (e.key === "Enter") {
        if (isCoordInputFocused()) return;
        post("gizmoAction", { action: "confirm" });
        return;
    }
    if      (e.key === "1")      post("gizmoAction", { action: "mode_translate" });
    else if (e.key === "2")      post("gizmoAction", { action: "mode_rotate"    });
    else if (e.key === "r" || e.key === "R") post("gizmoAction", { action: "mode_toggle" });
    else if (e.key === "f" || e.key === "F") post("gizmoAction", { action: "mode_freecam" });
    else if (e.key === "g" || e.key === "G") post("gizmoAction", { action: "toggle_cursor" });
    else if (e.key === "c" || e.key === "C") post("gizmoAction", { action: "duplicate" });
    else if (e.key === "Delete" || e.key === "Suppr") post("gizmoAction", { action: "delete" });
    else if (e.key === "Backspace") {
        if (isCoordInputFocused()) return;
        post("gizmoAction", { action: "cancel" });
    }
    else if (e.key === "Shift")  post("gizmoAction", { action: "snap"           });
});

document.addEventListener("wheel", (e) => {
    if (!isActive) return;
    e.preventDefault();
    post("gizmoAction", { action: "ratio_delta", delta: e.deltaY });
}, { passive: false });

document.addEventListener("mousedown", (e) => {
    if (!isActive || e.button !== 1) return;
    e.preventDefault();
    post("gizmoAction", { action: "ratio_reset" });
});

[posX, posY, posZ].forEach((input) => {
    input.addEventListener("blur", emitPosition);
    input.addEventListener("change", emitPosition);
    input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
            e.preventDefault();
            e.stopPropagation();
            input.blur();
        }
    });
});
[rotX, rotY, rotZ].forEach((input) => {
    input.addEventListener("blur", emitRotation);
    input.addEventListener("change", emitRotation);
    input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
            e.preventDefault();
            e.stopPropagation();
            input.blur();
        }
    });
});

resetPosBtn.addEventListener("click", () => post("gizmoResetPosition", {}));
resetRotBtn.addEventListener("click", () => post("gizmoResetRotation", {}));
