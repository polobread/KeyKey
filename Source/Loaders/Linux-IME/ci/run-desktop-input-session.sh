#!/usr/bin/env bash
set -euo pipefail
if [[ ${KEYKEY_E2E_SESSION_MODE:-managed} != managed ]]; then
  echo 'The extended desktop matrix requires a managed private display.' >&2
  exit 2
fi
if [[ -n ${CHICHI77_KEYKEY_GUANYINMA_USER_DB:-} ]]; then
  echo 'The desktop matrix requires its private DB; remove the user DB override.' >&2
  exit 2
fi
export KEYKEY_E2E_CASES=T01-X11-GTK3-BOPOMOFO-SMART,T01-X11-GTK4-BOPOMOFO-SMART,T01-X11-QT6-BOPOMOFO-STANDARD
export KEYKEY_E2E_CONFIG_UI=OFF
source "$(dirname -- "${BASH_SOURCE[0]}")/run-x11-e2e-session.sh"
python3 "$(dirname -- "${BASH_SOURCE[0]}")/../tests/desktop_input_matrix.py"
