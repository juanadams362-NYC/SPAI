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

## 1. Server (once, by SPAI)

Deploy `backend/` with persistent disk and HTTPS, then create the school:
`python -m app.admin create-org --name "<school>" --admin-email <director> --url <server>`.
Send the printed link to the program director. Details:
[how-spai-connects.md](how-spai-connects.md).

## 2. The school's admin (once)

1. Open the invite link and set a password.
2. **Team**: invite each instructor.
3. **Class**: add the students and print their PIN cards.
4. **Headsets**: connect each Vision Pro with a pairing code.
5. Optional: **Protocol**, to use your own wording, count sheet and scoring.

## 3. A session

1. The student taps their name on the headset and enters their PIN.
2. Pip gives a 30-second tour the first time.
3. At each station: **Start Step**, then follow the spoken and written steps.
   "Next", "repeat", "why" and "what is this" work by voice.
4. At the end the student sees their result, then presses **Next Student**.
   The run appears on the dashboard.

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
- **No single sign-on or password-reset email yet.** An admin re-invites
  anyone who forgets their password.
- SPAI is a training and workflow-guidance tool, not a medical device.
