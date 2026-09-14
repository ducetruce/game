#!/usr/bin/env python3
"""The writing surface: every line of in-game text, as plain Markdown.

    python3 tools/script.py export           # data/*.json  ->  script/*.md
    python3 tools/script.py import           # script/*.md  ->  data/*.json
    python3 tools/script.py check            # round-trips and reports what is
                                             # left to write
    python3 tools/script.py export --force   # overwrite even un-imported edits

Every piece of prose the game shows lives in data/ as JSON: what a sign says,
what a villager says at each point in a quest, what a tamer writes in a
letter, a quest's objective line, an item's description. JSON is the right
place for the game to read it from and the wrong place for a person to write
it: a stray comma breaks the file, quotes have to be escaped, and nothing
about it looks like a script.

So this pulls all of it out into script/, one Markdown file per area plus one
each for quests, items and creatures, and pushes edits back. The Markdown is
the writer's copy and the JSON is the game's; `export` regenerates the
Markdown from the JSON, `import` rewrites the text fields of the JSON from the
Markdown and touches nothing else. Each object is identified by a comment the
exporter writes and the writer leaves alone.

`export` refuses to overwrite a script/*.md file that holds edits `import`
has not yet pulled in -- otherwise a developer re-exporting after adding
content would silently erase writing in progress. `--force` overrides that,
for the rare case of wanting to throw an edit away on purpose.

Rules for the writer, all of which `import` checks:
  - One page of dialogue per bullet (`- `). Blank lines are ignored.
  - Headings are structure. Rename nothing above the bullets.
  - `[PLACEHOLDER]` marks a line nobody has written yet. `check` lists them.
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
MAPS = os.path.join(DATA, "maps")
SCRIPT = os.path.join(ROOT, "script")

PLACEHOLDER = "[PLACEHOLDER]"

# Text fields on a map object, by object type. `*` applies to every type.
# Each is a list of pages.
OBJECT_PAGE_FIELDS = {
    "*": ["text"],
    "tamer": ["intro", "rematch_intro", "beaten_text", "letter"],
}
# Single-string fields on a map object.
OBJECT_LINE_FIELDS = {
    "tamer": ["name"],
}


def load(path):
    with open(path) as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def save(path, doc) -> None:
    with open(path, "w") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def page_fields_for(obj_type: str) -> list[str]:
    return OBJECT_PAGE_FIELDS["*"] + OBJECT_PAGE_FIELDS.get(obj_type, [])


# --- export -------------------------------------------------------------------

def bullets(lines) -> list[str]:
    out = []
    for line in lines:
        out.append("- %s" % str(line))
    return out


def export_map(map_id: str, doc) -> str:
    out = ["# %s" % doc.get("display_name", map_id),
           "<!-- map %s -->" % map_id, ""]
    out += ["### display_name", "- %s" % doc.get("display_name", ""), ""]

    for i, obj in enumerate(doc.get("objects", [])):
        obj_type = obj.get("type", "?")
        if obj_type == "warp":
            continue
        tile = obj.get("tile", [0, 0])
        who = obj.get("name") or obj.get("id") or ""
        title = "%s at %d,%d" % (obj_type, tile[0], tile[1])
        if who:
            title += " -- %s" % who
        has_text = False
        section = ["## %s" % title, "<!-- object %d -->" % i]
        if obj.get("quest"):
            section.append("<!-- quest %s -->" % obj["quest"])
        section.append("")

        for field in OBJECT_LINE_FIELDS.get(obj_type, []):
            if field in obj:
                section += ["### %s" % field, "- %s" % obj[field], ""]
                has_text = True
        for field in page_fields_for(obj_type):
            if field in obj:
                section += ["### %s" % field] + bullets(obj[field]) + [""]
                has_text = True
        for j, variant in enumerate(obj.get("quest_text", [])):
            section += ["### quest_text %d from %s" % (j, variant.get("from", "?"))]
            section += bullets(variant.get("text", [])) + [""]
            has_text = True
        wants = obj.get("requires")
        if isinstance(wants, dict) and "text" in wants:
            section += ["### requires"] + bullets(wants["text"]) + [""]
            has_text = True
        if has_text:
            out += section
    return "\n".join(out).rstrip("\n") + "\n"


def export_quests(doc) -> str:
    out = ["# Quests", "<!-- quests -->", "",
           "### default_objective", "- %s" % doc.get("default_objective", ""), ""]
    for quest in doc.get("quests", []):
        out += ["## %s -- %s" % (quest.get("id"), quest.get("name", "")),
                "<!-- quest %s -->" % quest.get("id"), "",
                "### name", "- %s" % quest.get("name", ""), "",
                "### summary", "- %s" % quest.get("summary", ""), ""]
        for step in quest.get("steps", []):
            out += ["### step %s" % step.get("id"),
                    "- %s" % step.get("objective", ""), ""]
    return "\n".join(out).rstrip("\n") + "\n"


# Trial fields, all pages except "name" and "no_flee_message". Both are
# shared across kinds in the schema (an attune-only field costs nothing to
# export for a tamer trial that has not set it -- the "if field in trial"
# guard just skips it).
GAUNTLET_LINE_FIELDS = ["name", "no_flee_message"]
GAUNTLET_PAGE_FIELDS = [
    "intro", "victory", "defeat", "passed_text", "waiting_text", "spared",
]


def export_gauntlet(doc) -> str:
    # victory_text is a document-level field, not an object's -- it belongs
    # to the gauntlet as a whole, shown once after the last trial -- so it
    # goes under the file-level marker directly, the same way quests.md's
    # default_objective does, with no ## heading of its own.
    out = ["# The Gauntlet", "<!-- gauntlet -->", "",
           "### victory_text"] + bullets(doc.get("victory_text", [])) + [""]
    for trial in doc.get("trials", []):
        trial_id = trial.get("id")
        out += ["## %s -- %s" % (trial_id, trial.get("name", "")),
                "<!-- trial %s -->" % trial_id, ""]
        for field in GAUNTLET_LINE_FIELDS:
            if field in trial:
                out += ["### %s" % field, "- %s" % trial[field], ""]
        for field in GAUNTLET_PAGE_FIELDS:
            if field in trial:
                out += ["### %s" % field] + bullets(trial[field]) + [""]
    return "\n".join(out).rstrip("\n") + "\n"


def export_named(title: str, marker: str, entries, id_key: str = "id") -> str:
    out = ["# %s" % title, "<!-- %s -->" % marker, ""]
    for entry in entries:
        out += ["## %s -- %s" % (entry.get(id_key), entry.get("name", "")),
                "<!-- %s %s -->" % (marker, entry.get(id_key)), "",
                "### name", "- %s" % entry.get("name", ""), "",
                "### description", "- %s" % entry.get("description", ""), ""]
    return "\n".join(out).rstrip("\n") + "\n"


def _pending_edits(path: str) -> bool:
    """True if `path` holds writing not yet pulled into data/ -- i.e. import
    would change something. Only meaningful for a file that already exists;
    a fresh export has nothing to protect."""
    if not os.path.exists(path):
        return False
    filename = os.path.basename(path)
    stem = filename[: -len(".md")]
    try:
        if stem == "quests":
            return import_quests(path, dry_run=True) > 0
        if stem == "gauntlet":
            return import_gauntlet(path, dry_run=True) > 0
        if stem == "items":
            return import_named(path, "items", "item", "items", dry_run=True) > 0
        if stem == "creatures":
            return import_named(path, "creatures", "creature", "creatures",
                                dry_run=True) > 0
        if os.path.exists(os.path.join(MAPS, stem + ".json")):
            return import_map(path, stem, dry_run=True) > 0
    except ScriptError:
        # A currently-broken file is definitely not safe to overwrite --
        # that is where the writer's half-finished edit lives.
        return True
    return False


def export_all(force: bool = False) -> int:
    """Regenerates every script/*.md from data/*.json.

    Refuses (unless `force`) to overwrite a file that holds edits not yet
    imported: export always regenerates from the JSON, so writing straight
    over an edited-but-not-yet-imported .md would silently discard whatever
    the writer had just typed. This is the one place that can happen --
    import already writes only the file it was given -- so it is the one
    place that checks.
    """
    os.makedirs(SCRIPT, exist_ok=True)
    pending = []
    for filename in sorted(os.listdir(SCRIPT)) if os.path.isdir(SCRIPT) else []:
        if filename.endswith(".md") and _pending_edits(os.path.join(SCRIPT, filename)):
            pending.append(filename)
    if pending and not force:
        print("export refused: these have edits not yet imported:")
        for filename in pending:
            print("  script/%s" % filename)
        print("Run 'tools/script.py import' first to keep them, or re-run")
        print("export with --force to discard them and regenerate from data/.")
        return 1

    written = []
    for filename in sorted(os.listdir(MAPS)):
        if not filename.endswith(".json"):
            continue
        map_id = filename[: -len(".json")]
        doc = load(os.path.join(MAPS, filename))
        path = os.path.join(SCRIPT, map_id + ".md")
        with open(path, "w") as fh:
            fh.write(export_map(map_id, doc))
        written.append(path)
    for name, exporter in (
        ("quests", lambda d: export_quests(d)),
        ("gauntlet", lambda d: export_gauntlet(d)),
        ("items", lambda d: export_named("Items", "item", d.get("items", []))),
        ("creatures", lambda d: export_named("Creatures", "creature", d.get("creatures", []))),
    ):
        doc = load(os.path.join(DATA, name + ".json"))
        path = os.path.join(SCRIPT, name + ".md")
        with open(path, "w") as fh:
            fh.write(exporter(doc))
        written.append(path)
    for path in written:
        print("wrote %s" % os.path.relpath(path, ROOT))
    return 0


# --- import -------------------------------------------------------------------

class ScriptError(Exception):
    pass


def parse_markdown(path: str):
    """Yields (section_key, heading, lines) for every ### heading.

    section_key is the nearest preceding <!-- ... --> comment at ## level (or
    the file-level one), so text is tied to an object id rather than to a
    human-readable title the writer might reasonably want to change.
    """
    with open(path) as fh:
        raw = fh.read().splitlines()
    file_key = None
    section_key = None
    heading = None
    lines: list[str] = []
    started = False

    def flush():
        if heading is not None:
            yield_list.append((section_key or file_key, heading, list(lines), heading_line))

    yield_list: list = []
    heading_line = 0
    for number, line in enumerate(raw, 1):
        comment = re.match(r"^<!--\s*(.*?)\s*-->$", line.strip())
        if comment:
            key = comment.group(1)
            if file_key is None:
                file_key = key
            else:
                # A quest marker under an object is annotation, not identity.
                if not key.startswith("quest ") or section_key is None:
                    section_key = key
                elif section_key.startswith("object "):
                    pass
                else:
                    section_key = key
            continue
        if line.startswith("## ") and not line.startswith("### "):
            flush()
            heading = None
            lines = []
            section_key = None
            continue
        if line.startswith("### "):
            flush()
            heading = line[4:].strip()
            heading_line = number
            lines = []
            continue
        if line.startswith("# "):
            continue
        stripped = line.strip()
        if not stripped:
            continue
        if heading is None:
            raise ScriptError("%s:%d: text outside any heading: %r"
                              % (os.path.relpath(path, ROOT), number, stripped))
        if not stripped.startswith("- "):
            raise ScriptError("%s:%d: every line of text must start with '- ' "
                              "(one page per bullet); got %r"
                              % (os.path.relpath(path, ROOT), number, stripped))
        lines.append(stripped[2:])
    flush()
    return file_key, yield_list


def one_line(entries, path, heading) -> str:
    if len(entries) != 1:
        raise ScriptError("%s: '%s' takes exactly one line, got %d"
                          % (os.path.relpath(path, ROOT), heading, len(entries)))
    return entries[0]


def import_map(path: str, map_id: str, dry_run: bool = False) -> int:
    json_path = os.path.join(MAPS, map_id + ".json")
    doc = load(json_path)
    objects = doc.get("objects", [])
    _, sections = parse_markdown(path)
    changed = 0

    def set_if_changed(container, key, value):
        nonlocal changed
        if container.get(key) != value:
            container[key] = value
            changed += 1

    for key, heading, lines, number in sections:
        where = "%s:%d" % (os.path.relpath(path, ROOT), number)
        if key == "map %s" % map_id:
            if heading == "display_name":
                set_if_changed(doc, "display_name", one_line(lines, path, heading))
            else:
                raise ScriptError("%s: unknown map heading '%s'" % (where, heading))
            continue
        match = re.match(r"^object (\d+)$", key or "")
        if not match:
            raise ScriptError("%s: heading '%s' is not under an object marker"
                              % (where, heading))
        index = int(match.group(1))
        if index >= len(objects):
            raise ScriptError("%s: object %d does not exist in %s (re-export?)"
                              % (where, index, map_id))
        obj = objects[index]
        obj_type = obj.get("type", "")
        if not lines:
            raise ScriptError("%s: '%s' has no lines" % (where, heading))

        if heading in OBJECT_LINE_FIELDS.get(obj_type, []):
            set_if_changed(obj, heading, one_line(lines, path, heading))
        elif heading in page_fields_for(obj_type):
            set_if_changed(obj, heading, lines)
        elif heading == "requires":
            if not isinstance(obj.get("requires"), dict):
                raise ScriptError("%s: object %d has no 'requires'" % (where, index))
            set_if_changed(obj["requires"], "text", lines)
        else:
            match = re.match(r"^quest_text (\d+) from (\S+)$", heading)
            if not match:
                raise ScriptError("%s: unknown heading '%s' for a %s"
                                  % (where, heading, obj_type))
            j = int(match.group(1))
            variants = obj.get("quest_text", [])
            if j >= len(variants):
                raise ScriptError("%s: object %d has no quest_text %d"
                                  % (where, index, j))
            if variants[j].get("from") != match.group(2):
                raise ScriptError("%s: quest_text %d is from '%s', not '%s' -- "
                                  "the step in the heading is structure, not text"
                                  % (where, j, variants[j].get("from"), match.group(2)))
            set_if_changed(variants[j], "text", lines)
    if changed and not dry_run:
        save(json_path, doc)
    return changed


def import_quests(path: str, dry_run: bool = False) -> int:
    json_path = os.path.join(DATA, "quests.json")
    doc = load(json_path)
    by_id = {q.get("id"): q for q in doc.get("quests", [])}
    _, sections = parse_markdown(path)
    changed = 0
    for key, heading, lines, number in sections:
        where = "%s:%d" % (os.path.relpath(path, ROOT), number)
        if key == "quests":
            if heading != "default_objective":
                raise ScriptError("%s: unknown heading '%s'" % (where, heading))
            value = one_line(lines, path, heading)
            if doc.get("default_objective") != value:
                doc["default_objective"] = value
                changed += 1
            continue
        match = re.match(r"^quest (\S+)$", key or "")
        if not match or match.group(1) not in by_id:
            raise ScriptError("%s: heading '%s' is not under a known quest"
                              % (where, heading))
        quest = by_id[match.group(1)]
        if heading in ("name", "summary"):
            value = one_line(lines, path, heading)
            if quest.get(heading) != value:
                quest[heading] = value
                changed += 1
        else:
            step_match = re.match(r"^step (\S+)$", heading)
            if not step_match:
                raise ScriptError("%s: unknown quest heading '%s'" % (where, heading))
            steps = [s for s in quest.get("steps", []) if s.get("id") == step_match.group(1)]
            if not steps:
                raise ScriptError("%s: quest '%s' has no step '%s'"
                                  % (where, quest.get("id"), step_match.group(1)))
            value = one_line(lines, path, heading)
            if steps[0].get("objective") != value:
                steps[0]["objective"] = value
                changed += 1
    if changed and not dry_run:
        save(json_path, doc)
    return changed


def import_gauntlet(path: str, dry_run: bool = False) -> int:
    json_path = os.path.join(DATA, "gauntlet.json")
    doc = load(json_path)
    by_id = {t.get("id"): t for t in doc.get("trials", [])}
    _, sections = parse_markdown(path)
    changed = 0
    for key, heading, lines, number in sections:
        where = "%s:%d" % (os.path.relpath(path, ROOT), number)
        if key == "gauntlet":
            if heading != "victory_text":
                raise ScriptError("%s: unknown heading '%s'" % (where, heading))
            if doc.get("victory_text") != lines:
                doc["victory_text"] = lines
                changed += 1
            continue
        match = re.match(r"^trial (\S+)$", key or "")
        if not match or match.group(1) not in by_id:
            raise ScriptError("%s: heading '%s' is not under a known trial"
                              % (where, heading))
        trial = by_id[match.group(1)]
        if heading in GAUNTLET_LINE_FIELDS:
            value = one_line(lines, path, heading)
            if trial.get(heading) != value:
                trial[heading] = value
                changed += 1
        elif heading in GAUNTLET_PAGE_FIELDS:
            if trial.get(heading) != lines:
                trial[heading] = lines
                changed += 1
        else:
            raise ScriptError("%s: unknown trial heading '%s'" % (where, heading))
    if changed and not dry_run:
        save(json_path, doc)
    return changed


def import_named(path: str, name: str, marker: str, list_key: str, dry_run: bool = False) -> int:
    json_path = os.path.join(DATA, name + ".json")
    doc = load(json_path)
    by_id = {e.get("id"): e for e in doc.get(list_key, [])}
    _, sections = parse_markdown(path)
    changed = 0
    for key, heading, lines, number in sections:
        where = "%s:%d" % (os.path.relpath(path, ROOT), number)
        match = re.match(r"^%s (\S+)$" % marker, key or "")
        if not match or match.group(1) not in by_id:
            raise ScriptError("%s: heading '%s' is not under a known %s"
                              % (where, heading, marker))
        if heading not in ("name", "description"):
            raise ScriptError("%s: unknown heading '%s'" % (where, heading))
        entry = by_id[match.group(1)]
        value = one_line(lines, path, heading)
        if entry.get(heading) != value:
            entry[heading] = value
            changed += 1
    if changed and not dry_run:
        save(json_path, doc)
    return changed


def import_all() -> int:
    if not os.path.isdir(SCRIPT):
        print("nothing to import: script/ does not exist (run export first)")
        return 1
    total = 0
    for filename in sorted(os.listdir(SCRIPT)):
        if not filename.endswith(".md"):
            continue
        path = os.path.join(SCRIPT, filename)
        stem = filename[: -len(".md")]
        if stem == "quests":
            n = import_quests(path)
        elif stem == "gauntlet":
            n = import_gauntlet(path)
        elif stem == "items":
            n = import_named(path, "items", "item", "items")
        elif stem == "creatures":
            n = import_named(path, "creatures", "creature", "creatures")
        elif os.path.exists(os.path.join(MAPS, stem + ".json")):
            n = import_map(path, stem)
        else:
            print("skipping %s: no data file matches it" % filename)
            continue
        if n:
            print("%s: %d field(s) updated" % (filename, n))
        total += n
    print("%d field(s) changed. Run tools/validate_data.py before playing." % total)
    return 0


# --- check --------------------------------------------------------------------

def check() -> int:
    """Exports to a scratch copy, imports it back, confirms nothing moved, and
    lists every placeholder still standing."""
    import tempfile
    import shutil

    global SCRIPT
    real_script = SCRIPT
    before = {}
    for dirpath, _, files in os.walk(DATA):
        for f in files:
            if f.endswith(".json"):
                p = os.path.join(dirpath, f)
                before[p] = open(p).read()

    with tempfile.TemporaryDirectory() as tmp:
        SCRIPT = tmp
        export_all()
        import_all()
    SCRIPT = real_script

    moved = [p for p, text in before.items() if open(p).read() != text]
    for p in moved:
        print("ROUND TRIP CHANGED %s" % os.path.relpath(p, ROOT))
        with open(p, "w") as fh:
            fh.write(before[p])

    remaining = []
    for dirpath, _, files in os.walk(DATA):
        for f in sorted(files):
            if not f.endswith(".json"):
                continue
            p = os.path.join(dirpath, f)
            for number, line in enumerate(open(p), 1):
                if PLACEHOLDER in line:
                    remaining.append("%s:%d" % (os.path.relpath(p, ROOT), number))
    print("\n%d placeholder line(s) still to write%s"
          % (len(remaining), ":" if remaining else "."))
    for entry in remaining:
        print("  " + entry)
    return 1 if moved else 0


def main(argv) -> int:
    force = "--force" in argv
    positional = [a for a in argv[1:] if a != "--force"]
    if len(positional) != 1 or positional[0] not in ("export", "import", "check"):
        print(__doc__)
        return 2
    command = positional[0]
    try:
        if command == "export":
            return export_all(force=force)
        if command == "import":
            return import_all()
        return check()
    except ScriptError as exc:
        print("error: %s" % exc)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
