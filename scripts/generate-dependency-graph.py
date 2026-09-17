#!/usr/bin/env python3
"""
Generates code-dependency-graph.json at the repo root from the current state of every
Swift file under SPAI/, SPAITests/, and Packages/RealityKitContent/.

Static analysis by regex, not a compiler AST: it finds type declarations (class/struct/
enum/protocol/actor/extension) per file and word-boundary references to those type names
in every other file, and turns each reference into a file-to-file edge. That is a strong
approximation, not ground truth — two unrelated types sharing a name, or a name that only
appears in a comment, can produce a spurious edge. Good enough to answer "what touches
what" while working through the codebase; not a substitute for reading the code when a
specific edge matters.

Regenerate after any change that adds/removes a file, renames a type, or changes what
references what:

    python3 scripts/generate-dependency-graph.py

Run from anywhere; the repo root is derived from this script's location.
"""
import re
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent

SRC_DIRS = ["SPAI", "SPAITests", "Packages/RealityKitContent/Sources/RealityKitContent"]

DECL_RE = re.compile(
    r'^\s*(?:@[\w:().,\s"\'/<>\[\]]+\s+)*'
    r'(?:public |private |internal |fileprivate |open |final |static |indirect )*'
    r'(class|struct|enum|protocol|actor|extension)\s+'
    r'([A-Za-z_][A-Za-z0-9_]*)',
    re.MULTILINE,
)
IMPORT_RE = re.compile(r'^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)', re.MULTILINE)

# Type names common/generic enough that matching them creates noise rather than signal.
STOPWORDS = {"View", "Content", "Body", "Error", "State", "Item"}

VIEW_FILENAMES = {
    "AppBackground.swift", "TourInterruptPopup.swift", "TourCoachmark.swift",
    "StatusPill.swift", "FeatureCard.swift", "LEDBorder.swift",
    "ToggleImmersiveSpaceButton.swift", "WristMenuPanel.swift",
}
MODEL_FILENAMES = {
    "AppModel.swift", "SessionRecord.swift", "DetectionStatus.swift",
    "DetectionTuning.swift", "StationScripts.swift", "WristGesture.swift", "AppTour.swift",
}


def categorize(relpath: str, decls: list[dict]) -> str:
    name = pathlib.Path(relpath).name
    if relpath.startswith("SPAITests/") or name.endswith("Tests.swift"):
        return "test"
    if name == "Package.swift":
        return "package-manifest"
    if "+" in name:
        return "extension"
    if name.endswith(("Service.swift", "Manager.swift", "Client.swift", "Detector.swift")):
        return "service"
    if name.endswith(("Panel.swift", "View.swift")) or name in VIEW_FILENAMES:
        return "view"
    if name in MODEL_FILENAMES:
        return "model"
    if name == "DesignTokens.swift":
        return "design-system"
    if name == "SPAIApp.swift":
        return "app-entry"
    if name == "SPAILog.swift":
        return "infrastructure"
    return "other"


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True
    ).stdout.strip()


def main() -> None:
    files = []
    for d in SRC_DIRS:
        files.extend(sorted((ROOT / d).rglob("*.swift")))

    nodes: dict[str, dict] = {}
    raw: dict[str, str] = {}

    for f in files:
        rel = str(f.relative_to(ROOT))
        text = f.read_text(errors="ignore")
        raw[rel] = text
        decls = [
            {"kind": m.group(1), "name": m.group(2)}
            for m in DECL_RE.finditer(text)
        ]
        nodes[rel] = {
            "imports": sorted(set(IMPORT_RE.findall(text))),
            "declarations": decls,
            "lines": text.count("\n") + 1,
        }

    type_owner: dict[str, list[str]] = {}
    type_extenders: dict[str, list[str]] = {}
    for rel, info in nodes.items():
        for d in info["declarations"]:
            bucket = type_extenders if d["kind"] == "extension" else type_owner
            bucket.setdefault(d["name"], []).append(rel)

    candidate_types = [
        t for t in sorted(set(type_owner) | set(type_extenders)) if t not in STOPWORDS
    ]
    type_regexes = {t: re.compile(r'\b' + re.escape(t) + r'\b') for t in candidate_types}

    edges = []
    for rel, text in raw.items():
        own_decls = {d["name"] for d in nodes[rel]["declarations"]}
        targets: dict[str, set[str]] = {}
        for t in candidate_types:
            if t in own_decls or not type_regexes[t].search(text):
                continue
            for owner_file in type_owner.get(t, []):
                if owner_file != rel:
                    targets.setdefault(owner_file, set()).add(t)
        for target_file, via in targets.items():
            edges.append({"from": rel, "to": target_file, "via": sorted(via)})

    extension_edges = []
    for rel, info in nodes.items():
        for d in info["declarations"]:
            if d["kind"] != "extension":
                continue
            for owner_file in type_owner.get(d["name"], []):
                if owner_file != rel:
                    extension_edges.append(
                        {"from": rel, "to": owner_file, "extends": d["name"]}
                    )

    graph = {
        "$schema_note": (
            "Code dependency graph for SPAI. Nodes are Swift source files; edges are "
            "file-to-file dependencies inferred from type usage (regex-based static "
            "analysis, not a compiler AST — a strong approximation, not ground truth). "
            "Regenerate with scripts/generate-dependency-graph.py after structural changes."
        ),
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generated_from_commit": git("rev-parse", "--short", "HEAD") or None,
        "generated_from_branch": git("rev-parse", "--abbrev-ref", "HEAD") or None,
        "working_tree_dirty": bool(git("status", "--porcelain")),
        "stats": {
            "file_count": len(nodes),
            "type_count": len(type_owner),
            "edge_count": len(edges),
            "extension_edge_count": len(extension_edges),
        },
        "nodes": [
            {
                "id": rel,
                "category": categorize(rel, info["declarations"]),
                "imports": info["imports"],
                "declares": info["declarations"],
                "lines": info["lines"],
            }
            for rel, info in sorted(nodes.items())
        ],
        "edges": sorted(edges, key=lambda e: (e["from"], e["to"])),
        "extension_edges": sorted(extension_edges, key=lambda e: (e["from"], e["to"])),
        "type_index": {
            t: {
                "declared_in": type_owner.get(t, []),
                "extended_in": type_extenders.get(t, []),
            }
            for t in sorted(set(type_owner) | set(type_extenders))
        },
    }

    out_path = ROOT / "code-dependency-graph.json"
    graph_text = json.dumps(graph, indent=2) + "\n"
    out_path.write_text(graph_text)
    print(f"wrote {out_path}", file=sys.stderr)
    print(
        f"files={len(nodes)} types={len(type_owner)} "
        f"edges={len(edges)} ext_edges={len(extension_edges)}",
        file=sys.stderr,
    )

    # The interactive viewer embeds the graph inline (Artifacts and a plain double-clicked
    # file both need this to work with no server behind it), so it is baked fresh from the
    # template on every run rather than kept as a second, independently-editable copy that
    # would drift from the JSON the moment either one changed.
    template_path = ROOT / "scripts" / "dependency-map.template.html"
    if template_path.exists():
        template = template_path.read_text()
        if "__GRAPH_JSON__" not in template:
            print(
                f"warning: {template_path} has no __GRAPH_JSON__ placeholder; "
                "skipping dependency-map.html",
                file=sys.stderr,
            )
        else:
            viewer_path = ROOT / "dependency-map.html"
            viewer_path.write_text(template.replace("__GRAPH_JSON__", graph_text.rstrip("\n")))
            print(f"wrote {viewer_path}", file=sys.stderr)
    else:
        print(f"note: {template_path} not found; skipping dependency-map.html", file=sys.stderr)


if __name__ == "__main__":
    main()
