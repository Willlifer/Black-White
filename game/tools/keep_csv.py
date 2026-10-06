"""Mark every data/*.csv as importer="keep" so Godot leaves it as plain text.

Godot imports any .csv as a translation table by default, which creates
.translation files next to our data. Run after adding a new table; the
self-test fails if a table is missing its keep file.
"""
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent / "data"
for csv in sorted(root.glob("*.csv")):
    imp = csv.with_name(csv.name + ".import")
    want = '[remap]\n\nimporter="keep"\n'
    if not imp.exists() or imp.read_text() != want:
        imp.write_text(want)
        print("keep:", csv.name)
for t in root.glob("*.translation"):
    t.unlink(); print("removed:", t.name)
