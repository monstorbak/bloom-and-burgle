# BAB-011 Playtest Guide

**Commit:** 1b664a5  
**What changed:** Plants are no longer yellow rectangles. SellPad is now a proper kiosk. Planters have visual borders.

---

## 🎬 How to Test

### 1. Open the game in Studio
```
cd ~/Dev/bloom-and-burgle
bash scripts/sync-from-studio.sh           # (if you changed anything)
bash scripts/build.sh                       # rebuild rbxlx
# Open BloomAndBurgle.rbxlx in Roblox Studio
```

### 2. Enter Play mode (Studio → Play)

### 3. Look at each of these things:

#### A. Walk to the planting area
You should see:
- **9 planting slots** in a 3x3 grid
- Each slot has a **soft green border frame** underneath (like a halo)
- Borders are **glowing** (neon material) so they're obvious

#### B. Click "SHOP" button
Buy a seed (try "Sunbloom" at 25 cash).

#### C. Go back to a planter with the green border
- Press **E** on the planter (or you'll see a prompt if we added one)
- A **plant should sprout** — NOT a yellow box, but:
  - A **stem** (greenish)
  - **Two leaves** halfway up (angled outward)
  - A **bud** forming at the top
- The green **border should disappear** (no longer empty)

#### D. Watch the plant grow
As the plant grows (takes ~60 sec for Sunbloom):
- Stem gets taller
- Leaves become more visible/opaque
- Bud swells and changes color
- Bloom appears at the top (neon, same color as species)

#### E. When ripe (100% grown)
- Bloom should **glow brighter** (neon light effect)
- Should show a **✨ emoji** floating above it
- Plant might **pulse/animate** slightly

#### F. Walk to the SELL area
You should see:
- **A proper kiosk** with:
  - Green glowing platform base
  - Silver post in the center  
  - Green neon sign with "SELL" text
  - Glowing ring around the base
  - **"Walk here to sell"** prompt above the sign

#### G. Stand on the sell pad
- Your crops should be **harvested automatically**
- You should see **cash increase**
- The ripe bloom should disappear

---

## 🚩 What I'm looking for

### ✅ Good signs:
- [ ] Plants look like actual plants (stem, leaves, flower)
- [ ] Plants grow smoothly over time (3-stage visual progression)
- [ ] Ripe plants glow and show emoji
- [ ] Planter borders are visible and disappear when planted
- [ ] Sell kiosk looks clean (no floating glitchy text)
- [ ] Sell kiosk has a "Walk here to sell" prompt
- [ ] No error spam in Output
- [ ] Harvest works (crops disappear, cash increases)

### ⚠️ Bad signs (report these):
- [ ] Plants still look like yellow boxes
- [ ] Planter borders don't appear or don't disappear when planted
- [ ] Sell kiosk is glitchy or has floating text
- [ ] Sell pad is hard to find or unclear
- [ ] Game crashes
- [ ] Output shows Lua errors

---

## 📸 How to send me feedback

1. Take screenshots of:
   - A planter **before** planting (green border visible)
   - A planter **while growing** (plant sprouting, border gone)
   - A planter **when ripe** (glowing bloom, emoji above)
   - The **sell kiosk** from different angles
   - Any **errors** in the Output panel

2. Save them to `~/Dev/bloom-and-burgle/debug/` with names like:
   - `planter-empty.png`
   - `planter-growing.png`
   - `planter-ripe.png`
   - `sell-kiosk.png`
   - `errors.png` (if any)

3. Send message: **"Screenshots in debug/ folder, [brief description]"**

---

## 🔧 If something breaks

If you see errors in Output:
1. **Copy the error message** from the Output panel
2. **Right-click → Clear** to clear the output
3. **Play again** and try to reproduce it
4. **Screenshot the error** with context
5. **Send me the error + what you did**

---

## 🎯 The real test: Does it FEEL like a game now?

Compare to the earlier screenshots:
- Is this visually more polished?
- Can you tell what to do without reading instructions?
- Does the sell area feel less weird?
- Do the plants feel rewarding to watch grow?

Send honest feedback. I'll iterate fast.

---

## 📋 Next fixes coming if needed

Based on your feedback, I'll prioritize:
1. **Different plant varieties** (not all blue/purple, actual visual variety)
2. **Harvest popups** ("+10 cash!" appears when you sell)
3. **Sounds** (planting, growing, harvesting, selling sfx)
4. **Camera improvements** (better angle to see the plot)
5. **Tutorial arrows** (pointing to SHOP, then to PLANT, then to SELL)
6. **Stealing mechanics** (make them visible and fun, not abstract)

But first, **test what I just shipped**. Is it better? What's still broken?

---

**Commit: 1b664a5**  
Push back with screenshots + feedback.
