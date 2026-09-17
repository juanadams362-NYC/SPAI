# SPAI — Week 2 Test Plan & Tickets

**Branch:** `user-testing-fixes` · 8 commits · 67 tests passing · builds clean for simulator + device
**Source:** Gaby session 09/03 bug list, all items fixed on branch

Everything from the 09/03 session is fixed. What follows is what still needs *proving*, split by
where it can actually be proven — roughly half this work is spatial, and a simulator has no hands,
no head position, and no room.

---

# 1. Tickets for next week

Ordered by what blocks the most. WK2-02, 03 and 05 depend on lab data coming back, so run the lab
session early in the week.

---

### WK2-01 — Dynamic Type support across all panels
**Priority: High**

Every font size in the app is a hardcoded `.system(size:)` value, so text does not scale for anyone
who needs it larger. This is the one accessibility gap the last pass did not close, and it's a real
one — the wrist menus now go down to 8pt labels. Panels have fixed pixel widths too, so scaled text
will clip before it reflows.

**Done when**
- Panel text scales with the system setting from xSmall through AX3.
- Fixed `.frame(width:)` values become max-widths or intrinsic sizing; no clipped text at AX3.
- Wrist menus either scale or are explicitly capped, with the reason recorded.

---

### WK2-02 — Tune the panel arc from measured device data
**Priority: High · Needs lab**

The status bar reported at the bottom of the field of view could not be reproduced without a
headset. The arc is now anchored to a measured eye height rather than an assumed floor origin,
which *should* fix it — but that's a hypothesis until someone wears it. All heights live in one
table, `ImmersiveView.layout`, as offsets from the eye line.

**Done when**
- Status bar sits above the eye line for both a standing and a seated tester.
- `[head-anchor] calibrated eye height` appears in the log with a plausible value.
- Any panel reported as too close or too far has its slot adjusted and re-checked.

---

### WK2-03 — Tune wrist gesture thresholds
**Priority: High · Needs lab**

The summoning gestures (right wrist turned toward you, left forearm held level) are gated by numbers
picked on reasoning, not observation: enter 0.55, exit 0.30, level tolerance 0.6. All three are
constants at the top of `WristGesture.swift`. Expect them to be wrong in at least one direction on
a real arm.

**Done when**
- Menu appears within ~1s of the deliberate gesture, for two different testers.
- No false summons during a full workflow run with normal hand movement.
- No flicker while holding an arm still near the threshold.

---

### WK2-04 — Re-master the contamination alert audio
**Priority: Medium**

`error_fx.mp3` peaks at −4.6 dBFS and averages −19.7 dBFS RMS, which is quiet for an alert. Spatial
gain is at +10 dB and can't go much higher without clipping the transient. The real fix is a louder,
more compressed source rather than more gain on a thin one.

**Done when**
- Replacement asset sits near −12 dBFS RMS with peaks under −1 dBFS.
- Gain constant in `SoundManager` re-tuned down to suit it.
- A tester with the headset on describes it unprompted as impossible to miss.

---

### WK2-05 — Confirm or close the 11:44 crash
**Priority: Medium · Needs lab**

Two plausible causes were fixed blind: the Settings window spam (a `WindowGroup` minting a window
per press) and a microphone crash where the audio session was left recording-incapable before
installing a tap. Neither is confirmed as the actual cause, because there were no logs. **This
ticket closes on evidence, not on a fix.**

**Done when**
- A full lab session runs with console capture on from launch.
- Crash reports pulled from the device even if nothing visibly crashed.
- Either a crash is reproduced and diagnosed, or the session is signed off clean.

---

### WK2-06 — Make "no detection input" a first-class state
**Priority: Medium**

The guided panel now says "SPAI can't see your work yet" and offers a fix, but the detection panel
and status bar still render as though the system is simply idle. Three panels describing the same
condition three different ways is how the original confusion started.

**Done when**
- A single derived state on `DetectionService` answers "is anything feeding me".
- Detection panel, status bar and guided panel all read from it.
- Starting a step with no input source is visible without opening any other panel.

---

### WK2-07 — Reconcile the welcome pages with the in-app tour
**Priority: Low**

`OnboardingView` (the pre-launch page carousel) still exists alongside the new guided tour, and the
two overlap in what they explain. The setting is still labelled "always show welcome screens" while
the tour has its own replay button. Decide whether the carousel earns its place now that the tour
teaches the workspace directly.

**Done when**
- Either the carousel is cut to a single welcome screen, or there's a written reason it stays.
- One obvious route back into the tour, not two competing ones.

---

### WK2-08 — Session history: prove persistence, then add export
**Priority: Low**

History saving has never actually been observed working, because the test session crashed before a
workflow completed. The code writes to `UserDefaults` on completion and looks correct — but "looks
correct" is what the last four bugs also looked like. Prove it, then add the export the compliance
story needs.

**Done when**
- A completed 5-step session appears in History and survives a full app relaunch.
- Export produces a file with timestamps, events, role and contamination count.

---
---

# 2. What YOU can test in the simulator

All real verification — logic, layout, wiring and copy, none of which needs hardware.
**~30–40 minutes end to end.**

**Before you start:** run the backend locally or detection fails and several checks below become
inconclusive.

```bash
xcodebuild -project SPAI.xcodeproj -scheme SPAI \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
```

```bash
xcrun simctl boot "Apple Vision Pro"; xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/SPAI-ddflkyhdlspbcueoceppvwfumfxz/Build/Products/Debug-xrsimulator/SPAI.app; xcrun simctl launch booted juanbuildstech.SPAI
```

In the simulator, move your viewpoint with **W A S D** and drag with the mouse holding **Option**.
You need that for the billboard check.

## The tour

- [ ] Reset the tour so it offers itself — Settings → **Replay guided tour**, or delete + reinstall.
      *Offer card should appear ~1s after the immersive space opens.*
- [ ] Tap **No thanks**. It should disappear and not come back this session.
- [ ] Replay from Settings, tap **Show me**, walk the whole thing with Next.
      *Card should glide between panels, not teleport. Progress dots track along the bottom.*
- [ ] On **"You have a role"**, tap a role instead of Next.
      *Prompt flips to a green "Nice." then auto-advances after ~1s. This is the learn-by-doing
      path — most likely thing to be subtly broken.*
- [ ] On **"Start working"**, tap Start Step rather than Next. Same auto-advance.
- [ ] Turn **Wrist menus** OFF in Settings, then replay the tour.
      *The wrist-menu step should be gone entirely, and Chat/History/Settings steps should say
      "in the status bar" / "in the quick actions" instead of "on your wrist".*
- [ ] Skip the tour halfway. It should close and stay closed.

## The bugs from last session

- [ ] **Tap History.** Panel should fly in from the wrist menu and land on your left.
      *This was the "does nothing" bug. The button always worked — the panel opened behind your shoulder.*
- [ ] A confirmation reading **"History opened"** appears under the wrist buttons for ~2s.
- [ ] **Press Settings five times fast.** Exactly one window, no duplicates stacking.
      *Presses inside 500ms are swallowed by the debounce. Press once, wait a beat, press again — it should close.*
- [ ] Close Settings with its own window control, then press Settings again. It should **open**,
      not try to close a window that's already gone.
- [ ] **Change role with one pinch.** All four roles are inline pills in the status bar now.
- [ ] Switch to **Observer**. Start Step unavailable, workflow panel says why.
- [ ] Workflow header reads **"STEP 1 OF 5"** on the first step.
      *It used to read 0/5 — a plain off-by-one nobody had caught.*
- [ ] **Move your viewpoint** (W/A/S/D) and look back at the panels. They should rotate to keep facing you.
      *Then turn "Panels look at you" off and confirm they stop. This was the blendFactor bug.*

## The workflow gap

- [ ] Start a step **without** uploading anything or connecting a camera.
      *Amber callout appears: "SPAI can't see your work yet", with a button straight to upload.*
- [ ] Status line reads **"Waiting for you to show SPAI something"**, not "Waiting for detection…".
- [ ] Tap the callout button. Upload window opens; callout disappears once a detection result returns.
- [ ] Upload a loaded-tray image, confirm results land in the detection panel.
- [ ] **Complete all five steps.** Session report appears → shows in History → survives a relaunch.
      *This is WK2-08 and has never once been observed working. If it fails, promote that ticket.*

## Accessibility

- [ ] Turn on **Reduce Motion** (sim Settings → Accessibility → Motion).
      *Panels land instantly instead of flying, tour card jumps between anchors, buttons stop
      scaling on hover — but the written confirmations must STILL appear, or the feedback is lost entirely.*
- [ ] Turn on **VoiceOver** and sweep the panels.
      *Detection reads its risk as a percentage in words. Workflow announces step + next action.
      Toggles say On or Off.*
- [ ] Open Settings, scroll to the bottom. *It scrolls now — explanations + replay button pushed it
      past the window height.*
- [ ] Read the confidence-threshold explanation. Does it actually answer "what is confidence"?

## Scene lifecycle

- [ ] Open and close the immersive space **five times**. No crash, button never sticks disabled.
- [ ] With the space open, **quit the app**. All immersive content disappears with it.
      *This was the "UI stays up after the app closes" bug.*
- [ ] Relaunch. Settings and Upload should **not** reopen on their own.

---
---

# 3. Lab session protocol — for your colleague

Written to be followed without you in the room.

> Everything in this section can **only** be answered on a real headset. That's the point of running it.

## Part A — Pre-flight, before the participant arrives

Budget 20 minutes. If any of these fail, note it and continue with what still works rather than
cancelling — a partial session is still data.

### 1. Install the build on the Vision Pro
Branch `user-testing-fixes`. Build to the **device**, not the simulator. If signing fails, stop and
message Juan — the bundle identifier was recently changed back to `juanbuildstech.SPAI` and the
provisioning may need re-selecting.

### 2. Start console capture BEFORE first launch
**This is the single most valuable thing you can do.** Last session may have crashed and there were
no logs, so the cause is still unknown.

- Connect the headset, open **Console.app** on the Mac.
- Select the Vision Pro in the left sidebar, filter the search box to `SPAI`.
- Click **Start** and leave it running for the whole session.
- At the end, select all and **Save a copy** — even if nothing crashed.

**Also grab regardless:** Xcode → Window → Devices and Simulators → select the device →
**View Device Logs**. Export anything dated today. Crash reports land here even when the app
appeared fine.

### 3. Grant permissions and note what's asked for
On first launch the app should ask for hand tracking, world sensing, and microphone. Accept all.

**WRITE DOWN:** which permission prompts appeared, in what order, and whether any appeared *after*
the immersive space opened rather than before. A late prompt is a bug.

### 4. Confirm the eye-height calibration ran
In the console log, search for `[head-anchor]`. You should see a line reading
`calibrated eye height` followed by a number.

**WRITE DOWN:**
- The number it reports, and the tester's actual height.
- If it instead says `no device anchor after 1.5s`, note that — the whole panel arc is falling back
  to a 1.5 m assumption and every placement answer below is measuring the fallback, not the fix.

### 5. Test the Digital Crown across the full immersion range
**This is new and cannot be tested anywhere but on device — the simulator has no crown.**

The app used to allow only progressive immersion, which clamped the crown to the system's
default floor: it could never dial back to full passthrough, only about halfway, then snapped
fully in. It now allows mixed, progressive and full, so the crown should travel the whole way.

- The workspace should **open at full passthrough** — you see the whole room, no dimming.
- Turn the crown **in**: passthrough should fade progressively, all the way to fully immersed.
- Turn the crown **back out**: it should return to *completely* unobstructed passthrough — not
  stop partway.

**WRITE DOWN:**
- Does it reach full passthrough at the bottom of the crown's travel? (This is the whole point.)
- Does it reach full immersion at the top?
- Is the transition smooth, or does it jump/snap at any point?
- Are the panels still readable at every immersion level?

> Note: full immersion hides the room entirely. In a lab where someone is handling sharp
> instruments that is a safety consideration — flag it if it feels wrong to allow.

### 6. Check the panel arc yourself — standing AND seated
Open the immersive space and, without moving, answer:

- Is the **status bar above your eye line**, centred? *(Last session it was reported at the bottom —
  this is the fix that most needs confirming.)*
- Are detection and event log at roughly eye level, left and right?
- Is the workflow panel below centre?
- Does anything feel too close to your face?

Then **sit down**, close and reopen the immersive space, and answer all four again.

**WRITE DOWN:** any panel in the wrong place, standing vs seated, and roughly how far off —
"about a forearm too low" is a perfectly usable measurement.

### 7. Test the contamination alert volume
Trigger an alert — start a step whose instruction requires gloves, then show a bare hand to the camera.

**WRITE DOWN:**
- Was it startling, noticeable, or easy to miss?
- Did it sound like it came from the direction of the detection panel?
- Any distortion or crackle? *(Gain is at +10 dB and the source is close to clipping, so this is a
  real risk.)*

### 8. Test the wrist gestures deliberately
These are brand new and the thresholds were chosen on reasoning, not observation. Try each one
**ten times** and count.

- **Right wrist:** raise and turn it toward your face, as if checking a watch. Quick-action menu
  should appear beside your wrist, roughly a hand's width out.
- **Left forearm:** hold it level in front of you, turned up, as if a book were lying along it.
  Station list should appear above the arm.
- Lower each arm — the panel should **fade**, not freeze in place or snap away.
- Now work normally for two minutes — move your hands about, pick things up. Count how many times a
  menu appears when you did **not** ask for it.

**WRITE DOWN:**
- Out of 10 deliberate attempts, how many summoned the menu — for each wrist.
- How many false summons in two minutes of normal movement.
- Whether either panel flickers while you hold your arm still.
- Whether the panels are still too big or in the way. Both shrank ~25%, and the right one became a
  square tile instead of a wide strip.

---

## Part B — The participant session

> **DO NOT GUIDE THEM.** The value is entirely in where they get stuck. If they ask what to do, say
> "whatever you think you should" and write down that they asked. Only step in if they're stuck for
> more than ~2 minutes, and note when you did.

Give them these five tasks, **one at a time, in this order**. Say nothing else.

1. "Start a detection session."
2. "Trigger a compliance alert and see what happens."
3. "Find your past sessions and export them."
4. "Ask SPAI a question."
5. "Change the backend URL in settings."

### 1. Offer the tour, then let it run
The tour offers itself ~1s after the immersive space opens. Let them decide whether to take it —
do not encourage either way.

**WRITE DOWN:**
- Did they accept or decline?
- If they took it: which step did they abandon on, if any? Did they use Next, or perform the real actions?
- Did they still need to ask what to do afterwards? *That's the whole question the tour exists to answer.*

### 2. Time each task and note the wrong turns
Where they looked first matters more than whether they succeeded. "Looked for settings on the left
panel" is worth more than "completed in 40 seconds".

**WRITE DOWN, per task:**
- Time to complete, or that they gave up.
- Everywhere they looked before finding it.
- Anything they said out loud. **Quote it exactly** — last session's notes were useful precisely
  because they were verbatim.

### 3. Watch specifically for these five things
Each is a fix from last week that needs a fresh pair of eyes.

- When they tap **History**, do they notice the panel open? Do their eyes follow it?
- Do they read the **"History opened"** confirmation under the wrist buttons?
- When they start a step, do they work out on their own that they need to **show SPAI an image**?
  *This was the biggest gap last time.*
- Do they discover the **roles** without being told they exist?
- Do they ever open **Settings twice** by accident?

### 4. Ask three questions at the end
After they take the headset off, before discussing anything else:

- "At any point, did you not know what you were supposed to be doing?"
- "Was anything physically in your way?"
- "Did anything happen that you didn't expect, or that you couldn't undo?"

### 5. Close out
- Save the console log, whether or not anything crashed.
- Export device logs from Xcode.
- Note the **exact wall-clock time** of anything that looked like a freeze or crash — last session's
  "possible crash at 11:44" was only traceable because someone wrote the time down.
- Check whether the completed session actually saved into History.

---

## The gap from last session

**The detection panel glove check was left blank last time** and still needs capturing. Explicitly
test it: show gloved hands to the camera and confirm the detection panel updates, then show bare
hands and confirm it changes. Write down what the panel said in both cases.
