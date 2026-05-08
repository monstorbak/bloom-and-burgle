--!strict
-- PlantVisuals — backward-compat shim.
--
-- ADR-5 (P1.2 / 2026-05-08) renamed this module to CritterVisuals. This
-- shim re-exports CritterVisuals under the old name so consumers caching
-- the legacy require path keep working.
--
-- Removal target: one release after 2026-05-08. Search for
-- `require.*PlantVisuals` before deleting — every hit must be migrated.

return require(script.Parent:WaitForChild("CritterVisuals"))
