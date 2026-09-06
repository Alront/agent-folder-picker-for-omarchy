#!/bin/bash

set -euo pipefail

manifest=${1:-manifest.json}

jq -e '
  .schemaVersion == 1
  and (.id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and (contains("..") | not) and (startswith("omarchy.") | not))
  and (.name | type == "string" and length > 0)
  and (.version | type == "string" and length > 0 and length <= 64)
  and (.author | type == "string" and length > 0)
  and (.description | type == "string" and length > 0)
  and (.license == "MIT")
  and (.kinds == ["overlay"])
  and (.entryPoints.overlay | type == "string" and length > 0)
' "$manifest" >/dev/null

entry_point=$(jq -r '.entryPoints.overlay' "$manifest")
[[ $entry_point != /* && $entry_point != *..* && -f $entry_point ]]

link=$(find . -path ./.git -prune -o -type l -print -quit)
[[ -z $link ]]

printf 'Manifest validation passed.\n'
