#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
catalog_path="${project_dir}/Sources/RightClickCore/Localizable.xcstrings"

# L10n key 必须是字面量。当前代码全部遵守；若将来拼接动态 key，这个静态检查
# 会漏检而不会误报，届时应显式扩展脚本或为动态集合提供清单。
python3 - "${project_dir}/Sources" "${catalog_path}" <<'PY'
import json
import pathlib
import re
import sys

sources_root = pathlib.Path(sys.argv[1])
catalog_path = pathlib.Path(sys.argv[2])
pattern = re.compile(r'L10n\.(?:text|format)\(\s*"([^"]+)"')

used = set()
for source in sources_root.rglob("*.swift"):
    used.update(pattern.findall(source.read_text(encoding="utf-8")))

catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = catalog.get("strings", {})
defined = set(strings)
missing_definitions = sorted(used - defined)
missing_translations = []
for key in sorted(defined):
    localizations = strings[key].get("localizations", {})
    for language in ("en", "zh-Hans"):
        value = (
            localizations.get(language, {})
            .get("stringUnit", {})
            .get("value")
        )
        if not isinstance(value, str) or not value:
            missing_translations.append(f"{key} [{language}]")

unused = sorted(defined - used)
if unused:
    print("warning: localization keys defined but unused:")
    for key in unused:
        print(f"  {key}")

if missing_definitions:
    print("error: localization keys used but not defined:", file=sys.stderr)
    for key in missing_definitions:
        print(f"  {key}", file=sys.stderr)

if missing_translations:
    print("error: localization keys missing translations:", file=sys.stderr)
    for item in missing_translations:
        print(f"  {item}", file=sys.stderr)

if missing_definitions or missing_translations:
    raise SystemExit(1)

print(
    f"Localization verified: {len(used)} used keys, "
    f"{len(defined)} defined keys, en and zh-Hans complete."
)
PY
