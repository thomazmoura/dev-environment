#!/usr/bin/env bash
# Prints where and how it ran -- the shape a library script takes.
#
# This line and the ones below it are ignored by the picker: only the first
# comment line above becomes the description in the list. Delete this file once
# you have scripts of your own; nothing refers to it.
set -euo pipefail

printf 'Show-Example.sh\n\n'
printf '  interpreter  %s\n' "$(bash --version | head -1)"
printf '  directory    %s\n' "$PWD"
printf '  host         %s\n' "$(hostname)"
