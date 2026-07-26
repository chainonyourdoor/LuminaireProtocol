#!/usr/bin/env bash

[ -n "${KPATCH_NEXT_KPIMG:-}" ] && [ -n "${KPATCH_NEXT_KPTOOLS:-}" ] \
    || error "KPatch-Next: KPATCH_NEXT_KPIMG/KPATCH_NEXT_KPTOOLS not set — kpatch-next.sh addon may not have run correctly!"

KPATCH_NEXT_IMAGE="${OUT_DIR}/arch/${ARCH}/boot/Image"
[ -f "$KPATCH_NEXT_IMAGE" ] || error "KPatch-Next: kernel Image not found at ${KPATCH_NEXT_IMAGE} — did the build stage produce it?"

log "🩹 Patching kernel Image with KPatch-Next..."

KPATCH_NEXT_PATCH_ARGS=(
    -p
    -i "$KPATCH_NEXT_IMAGE"
    -k "$KPATCH_NEXT_KPIMG"
    -o "${KPATCH_NEXT_IMAGE}.kpatched"
)

# Embed kpatch binary if built. See CODEX.md.
[ -n "${KPATCH_NEXT_KPATCH_BIN:-}" ] && KPATCH_NEXT_PATCH_ARGS+=(-K "$KPATCH_NEXT_KPATCH_BIN")

"${KPATCH_NEXT_KPTOOLS}" "${KPATCH_NEXT_PATCH_ARGS[@]}" \
    || error "KPatch-Next: kptools patch failed!"

[ -f "${KPATCH_NEXT_IMAGE}.kpatched" ] || error "KPatch-Next: patch command exited 0 but output file missing!"

# Keep unpatched Image as .orig, swap patched one into AnyKernel3's expected path.
mv "$KPATCH_NEXT_IMAGE" "${KPATCH_NEXT_IMAGE}.orig"
mv "${KPATCH_NEXT_IMAGE}.kpatched" "$KPATCH_NEXT_IMAGE"

log "KPatch-Next: Image patched ✅ (original preserved as Image.orig)"
