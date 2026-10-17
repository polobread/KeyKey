#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  echo "Usage: $0 PACKAGE..." >&2
  exit 2
fi

for package in "$@"; do
  # A retained conffile keeps the dpkg record queryable after apt remove.
  # Check every package separately: one missing package must not hide another
  # package that is still installed or only partially removed.
  if status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null); then
    case "$status" in
      config-files|not-installed) ;;
      *)
        echo "Package $package remains in state '$status' after removal." >&2
        exit 1
        ;;
    esac
  else
    query_result=$?
    if (( query_result != 1 )); then
      echo "Cannot verify removal of $package: dpkg-query failed ($query_result)." >&2
      exit "$query_result"
    fi
    status=not-found
  fi
  printf '%s\t%s\n' "$package" "$status"
done
