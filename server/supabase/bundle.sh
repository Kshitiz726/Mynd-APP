#!/usr/bin/env bash
# Print every migration, in order, as one script.
#
# For standing a fresh database up from nothing: paste the output into the
# Supabase SQL editor, or pipe it to psql. Generated rather than committed as
# a second copy, because a hand-maintained "full schema" file drifts from the
# migrations it is supposed to equal and you find out when a restore fails.
#
# Order is the same one the files already encode: the 000N series first in
# numeric order, then the timestamped ones in date order. Both sort correctly
# as plain strings, which is why the names are shaped like that.
set -euo pipefail
cd "$(dirname "$0")/migrations"

echo "-- OurMynd schema: $(ls -1 *.sql | wc -l | tr -d ' ') migrations, generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "-- Every statement is create-if-not-exists or add-column-if-not-exists,"
echo "-- so this is safe to run twice."
echo "begin;"
for f in $(ls -1 *.sql | sort); do
  echo ""
  echo "-- ─── $f ───────────────────────────────────────────────────────────"
  cat "$f"
done
echo ""
echo "commit;"
