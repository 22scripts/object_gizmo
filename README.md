# FGizmo

Ressource client légère de placement 3D pour FiveM (gizmo custom, sans `DrawGizmo` natif).  
Dépendance unique : **ox_lib**. Aucun serveur, aucune base de données.

Le script parent spawn l'entité, appelle `useGizmo`, puis sauvegarde position/rotation (BDD, JSON, etc.).

## Exports

```lua
exports.FGizmo:useGizmo(entity, options?)
exports.FGizmo:isGizmoActive()
```

### Retour de `useGizmo`

```lua
{
    handle = entity,
    result = 'confirm' | 'cancel' | 'invalid' | 'busy',
    position = vector3,
    rotation = vector3,
    modifications = { { entity, position, rotation }, ... }  -- optionnel (multi-entités)
}
```

### Options

| Option | Défaut | Description |
|--------|--------|-------------|
| `lockEntity` | `true` si pas de filter | Une seule entité, pas de changement via freecam |
| `entityFilter` | `nil` | `function(ent) -> bool` pour le raycast freecam |
| `allowedEntities` | `nil` | Table `{ [entity] = true }` pour édition multi-props (admin) |
| `title` | `"Placement"` | Titre du panneau NUI |
| `allowFreecam` | `true` | Désactiver la freecam si besoin |
| `onDuplicate` | `nil` | `function(ent) -> newEntity?` (touche C) |
| `onDelete` | `nil` | `function(ent) -> bool` (touche Suppr) |

## Exemple — prop

```lua
local model = `prop_mp_cone_02`
lib.requestModel(model)
local coords = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 3.0
local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)

local result = exports.FGizmo:useGizmo(obj, {
    lockEntity = true,
    title = 'Placement prop',
})

if result.result == 'confirm' then
    -- Sauvegarder result.position et result.rotation dans votre BDD / JSON
elseif result.result == 'cancel' then
    DeleteEntity(obj)
end
```

## Exemple — ped

```lua
local model = `a_m_y_hipster_01`
lib.requestModel(model)
local coords = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 2.0
local ped = CreatePed(4, model, coords.x, coords.y, coords.z, 0.0, false, false)

local result = exports.FGizmo:useGizmo(ped, { title = 'Placement PNJ' })

if result.result == 'confirm' then
    -- Sauvegarder coords / rotation
else
    DeleteEntity(ped)
end
```

## Exemple — callbacks duplicate / delete

```lua
local result = exports.FGizmo:useGizmo(entity, {
    onDuplicate = function(ent)
        local c = GetEntityCoords(ent)
        local r = GetEntityRotation(ent, 2)
        local copy = CreateObject(GetEntityModel(ent), c.x + 1.0, c.y, c.z, false, false, false)
        SetEntityRotation(copy, r.x, r.y, r.z, 2, true)
        return copy
    end,
    onDelete = function(ent)
        DeleteEntity(ent)
        return true
    end,
})
```

## Fonctionnalités

- **Translation** : axes X / Y / Z et plans XY / XZ / YZ
- **Rotation** : anneaux X / Y / Z
- **Freecam** : navigation libre + sélection d'entité (si `lockEntity = false` ou `allowedEntities`)
- **UI NUI** : saisie coords/rotation, snap au sol, ratio de vitesse
- **Annulation** : restaure position/rotation initiales

## Contrôles

- **Clic gauche** : sélection + drag axe / plan / anneau
- **1 / 2** : translation / rotation
- **F** : basculer gizmo / freecam (si activé)
- **Shift** : coller au sol
- **Entrée** : valider
- **Retour arrière** : annuler
- **C / Suppr** : duplicate / delete (si callbacks fournis)

## Test rapide

Commande incluse :

```
testGizmo
```

Crée un cône devant le joueur, ouvre le gizmo avec callbacks duplicate/delete de démonstration.

## Installation

1. Placer la ressource `FGizmo` dans votre dossier resources
2. `ensure ox_lib`
3. `ensure FGizmo` (avant les scripts qui appellent l'export)

## Debug

Convar : `setr fgizmo:debugPlacement 1` pour activer les logs `[FGizmo]`.
