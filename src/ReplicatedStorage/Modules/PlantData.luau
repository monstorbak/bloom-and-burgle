--!strict
-- PlantData — backward-compat shim.
--
-- ADR-5 (P1.2 / 2026-05-08) renamed this module to CritterData. The "Plant"
-- name was a Hungarian-notation lie inherited from the pre-pivot design
-- (every "plant" is actually a critter). This shim re-exports CritterData
-- under the old name so:
--   - Any out-of-tree consumer that caches the require path keeps working.
--   - In-tree callers can be migrated to `CritterData` mechanically.
--
-- Removal target: one release after 2026-05-08. Search for `require.*PlantData`
-- across the tree before deleting — every hit must be migrated to
-- `require(... .CritterData)` first.

return require(script.Parent:WaitForChild("CritterData"))
