# Running a SPAI pilot

What a school or department needs to stand up, and what to check before the
first student puts on a headset.

## What you are setting up

| Piece | Where it runs | Who uses it |
| --- | --- | --- |
| SPAI app | Each Apple Vision Pro | Students and technicians |
| SPAI server (`backend/`) | One machine the headsets can reach | The headsets, automatically |
| Instructor dashboard | A browser, at `<server>/instructor` | Instructors |

The app works without the server: guidance, on-headset checks and scoring
all run locally. The server is what turns individual runs into a class
record.

## 1. Server

1. Deploy `backend/` somewhere with **persistent disk** and **HTTPS**.
2. Set `SPAI_API_KEY`, `SPAI_INSTRUCTOR_PIN` and `SPAI_SECRET`
   (see `backend/README.md`). The dashboard shows a warning until the first
   two are set.
3. Open `<server>/instructor`, sign in, and add the class under **Add
   learners**.
4. Optional: open **Protocol** and replace the standard wording with your
   own procedure, set the tray's count sheet, and adjust scoring.

## 2. Each headset

1. Install SPAI and open **Settings** from the home screen.
2. Enter the **server address** and the **site key**, then **Test
   connection**.
3. Leave **Keep camera frames on this headset** on unless you have agreed
   otherwise with your privacy office.

## 3. A session

1. The student picks their name, chooses **Assessed run** or **Practice**,
   and enters the workspace.
2. Pip gives a 30-second tour the first time.
3. At each station the student presses **Start Step** and follows the
   spoken and written steps. "Next", "repeat", "why" and "what is this"
   work by voice.
4. When the run ends the student sees their result and what to work on.
   Assessed runs appear on the dashboard; if the network was down they are
   held on the headset and sent later.

## What is and isn't recorded

Recorded: who ran the session, when, the steps and alerts, instruments
recognised, and the score. Never recorded: video, photos, audio, faces.
The full statement is at `<server>/privacy`. Deleting a learner on the
dashboard erases all of their runs.

## Known limits to tell a pilot partner

- **The headset camera needs Apple's enterprise main-camera entitlement.**
  Without it, checks run from an iPhone over Continuity Camera or from
  uploaded test media.
- **Instrument naming was validated on tray photos and synthetic handheld
  images**, not yet on real handheld footage. Measuring that is part of
  what a pilot is for. See `model-training/v5_instruments.md`.
- **Six instruments** are recognised today.
- **One server, one institution.** There are no separate accounts per
  instructor yet; everyone with the PIN sees the whole roster.
- SPAI is a training and workflow-guidance tool, not a medical device.
