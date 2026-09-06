#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=seed-runtime.sh
source "$SCRIPT_DIR/seed-runtime.sh"
# shellcheck source=seed-fixtures.sh
source "$SCRIPT_DIR/seed-fixtures.sh"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     Streamline Demo Data Seeder              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

wait_for_server
seed_topics

echo "🌱 Seeding sample data..."
echo ""
seed_all_fixtures

echo ""
echo "══════════════════════════════════════════════"
echo "✅ Seeding complete!"
echo ""
echo "  Topics created:  ${#TOPICS[@]}"
echo "  Messages seeded: ${TOTAL_MESSAGES}"
echo ""
echo "  Topics:"
for t in "${TOPICS[@]}"; do
  echo "    • ${t}"
done
echo ""
echo "  Try consuming:"
echo "    streamline-cli --broker localhost:9092 consume demo-events --from-beginning -n 5"
echo "══════════════════════════════════════════════"
echo ""
