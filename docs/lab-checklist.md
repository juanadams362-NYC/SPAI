# Lab checklist: first run on the Vision Pro

Work top to bottom. Each step depends on the ones above it. Write down
anything that fails, with what you saw, and bring the list back.

## 1. Build

- [ ] Delete your local `SPAI/instruments_best.mlpackage` folder, then pull the branch `claude/serene-volta-76ikau`.
- [ ] Open in Xcode and build for the headset. **Copy every error message exactly**; this code has never been compiled.
- [ ] If you have the enterprise main-camera entitlement and license, add them to the target now (they aren't in the repo).

## 2. Server

- [ ] `cd backend && pip install -r requirements.txt`
- [ ] `python -m app.seed_demo`; note the sign-in, pairing code and PINs.
- [ ] `python -m app.admin doctor`
- [ ] `uvicorn app.main:app --host 0.0.0.0 --port 8000`, on a laptop on the same Wi-Fi as the headset. The server address is `http://<laptop's IP>:8000`.
- [ ] Open `http://localhost:8000/instructor` and sign in.

## 3. Home screen

- [ ] Shows "Not connected to a school".
- [ ] Pair with the address and code. The roster appears.
- [ ] Wrong PIN: says how many tries are left. Right PIN: opens the workspace.
- [ ] Guest practice opens the workspace.

## 4. Workspace

- [ ] Panels appear in front of you at eye height. Try sitting and standing; use **Panels → Bring Panels to Me**.
- [ ] Only three panels at first. Panels menu opens the others.
- [ ] Pip's tour: Pip lands on each panel it mentions. Note any stop where it's in the wrong place.
- [ ] Settings → **Run system check**: note anything not green.

## 5. Wrist menus

- [ ] Turn the back of the left wrist toward you: stations appear above the wrist. Same for the right: four labelled buttons.
- [ ] Turn away: they disappear. Swing the arm fast: they hide, and never go through the arm.
- [ ] Note any angle where a menu clips into the arm or is hard to read.

## 6. A full run

- [ ] Start Step at Decontamination. Voice: "repeat", "why", "next".
- [ ] Test media `gloves-on.jpg` passes the glove step; `bare-hand.jpg` halts it, Pip jumps to Detection, the alert sounds.
- [ ] Hold up each of the six instruments, five times each, in a gloved hand. **Count how many times it says the right name.** That's the number for the website.
- [ ] Tray Assembly: the count sheet ticks off with `tray-three-instruments.jpg`.
- [ ] Wait out a camera step: **Confirm by hand** appears after about 12 seconds.
- [ ] Finish: the result shows a score and coaching. **Next Student** goes back to sign-in.
- [ ] The run is on the dashboard after a refresh.

## 7. Offline

- [ ] Turn off the laptop's server. Sign in (the PIN is accepted offline), do a short run, finish.
- [ ] The result says "Saved on this headset".
- [ ] Turn the server back on and open the home screen: the run arrives on the dashboard.

## 8. Disconnect

- [ ] Dashboard → Headsets → Disconnect. The headset's home screen asks to pair again.
