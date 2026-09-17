#!/usr/bin/env bash
# Packs the mod for Nexus: every file committed to git, minus whatever .nexusignore
# matches (same syntax as .gitignore). Files end up at the archive root.
#
#   bash tools/build_nexus_zip.sh [output.zip]    (default: nexus-upload.zip)
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-nexus-upload.zip}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
rm -f "$out"

files=$(comm -23 \
    <(git -c core.quotePath=false ls-files | sort) \
    <(git -c core.quotePath=false ls-files --cached --ignored --exclude-from=.nexusignore | sort))

if [ -z "$files" ]; then
    echo "Nothing to pack - check .nexusignore" >&2
    exit 1
fi

printf '%s\n' "$files" | zip -q -X "$out" -@
echo "Packed $(printf '%s\n' "$files" | wc -l) files into $out"
