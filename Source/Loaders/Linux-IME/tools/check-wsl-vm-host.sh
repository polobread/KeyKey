#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -r) != *microsoft-standard-WSL2* ]]; then
  echo "This check requires a normal WSL2 Ubuntu shell." >&2
  exit 2
fi

if [[ ! -c /dev/kvm ]]; then
  echo "KVM is not visible in this process." >&2
  echo "Retry from a normal WSL shell; a restricted process may hide /dev/kvm." >&2
  exit 1
fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "The current user cannot open /dev/kvm. Check membership in the kvm group and start a new WSL shell." >&2
  exit 1
fi

for command_name in python3 qemu-system-x86_64 qemu-img timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done
if [[ ! -r /usr/share/OVMF/OVMF_CODE_4M.fd || \
      ! -r /usr/share/OVMF/OVMF_VARS_4M.fd ]]; then
  echo "OVMF firmware is missing." >&2
  exit 1
fi

api_version=$(python3 - <<'PY'
import fcntl
import os

fd = os.open('/dev/kvm', os.O_RDWR)
try:
    print(fcntl.ioctl(fd, 0xAE00, 0))
finally:
    os.close(fd)
PY
)
if [[ "$api_version" != 12 ]]; then
  echo "Unexpected KVM API version: $api_version" >&2
  exit 1
fi

qmp_output=$(mktemp /tmp/keykey-wsl-kvm.XXXXXX)
trap 'rm -f -- "$qmp_output"' EXIT
qemu_status=0
timeout 3s qemu-system-x86_64 \
  -accel kvm -machine q35 -cpu host -m 128 \
  -display none -nodefaults -S -monitor none -qmp stdio \
  </dev/null >"$qmp_output" 2>&1 || qemu_status=$?
if [[ "$qemu_status" -ne 124 ]] || ! grep -Fq '"QMP"' "$qmp_output"; then
  cat "$qmp_output" >&2
  echo "QEMU did not start with KVM acceleration." >&2
  exit 1
fi

printf 'WSL2 KVM host ready: API %s, %s, OVMF present.\n' \
  "$api_version" "$(qemu-system-x86_64 --version | head -n 1)"
