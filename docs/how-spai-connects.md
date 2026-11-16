# How SPAI connects: website, dashboard, headsets, students

## The four pieces

| Piece | Where it lives | Who uses it | What it's for |
| --- | --- | --- | --- |
| **Website** | spai-vision.pages.dev | Anyone | Marketing: explains SPAI, books demos. Holds no student data. Its "Instructor sign-in" link opens the dashboard. |
| **SPAI server** | One server you run (e.g. `app.<your-domain>`) | Headsets and instructors | Holds every school's roster, runs, protocol and accounts, kept separate per school. |
| **Instructor dashboard** | `https://<server>/instructor` | Instructors, admins | Roster, PINs, results, headsets, team, protocol. |
| **SPAI app** | Each Vision Pro | Students | Guidance, checks, scoring; sends assessed runs to the server. |

The website and the server are separate on purpose. The website is static
and public; the server holds student records and is locked down. The only
connection between them is a link.

## Onboarding a school (once)

1. **You** (the operator) run, on the server:
   `python -m app.admin create-org --name "Riverside College" --admin-email director@riverside.edu --url https://app.<your-domain>`
   It prints a one-time invite link. Email it to the program director.
2. **The director** opens the link, sets their own password, and is the
   school's **admin**. You never see their password.
3. The admin invites instructors from **Team** (each gets their own link and
   their own password), adds the class on **Class** and prints the PIN cards,
   and connects each headset from **Headsets**.

## Connecting a headset (once per headset)

1. Admin: **Headsets → Show a pairing code**. The dashboard shows the server
   address and an 8-character code, valid 10 minutes, usable once.
2. On the headset: the home screen says "Connect to your school". Enter the
   address, the code and a name like "Lab headset 2".
3. The server gives that headset its own secret token. The headset keeps it
   in the Keychain; the server keeps only a scrambled copy.
4. From then on the headset shows that school's roster and protocol, and
   sends runs to that school only. **Disconnect** on the dashboard stops it
   instantly.

## How SPAI knows which student is which

1. Each student is added by an instructor and gets a **4-digit PIN**, shown
   once on a printable card. Only a scrambled copy is stored.
2. On the headset, the student taps their name and enters their PIN on a
   number pad. The server checks it. Five wrong tries lock that student for
   ten minutes (an instructor can issue a new PIN at any time).
3. The run is tied to that student **when it starts**, so it can never end
   up under whoever signs in next.
4. When the run ends it's scored on the headset (instant result for the
   student) and sent to the server, which scores it again. The server's
   score is the one of record. The dashboard updates on the next refresh.
5. **Next Student** on the result screen, ending the session, or returning
   to the home screen signs the student out.

## When things go wrong

| Situation | What happens |
| --- | --- |
| Wi-Fi drops mid-run | The run finishes normally and waits on the headset (encrypted file). It sends when the headset is back online, and a retry can never create a duplicate. |
| Wi-Fi is down at sign-in | The last roster the headset saw is shown. The student enters their PIN; it's checked when the run is sent. A wrong PIN keeps the run but marks it "PIN not confirmed", and it can't count toward competency. |
| A student is deleted while a run is waiting | The server refuses it; the headset drops it and says so. Deleting a student erases them everywhere. |
| A headset is lost or stolen | Admin presses **Disconnect**. Its token stops working immediately. |
| An instructor leaves | Admin presses **Remove access**. They are signed out everywhere at once. |
| Someone guesses | Passwords: 8 tries per 5 minutes. Pairing codes: single-use, 10 minutes, 10 tries per 5 minutes. PINs: 5 tries, then a 10-minute lock. |
| Two schools on one server | Every read and write is filtered by school. The test suite tries to cross the line through every route and fails each time. |
| Guest on a headset | Practice only. Nothing is scored or sent. |

## What only the operator can do

Server-wide detection thresholds (`PATCH /settings`) need the
`SPAI_OPERATOR_KEY` header. No school can change them for another.

## Still to do before a hospital

- **Single sign-on** (school Google or Microsoft accounts) instead of
  separate SPAI passwords.
- **Password reset by email.** Today an admin re-invites someone who forgets.
- **A signed data-processing agreement** (FERPA for schools, plus a security
  review for hospitals), and a decision on Ask SPAI's use of Google Gemini.
- **Postgres and automated backups** once there are several schools.
  `python -m app.admin backup <file>` works today; run it daily.
