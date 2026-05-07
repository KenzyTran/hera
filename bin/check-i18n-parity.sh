#!/usr/bin/env bash
# bin/check-i18n-parity.sh - Phase 5 DOC-12 parity gate (D-50).
# Asserts content/vi and content/en have matching _index.md file structure.
# Read-only; never writes. Zero AWS calls.
#
# Usage:  bash bin/check-i18n-parity.sh
# Reads:  content/vi/**/_index.md, content/en/**/_index.md
# Effect: prints OK/FAIL per assertion + final tally; exit 0 on parity, exit 1 on mismatch.

set -euo pipefail

# --- preflight: required tools ---
command -v find >/dev/null 2>&1 || { echo "ERROR: find not found on PATH" >&2; exit 2; }
command -v sort >/dev/null 2>&1 || { echo "ERROR: sort not found on PATH" >&2; exit 2; }
command -v diff >/dev/null 2>&1 || { echo "ERROR: diff not found on PATH" >&2; exit 2; }

# --- repo root anchor: lets the script run from any CWD ---
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

PASS_COUNT=0
FAIL_COUNT=0

echo "check-i18n-parity against content/vi vs content/en"
echo "----------------------------------------"

# --- Check 1: file count parity ---
VI_COUNT=$(find content/vi -name "_index.md" -type f | wc -l | tr -d ' ')
EN_COUNT=$(find content/en -name "_index.md" -type f | wc -l | tr -d ' ')
if [[ "${VI_COUNT}" -eq "${EN_COUNT}" ]]; then
  echo "OK: file count parity (vi=${VI_COUNT}, en=${EN_COUNT})"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: file count mismatch (vi=${VI_COUNT}, en=${EN_COUNT})"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- Check 2: bidirectional slug-tree parity ---
VI_SLUGS=$(find content/vi -name "_index.md" -type f | sed 's|^content/vi/||' | sort)
EN_SLUGS=$(find content/en -name "_index.md" -type f | sed 's|^content/en/||' | sort)
DIFF_OUT=$(diff <(echo "${VI_SLUGS}") <(echo "${EN_SLUGS}") || true)
if [[ -z "${DIFF_OUT}" ]]; then
  echo "OK: vi/en slug tree parity"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: slug tree mismatch:"
  echo "${DIFF_OUT}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- final tally ---
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "----------------------------------------"
echo "check-i18n-parity: ${PASS_COUNT}/${TOTAL} parity assertions passed"
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: ${FAIL_COUNT} parity violation(s) (DOC-12)." >&2
  echo "Hints:" >&2
  echo "  - Did you author vi+en in the same commit (D-49)?" >&2
  echo "  - Slug missing on one side? Add the matching _index.md." >&2
  echo "  - Slug renamed on one side? Rename on the other side too." >&2
  exit 1
fi

echo "OK: vi/en _index.md tree parity (DOC-12)"
exit 0
