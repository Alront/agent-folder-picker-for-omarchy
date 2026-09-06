#!/bin/bash

# Quoted tildes intentionally exercise the plugin's literal path interface.
# shellcheck disable=SC2088
set -euo pipefail

root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

home=$tmp/home
state=$tmp/state
capture=$tmp/launch-arguments
mkdir -p "$home/Alpha" "$home/Beta" "$home/Charlie" "$home/Delta" \
  "$home/Echo" "$home/Foxtrot" "$home/Space Project" "$tmp/bin"

result=$(HOME="$home" "$root/scripts/list-folders" "~/Al")
[[ $result == "$home/Alpha" ]]

result=$(HOME="$home" "$root/scripts/list-folders" "~/Space")
[[ $result == "$home/Space Project" ]]

count=$(HOME="$home" "$root/scripts/list-folders" "~/" | wc -l)
((count == 5))

cat >"$tmp/bin/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$@" >"$CAPTURE"
SCRIPT
cat >"$tmp/bin/omarchy-notification-send" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
chmod +x "$tmp/bin/setsid" "$tmp/bin/omarchy-notification-send"

HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Alpha"

history_file=$state/omarchy/agent-folder-picker/paths
[[ $(<"$history_file") == "$home/Alpha" ]]

expected=(
  "uwsm-app"
  "--"
  "xdg-terminal-exec"
  "--dir=$home/Alpha"
  "--app-id=org.omarchy.agent"
  "-e"
  "omarchy-agent"
  "--inline"
  "--pick"
)
mapfile -t args <"$capture"
(( ${#args[@]} == ${#expected[@]} ))
for index in "${!expected[@]}"; do
  [[ ${args[index]} == "${expected[index]}" ]]
done

HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Beta"
HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Alpha"

mapfile -t history <"$history_file"
(( ${#history[@]} == 2 ))
[[ ${history[0]} == "$home/Alpha" ]]
[[ ${history[1]} == "$home/Beta" ]]

for index in {1..35}; do
  printf '/example/project-%02d\n' "$index"
done >"$history_file"
HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Alpha"
(( $(wc -l <"$history_file") == 30 ))
IFS= read -r first_history_path <"$history_file"
[[ $first_history_path == "$home/Alpha" ]]

HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~"
mapfile -t args <"$capture"
[[ ${args[6]} == "env" ]]
[[ ${args[7]} == "PWD=$home/." ]]
[[ ${args[8]} == "omarchy-agent" ]]

HOME="$home" XDG_STATE_HOME="/proc/unwritable-state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Alpha" 2>/dev/null
mapfile -t args <"$capture"
[[ ${args[3]} == "--dir=$home/Alpha" ]]

if HOME="$home" XDG_STATE_HOME="$state" CAPTURE="$capture" \
  PATH="$tmp/bin:$PATH" "$root/scripts/launch-agent" "~/Missing"; then
  printf 'Expected a missing folder to fail.\n' >&2
  exit 1
fi

printf 'All script tests passed.\n'
