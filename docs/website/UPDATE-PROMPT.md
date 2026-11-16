# Prompt: update spai-vision.pages.dev to match the current app

Paste everything below the line into the session that edits the website.
Fill in the two `[YOU FILL IN]` items first.

---

Update my website, spai-vision.pages.dev, so it describes SPAI as it works today. The app has changed a lot since the site was written. Change the copy and add one new section; keep the design, the structure and every video exactly as they are.

## Ground rules

- **Keep the design system.** Ink-and-paper palette, Archivo / Instrument Sans / JetBrains Mono, the existing layout, nav, footer and page structure. No new fonts, colours or libraries.
- **Keep every video file and where it sits.** I don't have new footage yet. The clips show an earlier build of the interface, so:
  - don't write any caption or label that says a clip shows a feature it doesn't;
  - where a feature card sits on a clip and its text changes, the text describes the current app and the clip stays as it is;
  - add one quiet line under the "Spatial deployment" heading on the home page and under the footage on How it works: "Footage from an earlier build. The current interface is calmer: three panels by default, with everything else a tap away."
- **Keep the voice.** Plain, specific, honest: "Straight answers", "The models, honestly". Keep known limits next to every claim. Keep "SPAI is a training and workflow-guidance tool, not a medical device." everywhere it appears now.
- **Invent nothing.** No customers, testimonials, logos, prices, user counts or statistics beyond what's below. Keep the existing cited statistics and their sources.
- Leave the demo / quote form and the email address unchanged.

## Facts to use

### Instrument model (v5) — replaces "v4 · 92.1 mAP50" everywhere

- Names six instruments: Adson Dressing Forceps, Babcock Tissue Forceps, Halsted Mosquito Forceps, Mayo-Hegar Needle Holder, Operating Scissors, Scalpel Handle No. 3.
- Report it as "correctly named", not mAP. mAP measured whether an instrument was found; v4 found instruments but named every one "Adson Dressing Forceps".
  - Real tray photos the model never trained on (70 photos, 176 instruments): **89% correctly named** (v4: 18%).
  - Handheld-style test images (400 images; real instrument cutouts, synthetic backgrounds and hands): **72%** (v4: 5%).
  - Through the Vision Pro camera: **[YOU FILL IN — your measured headset result, or delete this line]**.
- Known limits: six instruments only; Halsted mosquito forceps is the hardest (it looks like the needle holder); handheld accuracy was measured on synthetic images, and real-world accuracy is what a pilot measures.
- Still YOLOv8n, exported to Core ML, running on the headset.

### Gloves + hands model

- Keep its 93.6 mAP50 score. The site calls it "v2" on most pages and "v3" on the Try page. The correct label is **[YOU FILL IN: v2 or v3]**; use it everywhere.

### For students (in the headset)

- **Sign in on a shared headset:** pick your name from the class roster (or Guest), choose **Assessed run** or **Practice**, and choose Trainee, Technician or Instructor. Practice runs are guided and checked but never sent to the instructor.
- **Pip, the guide:** a small glowing companion (blue when calm, green when you finish, red on an alert). It hops onto the panel it's talking about while that panel lights up. A 30-second tour the first time. On a contamination alert it jumps to the alert, then to the button that clears it. It names an instrument you hold up.
- **Focus layout:** the workspace opens with three panels (status bar, workflow, detection). Event log, history, Ask SPAI and test media open from one Panels menu. "Show Everything" opens them all. "Bring Panels to Me" re-centres the workspace at your eye height.
- **Voice on every step:** "next", "repeat", "why", "what is this".
- **Trainees see the reason behind each step**, not just the instruction.
- **Count-sheet check at Tray Assembly:** the tray's expected instruments are listed and ticked off as the camera recognises each one. A missing or extra instrument is flagged before the tray is closed.
- **Hold up an instrument** at any station and SPAI names it, says what it's for, and at Inspection lists what to check on it.
- **Never stuck:** if the camera can't confirm a step after 12 seconds, "Confirm by hand" appears. The override is recorded for the instructor.
- **Wrist menus:** turn the back of your wrist toward you like a watch. Left wrist: the stations. Right wrist: Ask SPAI, History, Event Log, Settings. (Reset is in the Panels menu now.)
- **Result at the end of every run:** a score out of 100, a verdict (Competent, Needs practice or Incomplete), what cost points, and what to work on. Any contamination means "Needs practice", however high the score.
- **Works offline:** guidance, on-headset checks and scoring don't need a connection. Runs are saved on the headset and sent when the server is reachable.

### For instructors (in a browser)

- **Instructor dashboard:** the class roster with each learner's latest result, best score, number of runs and a score trend; how many learners are competent; average score; contamination alerts; and "where the class slips", a per-station count of alerts, redos and send-backs that names the station to re-teach first.
- Per-learner history; a printable report for every run with a station-by-station breakdown, the timeline of what happened and coaching notes; CSV export of every run for a gradebook.
- **Your protocol, your words:** edit each station's steps, what the camera checks before a step can advance, the tray's count sheet and the scoring. Changes reach every headset the next time it opens, and Ask SPAI answers from the same wording.
- **Signed in with an instructor PIN.** Today one PIN sees the whole roster; separate instructor accounts aren't built yet.

### Privacy and data — for the FAQ's Privacy + data section

- Camera frames stay on the headset by default. If a school turns that off, frames are sent to its SPAI server for checking and discarded; frames are never stored either way.
- Stored: learner names and cohort labels an instructor enters; for each run, start and end time, the steps and alerts, instruments recognised and the score.
- Never collected: video, photos, audio, faces, patient information.
- Deleting a learner permanently erases them and all their runs. An instructor can export every run as CSV, or one learner's full record as JSON. An optional retention period deletes runs automatically after a set number of days.
- Every SPAI server has a plain-language privacy statement at `/privacy` that an IT office can read without signing in.
- **Ask SPAI uses an external AI service (Google Gemini).** When a student asks a question, the question, the current station's steps and a short text summary of what the camera sees (for example "gloves detected, holding Operating Scissors") are sent to it. No images and no names are sent.
- Headsets connect with a site key; the dashboard needs the instructor PIN.

## Page-by-page changes

**Home (`/`)**
- "v4 · instrument model / Primary detection" block: SPAI now names each instrument, not just counts them. Model "YOLOv8n → Core ML"; endpoint `/analyze`. Example readout: "Mayo-Hegar Needle Holder · 91%" in place of the generic "Instrument 0.77" labels.
- Model stats: replace "v4 — Instrument model 92.1 mAP50" with "v5 — Instrument model · 89% correctly named on held-out tray photos". Fix the glove model label.
- Feature cards (keep each one's clip):
  - "Welcome to SPAI": Pip gives a 30-second tour, hopping onto each panel.
  - "What SPAI is watching": keep.
  - "Wrist menus": new left/right wording above.
  - "Past sessions": every assessed run goes to the instructor dashboard, scored, with what to work on.
  - "Tray assembly": add the count-sheet check.
  - Add one card, without a clip if the layout allows (otherwise skip it), for voice commands.
- Add the footage note described in the ground rules.

**How it works**
- Under the hood: Vision Pro (detection on the headset, Core ML); FastAPI (runs, scoring, the instructor dashboard, the school's protocol); YOLOv8 (two models: gloves + hands, and six named instruments); FSM (one workflow per headset).
- "The models, honestly" table: replace the v4 row with v5, its numbers and limits above. Fix the glove model label.
- Five stations list: Tray assembly checks become "Tray loaded · count sheet matches".
- Add the footage note.

**For schools**
- Add a section **"What instructors see"** with the dashboard screenshots I'm providing (files below), showing the class view and a run report. Caption: "Instructor dashboard, shown with sample data."
- "For students": add Practice mode, voice commands, the reason behind each step, and the result at the end of every run.
- "For instructors": add the dashboard, per-station "where the class slips", CSV export, and editing the protocol in your own words.
- "A year with SPAI": in "Set up + tour", mention adding the class roster on the dashboard.

**For hospitals**
- Onboarding / Competency / Audit trail: competency is now a scored verdict per run with a printable report; the audit trail is the dashboard and its CSV export; "your department's steps" is the protocol editor.
- Keep "SPAI is a working prototype, and it's looking for its first pilot department."

**Plans**
- "Every plan includes": add the instructor dashboard and protocol editing alongside the two models and logs. Update the instrument model's line to v5.
- Don't add or change prices. If the Program and Classroom features no longer differ meaningfully, leave a note in a comment for me rather than rewriting the tiers.

**FAQ + privacy**
- "Can it tell a hemostat from a scalpel?": yes, for six instruments (list them), with the accuracy and limits above. Other instruments aren't recognised yet.
- "How accurate is it?": glove model as now; instrument model 89% correctly named on held-out tray photos, 72% on handheld-style test images, real-world accuracy measured in the pilot.
- "Does video leave the headset?": no, by default (see Privacy and data).
- Add "Does Ask SPAI send anything outside our network?" with the Gemini answer above.
- Add "Can we delete a student's data?" and "Can we use our own procedure?"
- "Is SPAI HIPAA compliant?": keep the current answer.

**About the maker**
- "What user testing taught me": keep the list and add these, which came from testers and are fixed in the current build:
  - "Too much on screen at once" → three panels by default.
  - "Wrist menus hard to read, and clipped into the arm" → larger labelled buttons, placed beside the arm.
  - "The guided tour pointed at the wrong places" → Pip lands on the real panel.
  - "Instrument names were wrong" → retrained model.
- Leave the sprint, ticket and commit counts as they are.

**Try it live**
- Fix the glove model label to match the rest of the site.

## Screenshots to use

Download from the SPAI GitHub repo, branch `claude/serene-volta-76ikau`, folder `docs/website/`:

- `dashboard-class.png`: class view (sample data)
- `dashboard-run-report.png`: one run's report
- `dashboard-learner.png`: one learner's history
- `dashboard-protocol-editor.png`: protocol editor

They're 2× captures of a 1280px-wide browser. Every name in them is invented sample data, which the "Sample data" banner in the shots states. Keep the "shown with sample data" caption wherever they appear.

## When you're done

List every page you changed, and flag anything you couldn't change without new footage or my input.
