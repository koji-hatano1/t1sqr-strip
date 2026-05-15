#!/bin/bash

# ===================================================================================================
# SCRIPT: fview_t1ss.sh
# METHOD: Hatano Skull Stripping Method - T1 Sqr Strip Viewer (v2.11)
# STRATEGY: Visual inspection helper for t1sqr-strip outputs
# GITHUB: https://github.com/koji-hatano1/t1sqr-strip
# ===================================================================================================

# --- Configuration ---
BASE_PATH="/path/to/your/project"

if [ $# -lt 1 ]; then
    echo "Usage: fview_t1ss.sh [Subject ID]"
    echo "Example: fview_t1ss.sh 001"
    exit 1
fi

SESSION=$1
T1wFolder="${BASE_PATH}/${SESSION}/T1w"

T1_IMAGE="${T1wFolder}/T1w_acpc_dc_restore.nii.gz"
T2_IMAGE="${T1wFolder}/T2w_acpc_dc_restore.nii.gz"

ORIG_BRAIN="${T1wFolder}/T1w_acpc_dc_restore_brain_bet.nii.gz"
T1SS_BRAIN="${T1wFolder}/T1w_acpc_dc_restore_brain.nii.gz"
MASK="${T1wFolder}/T1w_acpc_brain_mask.nii.gz"
MASK_BET="${T1wFolder}/T1w_acpc_brain_mask_bet.nii.gz"

if [ ! -f "$T1_IMAGE" ]; then
    echo "Error: Required T1w image is missing:"
    echo "$T1_IMAGE"
    exit 1
fi

if [ ! -f "$T1SS_BRAIN" ]; then
    echo "Error: t1sqr-strip brain image is missing:"
    echo "$T1SS_BRAIN"
    exit 1
fi

echo "------------------------------------------------------------"
echo "Launching Freeview for session: ${SESSION}"
echo "Base image       : T1w_acpc_dc_restore"
echo "Optional overlay : T2w_acpc_dc_restore"
echo "Backup brain     : T1w_acpc_dc_restore_brain_bet"
echo "Current brain    : T1w_acpc_dc_restore_brain"
echo "Backup mask      : T1w_acpc_brain_mask_bet"
echo "Current mask     : T1w_acpc_brain_mask"
echo "------------------------------------------------------------"

FREEVIEW_CMD=(freeview -v "$T1_IMAGE")

if [ -f "$T2_IMAGE" ]; then
    FREEVIEW_CMD+=("$T2_IMAGE")
fi

if [ -f "$ORIG_BRAIN" ]; then
    FREEVIEW_CMD+=("${ORIG_BRAIN}:colormap=heat:opacity=0.45")
else
    echo "Warning: backup brain image not found:"
    echo "$ORIG_BRAIN"
fi

FREEVIEW_CMD+=("${T1SS_BRAIN}:colormap=jet:opacity=0.45")

if [ -f "$MASK_BET" ]; then
    FREEVIEW_CMD+=("${MASK_BET}:colormap=lut:opacity=0.25")
else
    echo "Warning: backup mask not found:"
    echo "$MASK_BET"
fi

if [ -f "$MASK" ]; then
    FREEVIEW_CMD+=("${MASK}:colormap=gecolor:opacity=0.25")
else
    echo "Warning: current mask not found:"
    echo "$MASK"
fi

"${FREEVIEW_CMD[@]}" &