# Demo playbook: showing SPAI to a school

A 20-minute demo for a program director and instructors, plus what to set
up beforehand and what to do when something goes wrong. Nothing here
depends on the headset camera entitlement or on perfect Wi-Fi.

## The day before

1. **Server up.** Deploy with `render.yaml` (Render → New → Blueprint), or
   any host with a persistent disk and HTTPS. Set `GEMINI_API_KEY`.
2. **Server check.** On the server: `python -m app.admin doctor --ask`. Fix
   every FAIL. WARNs are fine for a demo.
3. **Demo school.** `python -m app.seed_demo`. Write down what it prints:
   the dashboard sign-in, the pairing code, and the sample PINs. Use
   **Avery Chen** for the demo.
4. **Pair the headset.** Home screen → Connect to your school → the address
   and code from step 3 (or a fresh code from Headsets on the dashboard).
5. **Count sheet to match the demo tray.** Dashboard → Protocol → Count
   sheet: set Halsted Mosquito Forceps, Operating Scissors and Babcock
   Tissue Forceps to 1 and the rest to 0. Save. (Or do this live; it's a
   good moment.)
6. **Test media on the headset.** AirDrop `demo/test-media/*.jpg` to the
   Vision Pro.
7. **System check.** Headset → Settings → Run system check. Everything
   green except, possibly, the camera feed.
8. **Speech on.** Settings → Speak step instructions, on. Accept the
   microphone prompt the first time.
9. **Rehearse once, start to finish.** Then **Next Student**, so the demo
   starts at the sign-in screen.

## Run of show (20 minutes)

| Min | Where | What to do | What to say |
| --- | --- | --- | --- |
| 0–2 | Laptop: website | Home page, scroll to the five stations | "Sterile processing training today is a binder and a supervisor's memory. SPAI puts a patient guide and a checker at every station." |
| 2–4 | Headset | Tap **Avery Chen**, enter the PIN | "Every student has a PIN. Shared headsets, but every run belongs to the right person." |
| 4–6 | Headset | Let **Pip** run the tour | "Three panels, not ten. Pip shows you where to look." |
| 6–9 | Headset | **Start Step** at Decontamination. Load `gloves-on.jpg`: step passes. Load `bare-hand.jpg`: alert, Pip jumps, **Acknowledge & Resume** | "A bare hand at the wrong moment stops the workflow, and it's logged." |
| 9–11 | Headset | Hold up a real instrument, or load `tray-three-instruments.jpg`. Say **"what is this"** | "It names six instruments today, and at Inspection it tells you what to check." |
| 11–13 | Headset | Skip ahead with the station list on the left wrist to **Tray Assembly**. Load the tray image; the count sheet ticks off | "It checks the tray against the count sheet before it's closed." |
| 13–14 | Headset | Finish the run; show the result and coaching; press **Next Student** | "Every student gets their result and what to work on, right away." Because you skipped stations, it scores **Incomplete**. That's correct; say so, and show a completed sample run on the dashboard next. |
| 14–19 | Laptop: dashboard | Refresh **Class**: the run is there. Open it. Show **Where the class slips**, **Export CSV**, **Protocol**, **Headsets**, **Privacy** | "Instructors see who's ready and who needs a hand, and they can teach your procedure in your words." |
| 19–20 | Laptop | Plans page, then **Book a demo** | "A pilot is one year with your headsets. We set it up with you." |

## When something goes wrong

| Problem | Do this |
| --- | --- |
| No Wi-Fi or the school blocks the server | Use your phone's hotspot for the headset. Students can still sign in offline; the run sends when it reconnects. |
| No camera feed | Use the test media. That's what it's for. |
| A step won't confirm | Wait 12 seconds; **Confirm by hand** appears. Say: "If the camera can't see it, the student isn't stuck, and the instructor sees it was confirmed by hand." |
| Ask SPAI doesn't answer | Skip it. Everything else works without it. |
| The run isn't on the dashboard | Refresh. If the result screen says "Saved on this headset", the server isn't reachable; it will send later. For the demo, `python -m app.seed_demo --live-run "Avery Chen"` adds a sample run now. |
| The app crashes | Go straight to the dashboard. It has the sample class and tells the instructor story on its own. |
| PIN locked from wrong tries | Dashboard → the learner → **New PIN**. |

## Questions you'll get, and honest answers

- **"How accurate is it?"** Instrument naming: 89% on held-out tray photos,
  72% on handheld-style images. Glove check: 94.8 mAP50 on its validation
  set (v3). Real-world accuracy in your lab is what the pilot measures.
- **"What about student privacy?"** Video stays on the headset. We store
  names, runs and scores, separate per school, deletable any time. Ask
  SPAI sends questions (no images, no names) to Google Gemini.
- **"Does it replace the instructor?"** No. It's a training and guidance
  tool, not a medical device and not a sign-off.
- **"What do we need?"** Apple Vision Pro headsets and Wi-Fi. We host the
  server and set it up with you.
- **"Can it follow our procedure?"** Yes: your steps, your count sheets,
  your scoring, edited on the dashboard.

## Before a real class (not just a demo)

Remove the sample data (dashboard banner), create the school with
`python -m app.admin create-org`, and have the program director invite their
instructors. See `how-spai-connects.md`.
