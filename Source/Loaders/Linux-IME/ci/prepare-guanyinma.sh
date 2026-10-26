# Source this file before a dual-core build. Cache locations belong to the
# calling build user, including arbitrary non-root container uids.
if [[ "${KEYKEY_ENABLE_GUANYINMA:-OFF}" == ON ]]; then
  keykey_prepare_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
  keykey_core_dir=$(CDPATH='' cd -- "$keykey_prepare_dir/../../Guanyinma" && pwd)
  keykey_rust_channel=$(sed -n 's/^channel = "\([0-9.]*\)"/\1/p' "$keykey_core_dir/rust-toolchain.toml")
  if [[ -z "$keykey_rust_channel" ]]; then
    echo "Cannot read the pinned Guanyinma Rust toolchain." >&2
    return 1
  fi
  if [[ -z "${CARGO:-}" && -z "${CARGO_HOME:-}" &&
        -x "$keykey_prepare_dir/out/rust/cargo/bin/cargo" ]]; then
    export CARGO_HOME="$keykey_prepare_dir/out/rust/cargo"
    export RUSTUP_HOME="${RUSTUP_HOME:-$keykey_prepare_dir/out/rust/rustup}"
    export PATH="$CARGO_HOME/bin:$PATH"
  fi
  keykey_cargo_version=$(RUSTUP_TOOLCHAIN="$keykey_rust_channel" "${CARGO:-cargo}" --version 2>/dev/null || true)
  if [[ "$keykey_cargo_version" != "cargo $keykey_rust_channel "* ]]; then
    export CARGO_HOME="${CARGO_HOME:-$keykey_prepare_dir/out/rust/cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-$keykey_prepare_dir/out/rust/rustup}"
    export PATH="$CARGO_HOME/bin:$PATH"
    case "${KEYKEY_GUANYINMA_OFFLINE:-OFF}" in
      ON|1) echo "Offline Guanyinma build requires a prepared pinned Rust toolchain." >&2; return 1 ;;
    esac
    mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"
    keykey_rust_installer=$(mktemp "${TMPDIR:-/tmp}/keykey-rustup-init.XXXXXX")
    if ! curl --fail --location --proto '=https' --tlsv1.2 https://sh.rustup.rs -o "$keykey_rust_installer"; then
      rm -f "$keykey_rust_installer"
      return 1
    fi
    sh "$keykey_rust_installer" -y --no-modify-path --profile minimal \
      --default-toolchain "$keykey_rust_channel"
    rm -f "$keykey_rust_installer"
    export CARGO="$CARGO_HOME/bin/cargo"
  fi
  export CARGO="${CARGO:-$(command -v cargo)}"
  export RUSTUP_TOOLCHAIN="$keykey_rust_channel"
  case "${KEYKEY_GUANYINMA_OFFLINE:-OFF}" in
    ON|1) ;;
    *) (cd "$keykey_core_dir" && "$CARGO" fetch --locked) ;;
  esac
fi
