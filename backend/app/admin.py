"""
Server operator commands: onboard a school, back up, list schools.

    python -m app.admin create-org --name "Riverside College SPD Program" \\
        --admin-email director@riverside.edu --url https://spai.example.com
    python -m app.admin invite-admin --org ORG_ID --email someone@riverside.edu --url https://spai.example.com
    python -m app.admin list-orgs
    python -m app.admin backup /backups/spai-2026-11-16.db
    python -m app.admin doctor            # ready for a class? (add --ask to test Ask SPAI)

Creating an organization prints a one-time invite link for its first admin.
The admin opens it, sets their own password, and takes it from there:
inviting instructors, adding learners, pairing headsets. Nobody else ever
sees their password.
"""
from __future__ import annotations

import argparse
import sys

from app.store import StoreError, get_store


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m app.admin", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create-org", help="add a school or department and invite its first admin")
    c.add_argument("--name", required=True)
    c.add_argument("--admin-email", required=True)
    c.add_argument("--url", required=True, help="this server's public address, for the invite link")

    i = sub.add_parser("invite-admin", help="another admin invite for an existing organization")
    i.add_argument("--org", required=True)
    i.add_argument("--email", required=True)
    i.add_argument("--url", required=True)

    sub.add_parser("list-orgs", help="every organization on this server")

    d = sub.add_parser("doctor", help="is this server ready for a class or a demo?")
    d.add_argument("--ask", action="store_true", help="also send one real question to Ask SPAI's AI service")

    b = sub.add_parser("backup", help="a consistent copy of the database, safe while the server runs")
    b.add_argument("destination")

    args = ap.parse_args(argv)
    store = get_store()
    try:
        if args.cmd == "create-org":
            org = store.create_org(args.name)
            token = store.create_invite(org["id"], args.admin_email, "admin")
            store.audit(org["id"], "operator", "organization created", org["name"])
            print(f"Created {org['name']} ({org['id']}).")
            print(f"Send this link to {args.admin_email}. It works once, for 7 days:")
            print(f"  {args.url.rstrip('/')}/instructor#invite/{token}")
        elif args.cmd == "invite-admin":
            if store.get_org(args.org) is None:
                print("No organization with that id. See list-orgs.", file=sys.stderr)
                return 1
            token = store.create_invite(args.org, args.email, "admin")
            print(f"  {args.url.rstrip('/')}/instructor#invite/{token}")
        elif args.cmd == "list-orgs":
            for org in store.list_orgs():
                people = len(store.list_instructors(org["id"]))
                learners = len(store.list_learners(org["id"]))
                headsets = len(store.list_devices(org["id"]))
                print(f"{org['id']}  {org['name']}  · {people} instructors · {learners} learners · {headsets} headsets")
        elif args.cmd == "doctor":
            return doctor(store, args.ask)
        elif args.cmd == "backup":
            store.backup(args.destination)
            print(f"Backed up to {args.destination}")
    except StoreError as e:
        print(e, file=sys.stderr)
        return 1
    return 0


def doctor(store, try_ask: bool = False) -> int:
    """Go / no-go for the server, in plain words. Exit code 1 if anything
    would stop a class from working."""
    import os
    from pathlib import Path

    from app.inference.detector import detector
    from app.inference.tray_detector import tray_detector
    from app.store import DEFAULT_DB_PATH

    problems = 0

    def line(ok: bool | None, text: str, fix: str = "") -> None:
        nonlocal problems
        mark = {True: "PASS", False: "FAIL", None: "WARN"}[ok]
        if ok is False:
            problems += 1
        print(f"  {mark}  {text}")
        if fix and ok is not True:
            print(f"        → {fix}")

    print("SPAI server check\n")

    detector.load()
    tray_detector.load()
    line(detector.model_loaded, "Glove + hand model loaded" if detector.model_loaded else "Glove + hand model missing (stub mode)",
         "Put best.pt in backend/model/.")
    line(tray_detector.model_loaded, "Instrument model loaded" if tray_detector.model_loaded else "Instrument model missing (stub mode)",
         "Put instruments_best.pt in backend/model/.")

    db = Path(store.path).resolve()
    line(None if db == DEFAULT_DB_PATH.resolve() else True, f"Database at {db}",
         "Set SPAI_DB to a path on a persistent disk, or records are lost when the host restarts.")

    line(True if os.getenv("GEMINI_API_KEY") else None, "Ask SPAI has an AI key" if os.getenv("GEMINI_API_KEY") else "Ask SPAI has no AI key",
         "Set GEMINI_API_KEY. Everything else works without it.")
    if try_ask and os.getenv("GEMINI_API_KEY"):
        from app.ask_spai import ask_spai
        try:
            answer = ask_spai("decontamination", 0, "gloves detected", "What do I put on first?")
            line(True, f"Ask SPAI answered: {answer[:70]}…")
        except Exception as e:  # report, don't crash the check
            line(False, f"Ask SPAI failed: {e}", "Check the key and that the server can reach Google's API.")

    retention = os.getenv("SPAI_RETENTION_DAYS")
    line(True if retention else None, f"Runs kept {retention} days" if retention else "Runs kept until deleted",
         "Optional: set SPAI_RETENTION_DAYS to match the school's records policy.")

    orgs = store.list_orgs()
    line(bool(orgs), f"{len(orgs)} organization(s)", "Create one: python -m app.admin create-org --help")
    for org in orgs:
        people = store.list_instructors(org["id"])
        admins = [p for p in people if p["role"] == "admin" and not p["disabled"]]
        learners = store.list_learners(org["id"])
        headsets = store.list_devices(org["id"])
        print(f"\n  {org['name']}")
        line(bool(admins), f"{len(admins)} admin(s), {len(people)} account(s)",
             "Nobody can sign in yet. Send the admin invite again: python -m app.admin invite-admin --help")
        line(True if learners else None, f"{len(learners)} learner(s)", "Add the class on the dashboard, or run python -m app.seed_demo for a demo.")
        line(True if headsets else None, f"{len(headsets)} headset(s) connected", "Connect headsets from the dashboard's Headsets page.")
        if any(l["is_demo"] for l in learners):
            line(None, "Has sample data", "Remove it from the dashboard before real students use this school.")

    print(f"\n{'Ready.' if not problems else f'{problems} problem(s) to fix.'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
