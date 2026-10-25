#!/bin/sh
# Native FreeBSD VM execution, with build output excluded from source copyback.
set -eu
toolchain=$(python3 -c 'import pathlib,tomllib; print(tomllib.loads(pathlib.Path("Source/Guanyinma/rust-toolchain.toml").read_text())["toolchain"]["channel"])')
curl --proto '=https' --tlsv1.2 --fail --silent --show-error https://sh.rustup.rs -o /tmp/guanyinma-rustup-init.sh
sh /tmp/guanyinma-rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain "$toolchain"
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR=/tmp/guanyinma-core-target
export CARGO_TERM_COLOR=never
python3 Source/Guanyinma/tools/ci/run-ci.py --platform freebsd --sqlite-provider system
