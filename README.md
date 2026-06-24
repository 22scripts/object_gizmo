# object_gizmo — 22scripts

Gizmo de manipulation d'entités (position / rotation / échelle) dessiné en NUI, avec
caméra libre (freecam). Exporté pour être utilisé par d'autres ressources (ex: `22_propsplacer`).

## Installation

1. Placer le dossier `object_gizmo` dans `resources/`.
2. Ajouter `ensure object_gizmo` au `server.cfg` (avant les ressources qui l'utilisent).
3. Dépendance : `ox_lib`.

## Exports

```lua
-- Lance une session gizmo (BLOQUANT : à appeler dans un CreateThread).
local result = exports.object_gizmo:useGizmo(entity, options)

-- Forme complète (mêmes options).
local result = exports.object_gizmo:openGizmo({ entity = entity, options = options })

-- Une session est-elle active ? (utile pour éviter de supprimer l'entité éditée)
local active = exports.object_gizmo:isGizmoActive()   -- alias : isActive()

-- Ré-applique une échelle {g,x,y,z} (offsets, 0 = natif) à une entité (respawn/streaming).
exports.object_gizmo:applyEntityScale(entity, { g = 0, x = 0, y = 0, z = 0 })
```

### Options (table, toutes optionnelles)

| Option | Type | Rôle |
|---|---|---|
| `lockEntity` | bool | Empêche de changer d'entité (clic freecam) |
| `gizmoFlag` | string | Libellé affiché dans le titre (ex: `'items'`) |
| `initialScale` | `{g,x,y,z}` | Échelle de départ (édition d'un prop déjà mis à l'échelle) |
| `allowDelete` / `onDelete(entity)` | bool / fn | Active la suppression (touche Suppr) |
| `allowDuplicate` / `onDuplicate(entity, taille)` | bool / fn | Active la duplication (touche C) |
| `entityFilter` / `allowedEntities` | fn / table | Restreint les entités sélectionnables en freecam |

### Retour

```lua
{
  result   = 'confirm' | 'cancel' | 'busy' | 'invalid',
  position = vector3,                 -- pivot final
  rotation = vector3,                 -- Euler ordre 2 (heading sur z)
  taille   = { g, x, y, z },          -- échelle (offsets, 0 = taille native)
  modifications = { { entity, position, rotation, taille }, ... },
}
```

## Contrôles

| Touche | Action |
|---|---|
| **Clic gauche** | Saisir un axe / plan / anneau du gizmo |
| **R** | Basculer Translation / Rotation |
| **F** | Basculer Gizmo / Freecam |
| **G** | Afficher / cacher le curseur |
| **Molette** | Ratio de déplacement (gizmo) / vitesse caméra (freecam) |
| **Maj (Shift)** | Coller au sol |
| **Ctrl (maintenu) + glisser** | Modifier l'échelle (en freecam, mode translation) |
| **C** | Dupliquer (si activé) |
| **Suppr** | Supprimer (si activé) |
| **Entrée** | Valider |
| **Retour arrière** | Annuler |

Les indications de touches sont affichées en bas de l'écran (scaleform INSTRUCTIONAL_BUTTONS),
**Annuler** étant placé tout à droite.

## Commande de test

`/testGizmo` — crée un prop devant le joueur et ouvre le gizmo dessus (voir `client/test.lua`).

## Notes

- `useGizmo` est **bloquant** (boucle interne) : toujours l'appeler dans un `CreateThread`.
- L'échelle utilise le format `{g,x,y,z}` (offsets, 0 = taille native), appliquée via matrice.
- Convention de rotation : Euler **ordre 2** (le heading est sur l'axe Z).
