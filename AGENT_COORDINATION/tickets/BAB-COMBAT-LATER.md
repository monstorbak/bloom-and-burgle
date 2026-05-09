# BAB-COMBAT-LATER: deferred — full PvP combat layer (revisit post-launch)

**Owner:** unassigned
**State:** **deferred — post-launch revisit**
**Priority:** P3 (deferred until telemetry from Phases 0-5 says it's needed)

## Why deferred (2026-05-08 decision)

Initially proposed as a 5-PR layer (combat foundation, NPC reactions, dialog, R15 humanoids, plot raids). The user reframed during the same session after a tighter analysis:

1. **The spec already names its viral engine — it isn't combat.** The Critter Escape Mechanic (`Bloom&Burgle_Design_Spec.md` §9.6, ticketed at `BAB-CRITTER-ESCAPE.md`) is the explicit "chaos generator" and "content generator for live stream clips." Spending 5 PRs on combat while the named viral hook sits unshipped is misallocation.
2. **PvP-with-tools makes BAB look like every other Roblox PvP sim.** The Steampunk-Ghibli aesthetic + the asset/liability matrix are the brand moat; combat is undifferentiated category noise.
3. **No telemetry yet.** Architecture eval ADR-3 still unchecked. Without funnel data, shipping a 5-PR combat layer is expensive guessing.
4. **Moderation cost the team isn't sized for.** Spec's own anti-pattern: "toxicity from stealing → heavy moderation required."

## What's NOT deferred — combat as plot defense

The "lethal critters defending plots" thread the user raised IS still in scope, but reframed as **plot-defense behaviors inside the existing Critter Escape mechanic**. See `BAB-CRITTER-ESCAPE.md` "Plot Defense Layer" section.

Specifically:
- Escaped liability critters detect raiders on the plot and damage them (no separate weapon system needed)
- Defense scales with the player's stable upgrades (later: "lethal critter upgrades" ticket TBD)
- All damage stays inside the existing Critter behavior catalog — no new Combat module

This preserves the design intent ("players must be vigilant to protect their land") without the 5-PR combat layer.

## What this ticket captures (for future revisit)

Original combat scope:

| Phase | Scope |
|---|---|
| 1 | Dialog system + branching trees per NPC |
| 2 | PvP zones + combat foundation (health, weapons, damage, zone gating) |
| 3 | NPC combat reactions + black-market reputation |
| 4 | R15 Humanoid NPCs (folded into Phase 1 of the new roadmap) |
| 5 | Plot raids — death, drops, plot damage |

If telemetry from Phases 0-5 of the new roadmap shows that:
- Engagement plateaus and players want adversarial mechanics
- Black-market reputation surfaces in player feedback
- The "I tried to raise a Coal Drake as a Knight" content template starts feeling stale

— then revisit this ticket. Until then, defer.

## Open questions to revisit

1. **Black market location.** New 4th place via TeleportService? Or a Cogworks-plaza section? (Phase 1 of original combat plan deferred this question.)
2. **Death penalty.** Cash drop, stash drop, or just respawn?
3. **Anti-grief.** Per-attacker per-plot cooldown? Owner-side invuln on home turf?
4. **Weapon model.** Roblox tools reskinned vs custom raycast?

These are the right questions to start the revisit conversation with — not "should we build it" but "what shape should it take when we do."

## Log

- 2026-05-08 — Original 5-PR combat plan superseded by the current critter-escape-first roadmap. Captured here so the design doesn't get lost.
