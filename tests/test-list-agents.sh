#!/bin/bash

set -euo pipefail

root=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/home/.local/bin" "$tmp/bin"
cat >"$tmp/bin/omarchy" <<'SCRIPT'
#!/bin/bash
printf '%s\n' '  omarchy default agent [opencode|claude|codex|pi|openclaw|hermes]'
SCRIPT
cat >"$tmp/bin/mise" <<'SCRIPT'
#!/bin/bash
[[ $1 == where ]] || exit 1
case $2 in
  opencode|claude|codex) exit 0 ;;
  *) exit 1 ;;
esac
SCRIPT
cat >"$tmp/bin/omarchy-install-openclaw-cli" <<'SCRIPT'
#!/bin/bash
[[ ${1-} == --check ]]
SCRIPT
cat >"$tmp/home/.local/bin/pi" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
chmod +x "$tmp/bin/omarchy" "$tmp/bin/mise" "$tmp/bin/omarchy-install-openclaw-cli" "$tmp/home/.local/bin/pi"

agents=$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" "$root/scripts/list-agents")
expected=$'opencode\nclaude\ncodex\npi\nopenclaw'
[[ $agents == "$expected" ]]

printf 'Installed-agent discovery tests passed.\n'
