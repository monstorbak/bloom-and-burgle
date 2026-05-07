# BAB-011 Playtest Guide

**Current commit:** 6ca873c  
**Last updated:** 2026-05-07 14:45 EDT

---

## What Changed (6ca873c vs Earlier)

**The Problem:** Plants grew for ~60 seconds, then **vanished silently**. Players had no idea what happened — looked like a bug.

**The Fix:** Plants now **STAY VISIBLE and RIPE**, waiting for you to walk over them to harvest.

---

## 🎬 Full Cycle to Test

### 1. Start Play in Studio

You have:
- 💰 **$10,000 cash** (dev mode auto-gives)
- 🌱 **5 Sunbloom + 5 Lavender Glow seeds** (dev mode auto-gives)
- ⚠️ **Red "DEV MODE" badge** top-left (so you remember this is test mode)

### 2. Walk to a planter
You'll see a **3x3 grid of brown planters** with **green glowing borders** underneath (empty slots).

### 3. Press E on a planter
- A **seed picker dialog** should pop up
- Pick a seed (Sunbloom is fast, ~60 sec grow time)
- **Seedling sprouts** — a small stem + leaves appear

### 4. Watch it grow (~60 seconds)
- Stem gets taller
- Leaves become visible
- Flower bud forms at top
- **When complete:** Flower **glows neon**, planter's green border disappears

### 5. Walk over the RIPE plant (key change!)
- Just **walk on top of the planter** — don't click anything
- Plant instantly **disappears**
- A **floating popup** appears: `+1 🌻 Sunbloom` (or `+1 ✨ MUTATION_NAME` if mutation)
- Popup **floats up & fades out**

### 6. Walk to the SELL PAD (green glowing kiosk on the left)
- It has a **post, platform, neon sign**
- Stand on it
- You see: **"Walk here to sell"** prompt
- **Crops harvest automatically** (invisible stash converted to coins)
- **Cash increases** on HUD

### 7. Repeat: Buy more seeds → Plant → Grow → Harvest via walk-over → Sell

---

## ✅ What to Watch For (Good Signs)

- [ ] **Seedling appears** when you pick a seed (not instant, takes 1-2 sec)
- [ ] **Plant grows smoothly** over ~60 sec (visible progression, not jumpy)
- [ ] **Plant glows when ripe** (distinct visual: stem stops, flower glows, no green border)
- [ ] **Harvest popup shows** when you walk over ripe plant (`+1 emoji name`)
- [ ] **Plant disappears** after harvest (planter returns to empty + green border reappears)
- [ ] **Cash increases** when you walk on sell pad
- [ ] **No error spam** in Output panel
- [ ] **DEV MODE badge visible** (red, top-left)

---

## ⚠️ Bad Signs (Report These!)

- [ ] Plants still look like **yellow boxes** or **unfinished**
- [ ] Plants **don't grow** (stay same size)
- [ ] Plants **disappear without a popup** (looks like a bug)
- [ ] **Walking over ripe plant does nothing** (need to find alternative harvest method)
- [ ] **No visual difference** between growing and ripe
- [ ] **Sell pad is confusing** or hard to find
- [ ] **Output panel has errors** (red text)
- [ ] **Game crashes** during play

---

## 📸 How to Send Feedback

If something looks wrong:

1. **Take a screenshot** from Play mode (showing the issue)
2. **Save to:** `~/Dev/bloom-and-burgle/debug/` with name like `plants-disappear.png`
3. **Send a 1-2 sentence description** of what you saw

**Example:**
> "Screenshot in debug/ folder. Plants grow fine but the harvest popup never shows — I walk over them and nothing happens."

I'll analyze the image + description and fix it within 1-2 hours.

---

## 🎯 The Real Question

**Does this FEEL better than "yellow boxes disappearing mysteriously"?**

- Can you tell when a plant is ready? ✅ (glows + no green border)
- Do you know what to do to harvest? ✅ (walk on it)
- Do you get satisfying feedback? ✅ (popup confirms harvest)
- Does the game feel like an actual game yet? 🤔 (let me know!)

---

## 🛠 If You Break Something

If you want to reset:

**While in Studio:**
```bash
# Stop Play (press Stop button in Studio)
cd ~/Dev/bloom-and-burgle
bash scripts/build.sh      # rebuild
# Press Play again
```

Or if Studio is totally broken:
```bash
# Close & reopen BloomAndBurgle.rbxlx in Roblox Studio
```

---

## 💭 What's Next

Once this feels solid, next fixes will be:
1. **Inventory chip** (so you can see harvested crops before selling)
2. **Sound effects** (plant, harvest, sell sounds)
3. **More plant varieties** (visual diversity, not all purple)
4. **Stealing mechanics** (make them visible, not abstract)

But first — **test this cycle and tell me if the harvest feel is better**.

**Commit: 6ca873c** | Test now, send feedback!
