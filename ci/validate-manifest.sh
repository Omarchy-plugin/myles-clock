#!/bin/bash
# Validate this plugin folder against the manifest schema the Omarchy shell
# enforces.
#
# This is a portable port of omarchy's own `omarchy plugin validate`, which is
# not installable on a stock CI runner. It mirrors that script's checks exactly
# so CI and `omarchy plugin validate` agree:
#
#   https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-plugin-validate
#
# If omarchy changes its rules, re-sync this file. The authoritative list is the
# registry the shell actually uses: shell/services/PluginRegistry.qml.
#
# Usage: ci/validate-manifest.sh [plugin-dir]     (default: the repo root)
#
# Exits 0 if valid, 1 with a reason otherwise.

set -o pipefail

PLUGIN_DIR="${1:-.}"
fail() {
  echo "validate-manifest: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"

[[ -n $PLUGIN_DIR && -d $PLUGIN_DIR ]] || fail "plugin folder not found: ${PLUGIN_DIR:-<none>}"

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f $MANIFEST ]] || fail "missing manifest.json in $PLUGIN_DIR"

# jq -e exits non-zero on false/null as well as on a parse error, so this covers
# "is valid JSON" and "is not literally null" together.
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON: $MANIFEST"

# schemaVersion must be the JSON number 1. jq's == is type-aware, so the string
# "1" is rejected here just as the QML `schemaVersion !== 1` check rejects it.
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 \
  || fail "unsupported or missing schemaVersion (expected 1) in $MANIFEST"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

ID=$(jq -r '.id // ""' "$MANIFEST")
[[ -n $ID ]] || fail "manifest 'id' is empty"
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$ID'"
[[ $ID != *".."* ]] || fail "invalid plugin id '$ID'"
[[ $ID != omarchy.* ]] || fail "plugin id '$ID' uses the reserved omarchy.* namespace"

# A plugin published by this organisation must stay inside the namespace the
# auto-updater scans. Anything else installs but never self-updates.
if [[ $ID != myles.* ]] && [[ ${REQUIRE_MYLES_NAMESPACE:-0} == 1 ]]; then
  fail "plugin id '$ID' is outside the myles.* namespace the updater scans"
fi

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'kinds' must be a non-empty array"

jq -e '(.entryPoints | type) == "object"' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'entryPoints' must be an object"

# A bar widget may declare where it should land without an explicit placement.
jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $section
    | ($section | type) == "string"
      and (["left", "center", "right"] | index($section)) != null
  else
    true
  end
' "$MANIFEST" >/dev/null 2>&1 \
  || fail "'barWidget.defaultSection' must be left, center, or right"

# Read each entry point as one JSON-encoded string per line, then decode it, so a
# value containing a newline stays a single literal path instead of being split
# into fragments that each pass the checks.
while IFS= read -r ep_json; do
  [[ -n $ep_json ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  [[ -n $ep ]] || fail "entry point path is empty"
  [[ $ep != *$'\n'* ]] || fail "entry point may not contain a newline"
  [[ $ep != /* ]] || fail "entry point must be a relative path: '$ep'"
  [[ $ep != *".."* ]] || fail "entry point may not contain '..': '$ep'"
  [[ -f "$PLUGIN_DIR/$ep" ]] || fail "entry point file not found: '$ep'"
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

# A kind is a promise to supply something to load, and the shell looks for it
# under a fixed key. Claiming a kind without its entry point produces a plugin
# that installs, enables, and does nothing.
while IFS=: read -r kind entry_point; do
  jq -e --arg kind "$kind" '(.kinds | index($kind)) != null' "$MANIFEST" >/dev/null 2>&1 || continue
  jq -e --arg ep "$entry_point" '.entryPoints | has($ep)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "kind '$kind' requires an 'entryPoints.$entry_point' to load"
done <<'KINDS'
bar:bar
bar-widget:barWidget
menu:menu
overlay:overlay
panel:panel
service:service
KINDS

# Refuse any symlink inside the plugin folder: one could point an installed
# plugin back at arbitrary files on disk. .git is skipped because installed
# plugins are git checkouts and the shell never loads git's internals.
link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

# Guard the licence notice: anything forked from an Omarchy built-in must keep
# the upstream copyright, because omarchy is MIT (c) David Heinemeier Hansson
# and MIT requires the notice to survive in copies.
if [[ -f $PLUGIN_DIR/omarchy.clonedFrom ]] || jq -e '.omarchy.clonedFrom' "$MANIFEST" >/dev/null 2>&1; then
  [[ -f $PLUGIN_DIR/LICENSE ]] || fail "a fork of an Omarchy plugin must ship a LICENSE"
  grep -q 'David Heinemeier Hansson' "$PLUGIN_DIR/LICENSE" \
    || fail "LICENSE is missing the upstream Omarchy copyright (David Heinemeier Hansson), which MIT requires"
fi

echo "validate-manifest: $ID is valid"
