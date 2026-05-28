# LF Object Gizmo (Custom)

Ressource de gizmo 100% custom (sans `DrawGizmo` natif GTA/FxDK).

## Features

- Mode **deplacement**:
  - manipulation sur axe unique `X / Y / Z`
  - manipulation sur face `XY / XZ / YZ` (deplacement simultane sur 2 axes)
- Mode **rotation**:
  - rotation sur axe `X / Y / Z`
- UI NUI moderne pour piloter les actions (mode, validation, annulation, snap)

## Export

```lua
local result = exports.lfobject_gizmo:useGizmo(entity)
```

`result` contient:
- `handle`
- `position`
- `rotation`
- `result` (`confirm`, `cancel`, `invalid`, `busy`)

## Test rapide

Commande incluse:

```lua
testGizmo
```

Elle cree un objet devant le joueur puis ouvre le gizmo.

## Controles

- **Clic gauche**: selection + drag d'un axe/face/anneau
- **1**: mode deplacement
- **2**: mode rotation
- **Shift**: snap au sol
- **Enter**: valider
- **Retour arrière (Backspace)**: annuler
