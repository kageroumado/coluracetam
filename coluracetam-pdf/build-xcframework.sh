#!/bin/zsh
# Builds libcoluracetam_pdf.a for every available Apple target, lipos the
# slices, and packages coluracetam-kit/Artifacts/ColuracetamPDF.xcframework.
#
# Universal builds need the x86_64-apple-darwin std library. Homebrew Rust
# ships host-only; install rustup (`brew install rustup`) and
# `rustup target add x86_64-apple-darwin` before a release build. An
# arm64-only framework is fine for local development.
set -euo pipefail
cd "$(dirname "$0")"

# Prefer rustup's cargo (has cross-target std libs) over Homebrew rust's.
if [[ -d /opt/homebrew/opt/rustup/bin ]]; then
    export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
fi

TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
OUTPUT="../coluracetam-kit/Artifacts/ColuracetamPDF.xcframework"

libs=()
for target in $TARGETS; do
    if cargo build --release --target "$target"; then
        libs+=("target/$target/release/libcoluracetam_pdf.a")
    else
        echo "warning: skipping $target (std library not installed for this target)" >&2
    fi
done

if (( ${#libs} == 0 )); then
    echo "error: no targets built" >&2
    exit 1
fi

mkdir -p target/universal
if (( ${#libs} > 1 )); then
    lipo -create "${libs[@]}" -output target/universal/libcoluracetam_pdf.a
else
    cp "${libs[1]}" target/universal/libcoluracetam_pdf.a
fi

rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
    -library target/universal/libcoluracetam_pdf.a \
    -headers include \
    -output "$OUTPUT"

echo "Built $OUTPUT ($(lipo -archs target/universal/libcoluracetam_pdf.a))"
