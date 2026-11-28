#!/usr/bin/env bash
# Every QML file parses (qmllint only for syntax: the Quickshell types are not installed here, so their names are not
# checked). A duplicate property binding is reported here too: the engine refuses that component, so a menu that is
# loaded with the bar (BarPop.qml) takes the whole shell down with it. Needs qmllint (Arch: qt6-declarative); skipped
# when it is not there.
set -Euo pipefail
command -v qmllint >/dev/null || { echo "qmllint is not installed: skipped"; exit 0; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# no list of files is a failed check, not a pass (a wrong root used to print find's error and then "ok")
list="$(mktemp)"; trap 'rm -f "$list"' EXIT
if ! find "$root/quickshell" -name '*.qml' -print0 >"$list" 2>/dev/null || [ ! -s "$list" ]; then
  echo "not ok - no QML files under $root/quickshell"
  exit 1
fi
bad=0
while IFS= read -r -d '' f; do
  if qmllint "$f" 2>&1 | grep -qE 'syntax\]|duplicate-property-binding'; then
    echo "not ok - ${f#"$root"/}"
    qmllint "$f" 2>&1 | grep -E 'syntax\]|duplicate-property-binding' | head -3
    bad=1
  fi
done <"$list"
[ "$bad" = 0 ] && echo "ok - every QML file parses, nothing bound twice"
exit "$bad"
