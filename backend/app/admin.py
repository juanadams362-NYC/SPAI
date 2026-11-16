"""
Server operator commands: onboard a school, back up, list schools.

    python -m app.admin create-org --name "Riverside College SPD Program" \\
        --admin-email director@riverside.edu --url https://spai.example.com
    python -m app.admin invite-admin --org ORG_ID --email someone@riverside.edu --url https://spai.example.com
    python -m app.admin list-orgs
    python -m app.admin backup /backups/spai-2026-11-16.db

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
        elif args.cmd == "backup":
            store.backup(args.destination)
            print(f"Backed up to {args.destination}")
    except StoreError as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
