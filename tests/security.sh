#!/usr/bin/env bash
# Checks for the security helpers in install/lib/secure.sh, the pinned hashes in install/checksums.txt and the
# update guards. Runs anywhere (no Linux, no network) and in CI on every push.
set -Euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

warn() { echo "  warn: $*" >&2; }
fail() { echo "  fail: $*" >&2; }
ROOT="$tmp/repo"
CHECKSUMS="$root/install/checksums.txt"
# shellcheck source=../install/lib/secure.sh
. "$root/install/lib/secure.sh"

n=0
ok() { n=$((n + 1)); printf 'ok %d - %s\n' "$n" "$1"; }
bad() { printf 'not ok %d - %s\n' "$n" "$1"; exit 1; }

# ---- the checksum list: "<64 hex>  <name>", unique names
awk 'NF && $1 !~ /^#/ { print NF, $1, $2 }' "$CHECKSUMS" >"$tmp/list"
[ -s "$tmp/list" ] && ok "checksums.txt has entries" || bad "checksums.txt is empty"
while read -r fields hash name; do
  [ "$fields" = 2 ] || bad "not two fields: $hash $name"
  case "$hash" in *[!0-9a-f]*|"") bad "not a lowercase SHA-256: $hash" ;; esac
  [ "${#hash}" = 64 ] || bad "not 64 characters: $hash"
done <"$tmp/list"
ok "every line is a SHA-256 and a file name"
[ -z "$(cut -d' ' -f3 "$tmp/list" | sort | uniq -d)" ] && ok "no duplicate names" || bad "duplicate names"

# ---- the helpers: pinned name, bad hash, no pin, archive paths
printf payload >"$tmp/f"
[ "$(sha256_of "$tmp/f")" = "$(printf payload | shasum -a 256 | cut -d' ' -f1)" ] && ok "sha256_of" || bad "sha256_of"
printf '%s  known.bin\n' "$(sha256_of "$tmp/f")" >"$tmp/own.txt"
CHECKSUMS="$tmp/own.txt"
[ "$(expected_sha known.bin)" = "$(sha256_of "$tmp/f")" ] && ok "expected_sha finds the pinned hash" || bad "expected_sha"
[ -z "$(expected_sha other.bin)" ] && ok "expected_sha is empty for an unknown file" || bad "expected_sha unknown"
printf 'not the pinned bytes' >"$tmp/bad.bin"
fetch_verified "file://$tmp/bad.bin" "$tmp/dl.bin" known.bin && bad "fetch_verified accepted a bad hash"
[ ! -e "$tmp/dl.bin" ] && ok "fetch_verified refuses a bad hash and deletes it" || bad "fetch_verified left a bad file"
fetch_verified "file://$tmp/f" "$tmp/dl2.bin" other.bin && bad "fetch_verified accepted an unpinned name"
[ ! -e "$tmp/dl2.bin" ] && ok "fetch_verified refuses an unpinned name" || bad "fetch_verified downloaded unpinned"

mkdir -p "$tmp/src/pkg" && echo hi >"$tmp/src/pkg/file"
tar -cf "$tmp/good.tar" -C "$tmp/src" pkg
mkdir -p "$tmp/dest"
extract_verified "$tmp/good.tar" "$tmp/dest" && [ -f "$tmp/dest/pkg/file" ] && ok "extract_verified unpacks a good archive" \
  || bad "extract_verified failed on a good archive"
python3 - "$tmp/evil.tar" "$tmp/abs.tar" <<'PY'
import io, sys, tarfile
for path, name in ((sys.argv[1], "../escaped"), (sys.argv[2], "/tmp/escaped")):
    with tarfile.open(path, "w") as t:
        i = tarfile.TarInfo(name)
        i.size = 1
        t.addfile(i, io.BytesIO(b"x"))
PY
mkdir -p "$tmp/out"
extract_verified "$tmp/evil.tar" "$tmp/out" && bad "extract_verified accepted ../"
[ ! -e "$tmp/escaped" ] && ok "extract_verified refuses ../ (nothing written)" || bad "extract_verified wrote outside"
extract_verified "$tmp/abs.tar" "$tmp/out" && bad "extract_verified accepted an absolute path"
[ ! -e /tmp/escaped ] && ok "extract_verified refuses absolute paths" || { rm -f /tmp/escaped; bad "wrote /tmp/escaped"; }

mkdir -p "$tmp/ln/pkg" && ln -s /etc "$tmp/ln/pkg/out" && ln -s ../../x "$tmp/ln/pkg/up"
tar -cf "$tmp/link.tar" -C "$tmp/ln" pkg/out
tar -cf "$tmp/link2.tar" -C "$tmp/ln" pkg/up
extract_verified "$tmp/link.tar" "$tmp/out" && bad "extract_verified accepted a link to /etc"
ok "extract_verified refuses a link pointing to an absolute path"
extract_verified "$tmp/link2.tar" "$tmp/out" && bad "extract_verified accepted a link to ../"
ok "extract_verified refuses a link pointing up with ../"

# ---- the update guards: remote allowlist, changed installer
mkdir -p "$ROOT"
git -C "$ROOT" init -q
printf 'echo old\n' >"$ROOT/install.sh"
git -C "$ROOT" add install.sh
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm old
old="$(git -C "$ROOT" rev-parse HEAD)"
printf 'echo new\n' >"$ROOT/install.sh"
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qam new
new="$(git -C "$ROOT" rev-parse HEAD)"
printf 'readme\n' >"$ROOT/README.md"
git -C "$ROOT" add README.md
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm other
other="$(git -C "$ROOT" rev-parse HEAD)"

remote() { git -C "$ROOT" remote remove origin 2>/dev/null; git -C "$ROOT" remote add origin "$1"; update_remote_ok; }
remote "git@github.com:notwafel/DarkShadowShell.git" && ok "accepts the ssh remote" || bad "ssh remote"
remote "https://github.com/shadowww-dev/DarkShadowShell" && ok "accepts the https remote" || bad "https remote"
remote "https://github.com/evil/DarkShadowShell" && ok "accepts a fork" || bad "fork remote"
remote "https://example.com/x/DarkShadowShell" && bad "accepted a foreign host" || ok "refuses a foreign host"
remote "https://evil.example/github.com/evil/DarkShadowShell" && bad "accepted a path on a foreign host" || ok "refuses a foreign host with a github.com path"
remote "ssh://git@evil.example/github.com/evil/DarkShadowShell.git" && bad "accepted a foreign ssh host" || ok "refuses a foreign ssh host"
remote "https://gitlab.com/github.com/evil/DarkShadowShell.git" && bad "accepted another host with a github.com path" || ok "refuses another host with a github.com path"
remote "https://github.com/evil/other" && bad "accepted another repo" || ok "refuses another repo"

update_guard "$old" "$old" && ok "same commit needs no confirmation" || bad "same commit"
update_guard "$new" "$other" </dev/null && ok "an update without a new installer passes" || bad "unchanged install.sh"
WAYLAND_DISPLAY= RICE_GUI=1 update_guard "$old" "$new" </dev/null && bad "started a changed installer from Settings"
ok "refuses a changed installer without a terminal"
out="$(update_guard "$old" "$new" </dev/null 2>&1 || true)"
case "$out" in *"install.sh"*) ok "says which file changed" ;; *) bad "no summary shown" ;; esac
RICE_TRUST_UPDATE=1 update_guard "$old" "$new" </dev/null && ok "RICE_TRUST_UPDATE=1 starts it" || bad "RICE_TRUST_UPDATE ignored"

mkdir -p "$ROOT/bin"
printf 'echo script\n' >"$ROOT/bin/rice-doctor"
git -C "$ROOT" add bin
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm scripts
scripts="$(git -C "$ROOT" rev-parse HEAD)"
WAYLAND_DISPLAY= RICE_GUI=1 update_guard "$new" "$scripts" </dev/null && bad "started a changed bin script from Settings"
ok "refuses a changed bin script without a terminal"

# ---- the question comes before the pull: a refused update leaves the files as they were
git clone -q "$ROOT" "$tmp/clone"
git -C "$tmp/clone" reset -q --hard "$old"
printf 'echo newer\n' >"$ROOT/install.sh"
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qam newer
( ROOT="$tmp/clone"; LOG=/dev/null; update_precheck </dev/null ) && bad "update_precheck let a changed installer through"
[ "$(git -C "$tmp/clone" rev-parse HEAD)" = "$old" ] && ok "a refused update moves nothing (asked before the pull)" \
  || bad "the files moved before the question"

# ---- rice-cursor reads the same list (installed copy) and refuses unpinned files
mkdir -p "$tmp/home/.local/bin" "$tmp/home/.local/share/rice"
cp "$root/bin/rice-cursor" "$tmp/home/.local/bin/"
cp "$root/install/checksums.txt" "$tmp/home/.local/share/rice/checksums.txt"
printf '%s  local.bin\nnot-a-hash  broken.bin\n' "$(sha256_of "$tmp/f")" >>"$tmp/home/.local/share/rice/checksums.txt"
HOME="$tmp/home" python3 - "$tmp/home" <<'PY' && ok "rice-cursor uses the list, ignores a bad line, refuses unpinned" || bad "rice-cursor checksums"
import importlib.machinery, importlib.util, os, sys
home = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("rc_test", home + "/.local/bin/rice-cursor")
spec = importlib.util.spec_from_loader("rc_test", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
assert m.checksum_file() == home + "/.local/share/rice/checksums.txt"
assert m.expected_sha("local.bin")
assert m.expected_sha("Bibata-Modern-Ice.tar.xz")
assert m.expected_sha("nothing-here.bin") == ""
assert m.expected_sha("broken.bin") == ""
assert m.get_bibata("Bibata-Modern-Amber") is False
PY

# ---- border-sync: the color file is read as Lua by hyprctl eval, so it may not carry code
mkdir -p "$tmp/bs/home/.config/hypr" "$tmp/bs/bin"
cat >"$tmp/bs/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
touch "$HYPR_MARK"
EOF
chmod +x "$tmp/bs/bin/hyprctl"
run_border() { HOME="$tmp/bs/home" PATH="$tmp/bs/bin:$PATH" HYPR_MARK="$tmp/bs/ran" bash "$root/bin/border-sync"; }
printf '%s\n%s\n' '0)ff)") } }) os.execute("id") --' '#ffffff' >"$tmp/bs/home/.config/hypr/border-colors.txt"
rm -f "$tmp/bs/ran"; run_border
[ ! -e "$tmp/bs/ran" ] && ok "border-sync refuses a line that is not a hex color" || bad "border-sync passed Lua through"
printf '%s\n%s\n' '#aabbcc' '#ddeeff' >"$tmp/bs/home/.config/hypr/border-colors.txt"
rm -f "$tmp/bs/ran"; run_border
[ -e "$tmp/bs/ran" ] && ok "border-sync still applies plain colors" || bad "border-sync refused a plain color"
# ---- rice-apps-helper: opening an archive does not write outside the folder it is opened in
python3 - "$root/bin/rice-apps-helper" "$tmp/evil.tar" "$tmp/good.tar" "$tmp/evil.zip" <<'PYA' && ok "an archive member with .. is refused" || bad "rice-apps-helper would unpack .."
import importlib.machinery, importlib.util, sys, zipfile
loader = importlib.machinery.SourceFileLoader("ah", sys.argv[1])
spec = importlib.util.spec_from_loader("ah", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
assert m.safe_names(sys.argv[2]) is False, "accepted ../ in tar"
assert m.safe_names(sys.argv[3]) is True, "refused a plain archive"
with zipfile.ZipFile(sys.argv[4], "w") as z:
    z.writestr("../escaped", "x")
assert m.safe_names(sys.argv[4]) is False, "accepted ../ in zip"
PYA

# ---- hypr-set: a command with an accent reaches the Lua config as UTF-8, not as an escape Lua cannot read
mkdir -p "$tmp/hs/home/.config/hypr" "$tmp/hs/bin"
printf '#!/usr/bin/env bash\necho ok\n' >"$tmp/hs/bin/hyprctl"
chmod +x "$tmp/hs/bin/hyprctl"
HOME="$tmp/hs/home" PATH="$tmp/hs/bin:$PATH" NIRI_SOCKET= HYPRLAND_INSTANCE_SIGNATURE= XDG_CURRENT_DESKTOP= \
  python3 "$root/bin/hypr-set" bind-add "SUPER + X" "notify-send café" >/dev/null 2>&1
hs="$tmp/hs/home/.config/hypr/rice-settings.lua"
grep -q 'café' "$hs" && ok "a bind command keeps its accent" || bad "the accent was escaped or lost"
grep -q '\\u00e9' "$hs" && bad "the Lua file has a \u escape" || ok "no \u escape in the Lua file"
# ---- rice-sddm: an update's new theme files are noticed (not only its .qml), so the installer puts them in
mkdir -p "$tmp/sd/theme/user" "$tmp/sd/repo/sddm/darkshadow-shell" "$tmp/sd/home/.config/rice"
printf '%s\n' 'import QtQuick' >"$tmp/sd/theme/Main.qml"
printf '%s\n' 'import QtQuick' >"$tmp/sd/repo/sddm/darkshadow-shell/Main.qml"
printf '%s\n' '[General]' 'clock=stacked' >"$tmp/sd/repo/sddm/darkshadow-shell/theme.conf"
printf '%s' "$tmp/sd/repo" >"$tmp/sd/home/.config/rice/repo"
sd_state() { HOME="$tmp/sd/home" RICE_SDDM_THEME="$tmp/sd/theme" bash "$root/bin/rice-sddm" state; }
sd_state >"$tmp/sd/state"   # no theme.conf in /usr/share yet: outdated
grep -q '"outdated": true' "$tmp/sd/state" && ok "a changed theme.conf marks the login screen outdated" || bad "theme.conf was not compared"
printf '%s\n' '[General]' 'clock=stacked' >"$tmp/sd/theme/theme.conf"
sd_state >"$tmp/sd/state"
grep -q '"outdated": false' "$tmp/sd/state" && ok "the same theme.conf is not outdated" || bad "the same theme.conf was called outdated"
grep -q 'MODE" = update.*outdated' "$root/install.sh" && ok "an update puts the new login screen in" || bad "an update leaves the login screen old"

# ---- rice-busy: a window far away on the Infinite Desktop's canvas does not hide the widgets
python3 - "$root/bin/rice-busy" <<'PYB' && ok "only a tiled window on that screen hides the widgets" || bad "a window off the screen hides the widgets"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("rb", sys.argv[1])
spec = importlib.util.spec_from_loader("rb", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
mon = {"name": "DP-1", "focused": True, "x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 1.0,
       "transform": 0, "activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}
def client(x, y, w=400, h=300, floating=False):
    return {"workspace": {"id": 1}, "mapped": True, "hidden": False, "floating": floating,
            "fullscreen": 0, "at": [x, y], "size": [w, h]}
def check(client, want):
    m.hypr = lambda what: [mon] if what == "monitors" else [client]
    return m.busy("DP-1") is want
assert check(client(-900, -700), False), "a window off the screen counted"
assert check(client(100, 100), True), "a tiled window on the screen did not count"
assert check(client(100, 100, floating=True), False), "a floating window counted"
assert check(client(0, -5000), False), "a window above the screen counted"
PYB
grep -q 'autoHide && busy && !editing && !locked && !Infinite.here' "$root/quickshell/rice-desktop/shell.qml" \
  && ok "the Infinite Desktop's floating windows leave the widgets out of auto-hide" || bad "auto-hide still hides widgets on the canvas"

# ---- rice-mirrors: reflector's list, and the old mirrorlist stays unless one was written
mkdir -p "$tmp/mr/bin" "$tmp/mr/etc"
printf 'Server = https://old/$repo/os/$arch\n' >"$tmp/mr/etc/mirrorlist"
printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$tmp/mr/etc/pacman.conf"
cat >"$tmp/mr/bin/reflector" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$REFLECTOR_ARGS"
[ "${MAKE_LIST:-0}" = 1 ] || exit 1
out=""
while [ $# -gt 0 ]; do [ "$1" = "--save" ] && { out="$2"; shift; }; shift; done
printf 'Server = https://new/$repo/os/$arch\n' >"$out"
EOS
cat >"$tmp/mr/bin/sudo" <<'EOS'
#!/usr/bin/env bash
exec "$@"
EOS
chmod +x "$tmp/mr/bin/reflector" "$tmp/mr/bin/sudo"
run_mirrors() { HOME="$tmp/mr/home" PATH="$tmp/mr/bin:$PATH" RICE_MIRRORS_DIR="$tmp/mr/etc" \
  RICE_MIRRORS_CONF="$tmp/mr/etc/pacman.conf" REFLECTOR_ARGS="$tmp/mr/args" MAKE_LIST="$1" \
  bash "$root/bin/rice-mirrors" >/dev/null 2>&1; }
run_mirrors 1 && grep -q 'https://new/' "$tmp/mr/etc/mirrorlist" && ok "reflector's list replaces the mirrorlist" \
  || bad "a good reflector list was not put in"
grep -q -- '--protocol' "$tmp/mr/args" && grep -q 'https' "$tmp/mr/args" && grep -q -- '--latest' "$tmp/mr/args" \
  && grep -q 'Poland,Germany,Czechia' "$tmp/mr/args" && grep -q -- '--sort' "$tmp/mr/args" \
  && ok "reflector: HTTPS, the freshest 20, by speed, the chosen countries" || bad "reflector's arguments changed"
printf 'Server = https://old/$repo/os/$arch\n' >"$tmp/mr/etc/mirrorlist"
run_mirrors 0 && bad "a failed reflector reported success" || ok "a failed reflector says so"
grep -q 'https://old/' "$tmp/mr/etc/mirrorlist" && ok "a failed reflector leaves the working mirrorlist" \
  || bad "a failed reflector wiped the mirrorlist"
# Artix: its own repos keep their mirrorlist, Arch's list (mirrorlist-arch) gets reflector's
mkdir -p "$tmp/mr3/etc"
printf 'Server = https://artix.example/$repo/os/$arch\n' >"$tmp/mr3/etc/mirrorlist"
printf 'Server = https://arch-old.example/$repo/os/$arch\n' >"$tmp/mr3/etc/mirrorlist-arch"
printf '[system]\nInclude = %s/mirrorlist\n[extra]\nInclude = %s/mirrorlist-arch\n' "$tmp/mr3/etc" "$tmp/mr3/etc" >"$tmp/mr3/etc/pacman.conf"
HOME="$tmp/mr/home" PATH="$tmp/mr/bin:$PATH" RICE_MIRRORS_DIR="$tmp/mr3/etc" RICE_MIRRORS_CONF="$tmp/mr3/etc/pacman.conf" \
  REFLECTOR_ARGS="$tmp/mr/args3" MAKE_LIST=1 bash "$root/bin/rice-mirrors" >/dev/null 2>&1 \
  && grep -q 'https://new/' "$tmp/mr3/etc/mirrorlist-arch" && grep -q 'artix.example' "$tmp/mr3/etc/mirrorlist" \
  && ok "Artix: Arch's list is replaced, Artix's own mirrors are kept" \
  || bad "Artix: the Artix mirrorlist was replaced with Arch mirrors"
# reflector missing: it is installed first (pacman), and nothing is run when that fails
mkdir -p "$tmp/mr2/bin" "$tmp/mr2/etc"
printf 'Server = https://old/$repo/os/$arch\n' >"$tmp/mr2/etc/mirrorlist"
printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$tmp/mr2/etc/pacman.conf"
cat >"$tmp/mr2/bin/pacman" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PACMAN_ARGS"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN_HERE/reflector"
chmod +x "$BIN_HERE/reflector"
EOS
cat >"$tmp/mr2/bin/sudo" <<'EOS'
#!/usr/bin/env bash
exec "$@"
EOS
chmod +x "$tmp/mr2/bin/pacman" "$tmp/mr2/bin/sudo"
HOME="$tmp/mr2/home" PATH="$tmp/mr2/bin:$PATH" BIN_HERE="$tmp/mr2/bin" PACMAN_ARGS="$tmp/mr2/args" \
  RICE_MIRRORS_DIR="$tmp/mr2/etc" RICE_MIRRORS_CONF="$tmp/mr2/etc/pacman.conf" \
  bash "$root/bin/rice-mirrors" >/dev/null 2>&1 \
  && bad "a missing reflector still reported success" || ok "a missing reflector is an error"
grep -q 'reflector' "$tmp/mr2/args" && grep -q 'install\|-S' "$tmp/mr2/args" \
  && grep -q 'https://old/' "$tmp/mr2/etc/mirrorlist" && ok "a missing reflector is installed with the package manager" \
  || bad "reflector was not fetched"

# ---- rice-care: Snap is checked, AUR is shown only, and the update keeps AUR out
mkdir -p "$tmp/care/bin" "$tmp/care/home/.local/bin" "$tmp/care/home/.config/rice"
cat >"$tmp/care/bin/checkupdates" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' 'foo 1.0-1 -> 1.1-1'
EOS
cat >"$tmp/care/bin/paru" <<'EOS'
#!/usr/bin/env bash
[ "${1:-}" = "-Qua" ] && printf '%s\n' 'aurpkg 1.0-1 -> 2.0-1'
exit 0
EOS
cat >"$tmp/care/bin/pacman" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
cat >"$tmp/care/bin/flatpak" <<'EOS'
#!/usr/bin/env bash
[ "${1:-}" = "remote-ls" ] && printf '%s\n' 'org.example.App 2.0'
exit 0
EOS
cat >"$tmp/care/bin/snap" <<'EOS'
#!/usr/bin/env bash
[ "${1:-}" = "refresh" ] && { printf '%s\n' 'Name  Version  Rev  Size  Publisher  Notes'; printf '%s\n' 'firefox  120.0  456  100MB  mozilla  -'; }
exit 0
EOS
chmod +x "$tmp/care/bin/"*
cat >"$tmp/care/home/.local/bin/rice-term" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do [ -f "$a" ] && cp "$a" "$CARECMD"; done
EOS
chmod +x "$tmp/care/home/.local/bin/rice-term"
HOME="$tmp/care/home" PATH="$tmp/care/bin:$PATH" "$root/bin/rice-care" updates --fresh >"$tmp/care/up.json"
python3 - "$tmp/care/up.json" <<'PYC' && ok "Arch, Flatpak and Snap are checked; AUR is shown but not counted as updateable" \
  || bad "rice-care updates lost a manager or counted AUR as updateable"
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["id"]: x for x in d["managers"]}
assert m["pacman"]["count"] == 1, m
assert m["aur"]["count"] == 1 and m["aur"].get("manual") is True, m["aur"]
assert d["updateable"] == 3 and d["total"] == 4, d
PYC
HOME="$tmp/care/home" PATH="$tmp/care/bin:$PATH" CARECMD="$tmp/care/run.sh" "$root/bin/rice-care" update >/dev/null 2>&1
i=0; while [ ! -f "$tmp/care/run.sh" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
[ -f "$tmp/care/run.sh" ] && ok "the package update opens in a terminal" || bad "rice-care update made no terminal command"
grep -q 'rice-mirrors' "$tmp/care/run.sh" && ok "the mirrors are picked before a package update" || bad "no reflector before the packages"
grep -q 'pacman -Syu' "$tmp/care/run.sh" && ok "the repositories update with pacman" || bad "pacman -Syu is gone"
grep -qE '(paru|yay) -Syu' "$tmp/care/run.sh" && bad "the package update still upgrades the whole AUR" || ok "the AUR is left alone"
grep -q 'flatpak update -y' "$tmp/care/run.sh" && grep -q 'snap refresh' "$tmp/care/run.sh" \
  && ok "Flatpak and Snap apps update too" || bad "Flatpak or Snap is missing from the update"
python3 - "$tmp/care/run.sh" <<'PYC' && ok "rice-mirrors runs before pacman in the terminal" || bad "order changed: pacman before the mirrors"
import sys
s = open(sys.argv[1]).read()
assert 0 <= s.find("rice-mirrors") < s.find("pacman -Syu")
PYC

# ---- rice-update update: AUR alone does not move the shell update to a terminal
mkdir -p "$tmp/upd/home/.local/bin"
cat >"$tmp/upd/home/.local/bin/rice-care" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$UPDATES_JSON"
EOS
chmod +x "$tmp/upd/home/.local/bin/rice-care"
HOME="$tmp/upd/home" python3 - "$root/bin/rice-update" <<'PYC' && ok "rice-update update: AUR is not a reason for a terminal, packages are" \
  || bad "rice-update update counts AUR as updateable"
import importlib.machinery, importlib.util, os, sys
os.environ["UPDATES_JSON"] = '{"updateable":0,"managers":[{"id":"aur","count":5,"manual":true}]}'
loader = importlib.machinery.SourceFileLoader("ru", sys.argv[1])
spec = importlib.util.spec_from_loader("ru", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
assert m.packages_pending() == 0, m.packages_pending()
os.environ["UPDATES_JSON"] = '{"updateable":2,"managers":[{"id":"pacman","count":2}]}'
assert m.packages_pending() == 2
os.environ["UPDATES_JSON"] = '{"managers":[{"id":"pacman","count":3},{"id":"aur","count":5,"manual":true}]}'
assert m.packages_pending() == 3
PYC

# ---- the other supported distros: Update Center checks and updates what that distro has
mkdir -p "$tmp/dis"
cat >"$tmp/dis/rice-term" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do [ -f "$a" ] && cp "$a" "$CARECMD"; done
EOS
make_stub() { # make_stub DIR NAME BODY
  mkdir -p "$1/bin"; printf '#!/usr/bin/env bash\n%s\n' "$3" >"$1/bin/$2"; chmod +x "$1/bin/$2"
}
for name in dnf apt zypper xbps-install emerge; do
  mkdir -p "$tmp/dis/$name/home/.local/bin" "$tmp/dis/$name/bin"
  cp "$tmp/dis/rice-term" "$tmp/dis/$name/home/.local/bin/rice-term"
  chmod +x "$tmp/dis/$name/home/.local/bin/rice-term"
done
make_stub "$tmp/dis/dnf" dnf 'printf "%s\n" "vim-enhanced.x86_64  2:9.1-1.fc41  updates"'
make_stub "$tmp/dis/apt" apt 'printf "%s\n" "Listing..." "vim/jammy-updates 9.1 amd64 [upgradable from: 9.0]"'
make_stub "$tmp/dis/zypper" zypper 'printf "%s\n" "S | Name | Current | Available | Arch" "--+------+---------+-----------+-----" "v | vim  | 9.0     | 9.1       | x86_64"'
make_stub "$tmp/dis/xbps-install" xbps-install 'printf "%s\n" "vim-9.0_1 update 9.1_1"'
make_stub "$tmp/dis/emerge" emerge 'printf "%s\n" "[ebuild  U  ] app-editors/vim-9.1 [9.0]"'
for spec in "dnf:dnf:Fedora packages:dnf upgrade --refresh" "apt:apt:Debian / Ubuntu packages:apt update && sudo apt upgrade" \
            "zypper:zypper:openSUSE packages:zypper dup" "xbps-install:xbps:Void packages:xbps-install -Su" \
            "emerge:portage:Gentoo packages:emerge -uDN @world"; do
  IFS=: read -r name id human cmd <<<"$spec"
  d="$tmp/dis/$name"
  HOME="$d/home" PATH="$d/bin:$PATH" "$root/bin/rice-care" updates --fresh >"$d/up.json" 2>/dev/null
  python3 - "$d/up.json" "$id" <<'PYC' && ok "$name: the Update Center sees its packages" || bad "$name: nothing checked, or a wrong count"
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["id"]: x for x in d["managers"]}
assert m[sys.argv[2]]["count"] == 1 and d["updateable"] == 1, d
PYC
  HOME="$d/home" PATH="$d/bin:$PATH" CARECMD="$d/run.sh" "$root/bin/rice-care" update >/dev/null 2>&1
  i=0; while [ ! -f "$d/run.sh" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$d/run.sh" ] && grep -qF "$cmd" "$d/run.sh" && ok "$name: the update runs its own package manager" \
    || bad "$name: the update does not run: $cmd"
  grep -q 'pacman -Syu' "$d/run.sh" 2>/dev/null && bad "$name: an Arch update ran on another distro" \
    || ok "$name: no pacman on another distro"
done
grep -q 'emaint sync -a' "$tmp/dis/emerge/run.sh" && ok "Gentoo: the repos are synced before @world" \
  || bad "Gentoo: emerge runs without a sync"

# ---- NixOS and the atomic Fedoras: shown, not updated from here (their own command does it)
mkdir -p "$tmp/dis/nixos/home/.local/bin" "$tmp/dis/nixos/bin"
cp "$tmp/dis/rice-term" "$tmp/dis/nixos/home/.local/bin/rice-term"; chmod +x "$tmp/dis/nixos/home/.local/bin/rice-term"
make_stub "$tmp/dis/nixos" nixos-rebuild 'exit 0'
HOME="$tmp/dis/nixos/home" PATH="$tmp/dis/nixos/bin:$PATH" "$root/bin/rice-care" updates --fresh >"$tmp/dis/nixos/up.json" 2>/dev/null
python3 - "$tmp/dis/nixos/up.json" <<'PYC' && ok "NixOS: shown with its own update command, and not counted as updateable" \
  || bad "NixOS: no manager, or it was counted as updateable"
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["id"]: x for x in d["managers"]}
assert m["nixos"].get("manual") is True and d["updateable"] == 0 and "nixos-rebuild switch --upgrade" in m["nixos"]["note"], d
PYC
HOME="$tmp/dis/nixos/home" PATH="$tmp/dis/nixos/bin:$PATH" CARECMD="$tmp/dis/nixos/run.sh" \
  "$root/bin/rice-care" update >"$tmp/dis/nixos/out.txt" 2>/dev/null
i=0; while [ ! -f "$tmp/dis/nixos/run.sh" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
if [ -f "$tmp/dis/nixos/run.sh" ]; then
  ! grep -q 'nixos-rebuild' "$tmp/dis/nixos/run.sh" && ok "NixOS: no rebuild runs on its own" \
    || bad "NixOS: a system rebuild was started on its own"
else
  grep -q 'nixos-rebuild switch --upgrade' "$tmp/dis/nixos/out.txt" && ok "NixOS: a package update says how the system updates" \
    || bad "NixOS: rice-care update failed silently"
fi

mkdir -p "$tmp/dis/ostree/home/.local/bin" "$tmp/dis/ostree/bin"
cp "$tmp/dis/rice-term" "$tmp/dis/ostree/home/.local/bin/rice-term"; chmod +x "$tmp/dis/ostree/home/.local/bin/rice-term"
make_stub "$tmp/dis/ostree" rpm-ostree 'exit 0'
make_stub "$tmp/dis/ostree" dnf 'printf called >"$DNF_CALLED"; exit 1'
HOME="$tmp/dis/ostree/home" PATH="$tmp/dis/ostree/bin:$PATH" DNF_CALLED="$tmp/dis/ostree/dnf" \
  "$root/bin/rice-care" updates --fresh >"$tmp/dis/ostree/up.json" 2>/dev/null
python3 - "$tmp/dis/ostree/up.json" <<'PYC' && ok "Fedora Atomic: rpm-ostree is shown instead of dnf, and not counted" \
  || bad "Fedora Atomic: dnf was used, or the image update is missing"
import json, sys
d = json.load(open(sys.argv[1]))
m = {x["id"]: x for x in d["managers"]}
assert m["ostree"].get("manual") is True and d["updateable"] == 0, d
PYC
[ -f "$tmp/dis/ostree/dnf" ] && bad "Fedora Atomic: dnf was checked on an image system" || ok "Fedora Atomic: dnf is not asked"

# ---- install.sh: the mirrors come first, and an update takes the app stores with it
python3 - "$root/install.sh" <<'PYC' && ok "install.sh picks the mirrors before pacman and updates Flatpak and Snap on an update" \
  || bad "install.sh lost the mirror step or the app stores"
import sys
s = open(sys.argv[1]).read()
assert 0 <= s.find("rice-mirrors") < s.find("sudo pacman -Syu --noconfirm"), "mirrors not before pacman"
assert 'live "Snap apps" sudo snap refresh' in s and "update_app_stores" in s, "snap or app stores missing"
assert '[ "$MODE" = update ] && update_app_stores' in s, "app stores not tied to an update"
PYC


# ---- rice-apps-helper: opening an archive does not write outside the folder it is opened in
python3 - "$root/bin/rice-apps-helper" "$tmp/evil.tar" "$tmp/good.tar" "$tmp/evil.zip" <<'PYA' && ok "an archive member with .. is refused" || bad "rice-apps-helper would unpack .."
import importlib.machinery, importlib.util, sys, zipfile
loader = importlib.machinery.SourceFileLoader("ah", sys.argv[1])
spec = importlib.util.spec_from_loader("ah", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
assert m.safe_names(sys.argv[2]) is False, "accepted ../ in tar"
assert m.safe_names(sys.argv[3]) is True, "refused a plain archive"
with zipfile.ZipFile(sys.argv[4], "w") as z:
    z.writestr("../escaped", "x")
assert m.safe_names(sys.argv[4]) is False, "accepted ../ in zip"
PYA

# ---- hypr-set: a command with an accent reaches the Lua config as UTF-8, not as an escape Lua cannot read
mkdir -p "$tmp/hs/home/.config/hypr" "$tmp/hs/bin"
printf '#!/usr/bin/env bash\necho ok\n' >"$tmp/hs/bin/hyprctl"
chmod +x "$tmp/hs/bin/hyprctl"
HOME="$tmp/hs/home" PATH="$tmp/hs/bin:$PATH" NIRI_SOCKET= HYPRLAND_INSTANCE_SIGNATURE= XDG_CURRENT_DESKTOP= \
  python3 "$root/bin/hypr-set" bind-add "SUPER + X" "notify-send café" >/dev/null 2>&1
hs="$tmp/hs/home/.config/hypr/rice-settings.lua"
grep -q 'café' "$hs" && ok "a bind command keeps its accent" || bad "the accent was escaped or lost"
grep -q '\\u00e9' "$hs" && bad "the Lua file has a \u escape" || ok "no \u escape in the Lua file"

# ---- V6.84: the launcher's shape is the dock's (Edit mode > Icons, then the dock's own, then pills)
grep -q 'dockCfg.style === "pills" ? "squircle"' "$root/quickshell/rice-desktop/Launcher.qml" \
  && ok "the launcher takes the same icon shape as the dock" || bad "the launcher ignores the dock's shape"
grep -q 'shape: ln.iShape$' "$root/quickshell/rice-desktop/LauncherM3.qml" \
  && ok "the frequent apps do not force a shape of their own" || bad "the frequent apps still force a cookie"

# ---- V6.84: a scheme you picked (grey) is not repainted by the cover of a song
grep -q 'wantTint && colorMode === "auto"' "$root/quickshell/rice-desktop/Vibe.qml" \
  && ok "the cover's colors belong to Auto only" || bad "a song overrides the picked scheme"
grep -q 'setAutoSource' "$root/quickshell/rice-settings/ThemePage.qml" \
  && ok "Auto offers the wallpaper or the cover" || bad "Auto has no source to choose"

# ---- V6.84: an update stops the shell for the swap, so it never reloads half old and half new files
grep -q 'Stopping the desktop shell for the file swap' "$root/install.sh" && grep -q 'Starting the desktop shell again' "$root/install.sh" \
  && ok "an update stops the shell for the file swap and starts it again" \
  || bad "the shell reloads between two swaps during an update"

# ---- V6.84: the wallpaper you picked is what an update keeps
grep -q 'HOME/.config/rice/wallpaper' "$root/install.sh" && grep -q 'head -n1 "$HOME/.config/rice/wallpaper"' "$root/install.sh" \
  && ok "an update puts the remembered wallpaper back, not a random one" \
  || bad "an update can still pick a random wallpaper"
grep -q '\[ "$dir/$name" = "$cur" \] && continue' "$root/install.sh" \
  && ok "an update never deletes the wallpaper on the screen" || bad "a retired wallpaper can be deleted while it is shown"

# ---- V6.84: a live wallpaper keeps playing when the color scheme changes
mkdir -p "$tmp/lw/home/.cache/rice" "$tmp/lw/home/.config/quickshell/hyprquickpaper" "$tmp/lw/home/.local/bin" "$tmp/lw/home/.config/rice"
mkdir -p "$tmp/lw/videos"; : >"$tmp/lw/videos/sea.mp4"
printf '%s/videos/sea.mp4\n' "$tmp/lw" >"$tmp/lw/home/.cache/rice/live-wallpaper"
printf '%s/videos/sea.mp4\n' "$tmp/lw" >"$tmp/lw/home/.cache/hyprquickpaper-current"
touch "$tmp/lw/still.jpg"
printf '#!/usr/bin/env bash\n[ "$1" = still ] && echo "%s"\n' "$tmp/lw/still.jpg" >"$tmp/lw/home/.local/bin/rice-walls"
cat >"$tmp/lw/home/.config/quickshell/hyprquickpaper/commands.sh" <<'EOS'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$RICE_LIVE" "$RICE_COLORS_ONLY" "$RICE_CURRENT" "$1" >"$HOME/colors-ran"
EOS
chmod +x "$tmp/lw/home/.local/bin/rice-walls" "$tmp/lw/home/.config/quickshell/hyprquickpaper/commands.sh"
HOME="$tmp/lw/home" PATH="$tmp/lw/home/.local/bin:$PATH" python3 "$root/bin/rice-colors" mode grey >/dev/null 2>&1
[ -f "$tmp/lw/home/.cache/rice/live-wallpaper" ] && ok "a color change keeps the live wallpaper playing" \
  || bad "a color change stopped the live wallpaper"
grep -q "^1|1|$tmp/lw/videos/sea.mp4|$tmp/lw/still.jpg$" "$tmp/lw/home/colors-ran" 2>/dev/null \
  && ok "the colors come from the frame, and the wallpaper is left alone" \
  || bad "the color change did not keep the live wallpaper: $(cat "$tmp/lw/home/colors-ran" 2>/dev/null)"
[ "$(cat "$tmp/lw/home/.cache/hyprquickpaper-current")" = "$tmp/lw/videos/sea.mp4" ] \
  && ok "the video stays the current wallpaper" || bad "the still frame replaced the video"

# ---- a picture changes as it always did
mkdir -p "$tmp/pic/home/.cache" "$tmp/pic/home/.config/quickshell/hyprquickpaper" "$tmp/pic/home/.config/rice"
printf '%s/pic.jpg\n' "$tmp/pic" >"$tmp/pic/home/.cache/hyprquickpaper-current"
touch "$tmp/pic/pic.jpg"
cp "$tmp/lw/home/.config/quickshell/hyprquickpaper/commands.sh" "$tmp/pic/home/.config/quickshell/hyprquickpaper/commands.sh"
chmod +x "$tmp/pic/home/.config/quickshell/hyprquickpaper/commands.sh"
HOME="$tmp/pic/home" python3 "$root/bin/rice-colors" mode grey >/dev/null 2>&1
grep -q "^|||$tmp/pic/pic.jpg$" "$tmp/pic/home/colors-ran" 2>/dev/null \
  && ok "a picture is applied the plain way" || bad "the picture path changed: $(cat "$tmp/pic/home/colors-ran" 2>/dev/null)"

# ---- rice-walls gives the still frame the colors are made from
python3 - "$root/bin/rice-walls" "$tmp/still-check.jpg" <<'PYW' && ok "rice-walls gives the still frame of a live wallpaper" || bad "rice-walls has no still frame"
import importlib.machinery, importlib.util, os, sys
ldr = importlib.machinery.SourceFileLoader("rw", sys.argv[1])
spec = importlib.util.spec_from_loader("rw", ldr); m = importlib.util.module_from_spec(spec)
import types; m.__dict__["__name__"] = "rw"; spec.loader.exec_module(m)
m.LIVE_DIR = sys.argv[2] + "-live"; os.makedirs(m.LIVE_DIR, exist_ok=True)
open(sys.argv[2], "w").write("x")
open(m.LIVE_DIR + "/" + m.key("/videos/sea.mp4") + ".jpg", "w").write("x")
assert m.cmd_still("/videos/sea.mp4") == 0
PYW

bash -n "$root/install.sh" && ok "install.sh parses" || bad "install.sh syntax"
echo "# $n checks passed"
