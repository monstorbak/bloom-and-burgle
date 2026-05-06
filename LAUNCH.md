# 🌅 Morning Launch Runbook

> **Hey Retardio, GM 🤘** Here's the EXACT click-by-click to ship Bloom & Burgle.
> Total time: ~25 minutes if nothing breaks. Most of it is browser clicks I can't do for you.

---

## ⚡ TL;DR (5-minute version)

1. Create new Roblox experience → grab Universe ID + Place ID
2. Tell me the IDs (paste in WhatsApp, I'll publish v0.1)
3. Upload thumbnail + icon I generated (`marketing/thumbnails/launch-v1.jpg`, `marketing/icons/icon-v1.jpg`)
4. Create game passes from `marketing/copy/gamepasses.md` (copy-paste descriptions)
5. Post Video 1 from `marketing/copy/tiktok-launch-scripts.md` to TikTok
6. We wait for users.

---

## 📝 Step-by-step

### Step 1 — Create the Roblox experience (5 min)

1. Open https://create.roblox.com/dashboard/creations
2. Click **"+ Create Experience"** (top right)
3. Pick: **Baseplate** template (we'll overwrite it anyway)
4. Configure:
   - **Name:** `Bloom & Burgle 🌸💰 [BETA]`
   - **Genre:** Simulator
   - **Server size:** 16 players
   - **Privacy:** Public (or Private until we confirm v0.1 works, then flip Public)
5. Save

### Step 2 — Get the IDs (1 min)

In the new experience's Creator Dashboard:
- The URL will look like: `https://create.roblox.com/dashboard/creations/experiences/<UNIVERSE_ID>/...`
- Click **Places** tab → click the start place → its URL will end in `/places/<PLACE_ID>/...`
- **Copy both IDs and paste them to me on WhatsApp.**

I'll auto-publish v0.1 the second I get them. Should be live within 2 minutes.

### Step 3 — Upload assets (3 min)

In the same dashboard:
- **Configure → Basic Info → Game Icon** → upload `marketing/icons/icon-v1.jpg` (it's at `/home/monstorbak/Dev/bloom-and-burgle/marketing/icons/icon-v1.jpg` — Mac via SSH or Drive sync)
- **Configure → Thumbnails** → upload `marketing/thumbnails/launch-v1.jpg`
- Save

### Step 4 — Description + Tags (2 min)

- **Configure → Basic Info → Description** → paste the block from `marketing/copy/roblox-listing.md` (under "Description (full)")
- **Tags:** simulator, tycoon, farming, competitive, social

### Step 5 — Game passes (10 min)

Open `marketing/copy/gamepasses.md`. Create 6 game passes one by one:
- **Monetization → Passes → Create Pass**
- For each: name + price + description (copy-paste from the file)
- Upload a simple icon (any of the gen'd images works for now — I'll generate proper icons later if revenue comes in)

| # | Name | Price |
|---|---|---|
| 1 | 2x Bloom Bucks Forever | 199 |
| 2 | 4x Bloom Bucks Forever | 599 |
| 3 | Auto-Harvest | 399 |
| 4 | Anti-Theft Shield | 299 |
| 5 | VIP Plot | 499 |
| 6 | Mythic Hunter | 999 |

⚠️ Note: 2-7 day Roblox approval delay on game passes typically. Set them up FIRST so they're ready when v0.2 lands.

### Step 6 — Dev products (5 min)

Same flow, **Monetization → Developer Products**. Use `marketing/copy/dev-products.md` for descriptions.

⚠️ Dev products **don't auto-grant rewards** — I haven't built `DevProductHandler.server.luau` yet. It's filed as bead `bab-???`. v0.2 ships this. For launch night, only the gamepasses will work; that's fine, gamepasses are the higher-conversion tier anyway.

### Step 7 — Flip Privacy to Public (1 min)

When you're ready: **Configure → Visibility → Public**. The internet now has access.

### Step 8 — Post the launch TikTok (5 min)

Pick **Video 1** from `marketing/copy/tiktok-launch-scripts.md` (the AI-built-it angle). Record on your phone, post to TikTok + Reels + X.

**Add to bio:** `https://www.roblox.com/games/<PLACE_ID>`

---

## 🐛 Likely first-night bugs (and fixes)

**Bug 1: Players spawn but no claim pads visible**
→ `gt sling <new bead> bloom_and_burgle` to a polecat with: "verify Workspace.TownSquare loaded; check ServerScriptService.PlotManager spawned 16 ClaimPads."

**Bug 2: Plants don't grow**
→ `Heartbeat:Connect` running but `CollectionService:GetTagged("Planter")` returning empty. Polecat fix: ensure Planter tags are set in PlotManager AFTER `:AddTag`, not before.

**Bug 3: Sell pad doesn't pay out**
→ The `for _, sellPad in CollectionService:GetTagged("SellPad")` loop runs ONCE at server start, before any players have claimed plots. Fix: switch to `CollectionService:GetInstanceAddedSignal("SellPad"):Connect(...)`. Polecat ticket pre-filed.

**Bug 4: Welcome popup never shows**
→ Check `WelcomeUX.client.luau` is in StarterPlayerScripts (not StarterCharacterScripts). Should be fine but worth checking.

If anything else breaks, screenshot the in-game `/console` and send it. Layer 2 will sling fixes within minutes.

---

## 🎯 Day 1 metrics to track

(All visible in Creator Dashboard → Analytics)

- **CCU peak** (concurrent users) — goal: any positive number on day 1 lol
- **Visits** — aiming for 500+ from a single TikTok
- **Avg session length** — goal: >5 min (meaning the game is actually engaging)
- **Bounce rate** (left in <30 sec) — keep under 60%
- **Earnings (Robux)** — anything > 0 = first dollar earned 🤘

---

## 🚨 If a TikTok hits big

Like, >100k views big. Action items:
1. Pin the comment "play it FREE here → roblox.com/games/<PLACE_ID>"
2. DM me on WhatsApp — I can rapid-deploy fixes mid-virality if servers struggle
3. Don't switch privacy or break the link mid-spike

---

## 💪 What I shipped overnight while you slept

See `OVERNIGHT_REPORT.md` in this directory.

🤘 Let's make some moolah, partner.
— G-Tard
