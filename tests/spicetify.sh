#!/usr/bin/env bash
# rice-spicetify for people without Spotify or spicetify: a fake spicetify in PATH writes down every command,
# the palette is a fixed one, and the Python behind rice-theme is not supposed to move.
set -Euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

export HOME="$T/home"; mkdir -p "$HOME/.config/rice" "$T/bin"
export XDG_CONFIG_HOME="$T/home/.config"
cat >"$HOME/.config/rice/palette.json" <<'J'
{"surface": "#101010", "surface_low": "#0A0A0A", "surface_container": "#202020",
 "surface_high": "#303030", "surface_highest": "#404040", "on_surface": "#E0E0E0",
 "on_surface_variant": "#C0C0C0", "outline": "#909090", "outline_variant": "#505050",
 "primary": "#123456", "error": "#FF0000"}
J
cat >"$T/bin/spicetify" <<'S'
#!/usr/bin/env bash
echo "$*" >>"$SPICE_LOG"
S
chmod +x "$T/bin/spicetify"
export SPICE_LOG="$T/calls"

R="$ROOT/bin/rice-spicetify"

# 1. no spicetify anywhere: says where to get it, and the theme is written anyway? (no: nothing to write into)
PATH="/usr/bin:/bin" bash "$R" theme >/dev/null 2>"$T/err" && fail "theme without spicetify should fail"
grep -q "spicetify is not in PATH" "$T/err" || fail "no message about spicetify"
pass "no spicetify: message, non-zero exit"

# 2. colors: only color.ini + user.css, no spicetify needed, colors from the palette
PATH="$T/bin:$(dirname "$(command -v python3)"):/usr/bin:/bin" bash "$R" colors || fail "colors failed"
INI="$XDG_CONFIG_HOME/spicetify/Themes/darkshadow/color.ini"
[ -f "$INI" ] || fail "no color.ini"
[ -f "$XDG_CONFIG_HOME/spicetify/Themes/darkshadow/user.css" ] || fail "no user.css"
grep -q '^\[darkshadow\]$' "$INI" || fail "no [darkshadow] section"
grep -q '^text *= *e0e0e0$' "$INI" || fail "text is not on_surface"
grep -q '^main *= *202020$' "$INI" || fail "main is not surface_container"
grep -q '^button *= *123456$' "$INI" || fail "button is not primary"
grep -q '^notification-error *= *ff0000$' "$INI" || fail "notification-error is not error"
grep -q '^shadow *= *0a0a0a$' "$INI" || fail "shadow is not surface_low"
! grep -q '^#' "$INI" || fail "color.ini has # (Spicetify wants plain hex)"
[ "$(grep -c '^[a-z-]* *=' "$INI")" = 17 ] || fail "not 17 keys: $(grep -c '^[a-z-]* *=' "$INI")"
[ -s "$SPICE_LOG" ] && fail "colors should not call spicetify"
pass "colors: 17 keys from palette, no spicetify call"

# 3. no palette at all: the DarkShadow defaults, still 6 hex digits
mv "$HOME/.config/rice/palette.json" "$T/pal.json"
PG="$(PATH="$T/bin:$(dirname "$(command -v python3)"):/usr/bin:/bin" bash "$R" colors; cat "$INI")"
echo "$PG" | grep -q '^main *= *211f24$' || fail "fallback main is not the default"
pass "no palette: defaults"

# 4. theme: config + apply, in that order, and the scheme name matches the section
mv "$T/pal.json" "$HOME/.config/rice/palette.json"
: >"$SPICE_LOG"
PATH="$T/bin:$(dirname "$(command -v python3)"):/usr/bin:/bin" bash "$R" theme || fail "theme failed"
want="config current_theme darkshadow
config color_scheme darkshadow
config inject_css 1
config replace_colors 1
config overwrite_assets 1
apply"
[ "$(cat "$SPICE_LOG")" = "$want" ] || fail "calls: $(cat "$SPICE_LOG")"
pass "theme: config then apply"

# 5. state: JSON that parses, flags follow the config file and PATH
mkdir -p "$XDG_CONFIG_HOME/spicetify"
printf '[Setting]\ncurrent_theme = darkshadow\n' >"$XDG_CONFIG_HOME/spicetify/config-xpui.ini"
s="$(PATH="$T/bin:$(dirname "$(command -v python3)"):/usr/bin:/bin" bash "$R" state)"
echo "$s" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["spicetify"]==1 and d["themed"]==1, d' || fail "state: $s"
pass "state: spicetify 1, themed 1"
rm "$XDG_CONFIG_HOME/spicetify/config-xpui.ini"
s="$(PATH="$T/bin:$(dirname "$(command -v python3)"):/usr/bin:/bin" bash "$R" state)"
echo "$s" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["themed"]==0, d' || fail "state unthemed: $s"
pass "state: unthemed 0"

# 6. usage: exit 2, mentions theme and colors
rc=0; bash "$R" >"$T/out" 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "usage should exit 2, got $rc"
grep -q "rice-spicetify theme" "$T/out" || fail "usage text"
grep -q "set -Euo" "$T/out" && fail "usage shows the code"
pass "usage: exit 2"

echo "all 6 checks passed"