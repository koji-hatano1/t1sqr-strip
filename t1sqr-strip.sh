#!/bin/bash

# ===================================================================================================
# SCRIPT: t1sqr-strip.sh
# METHOD: Hatano Skull Stripping Method - T1w (v2.11)
# STRATEGY: T1w-based SynthStrip with squared-intensity adaptive thresholding
# GITHUB: https://github.com/koji-hatano1/t1sqr-strip
# ===================================================================================================

# --- Configuration ---
Subjlist="001 002 003"
BASE_PATH="/path/to/your/project"

# --- Extraction and threshold settings ---
border_num=2
SD_FACTOR_T1=1.960

# Reference:
# 1.960 (95%)   : standard
# 2.241 (97.5%) : intermediate
# 2.576 (99%)   : conservative

# --- Temporary file handling ---
# 0: remove temporary files after each session
# 1: keep temporary files for debugging and visual inspection
KEEP_TMP=0

# --- Global logging ---
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
GLOBAL_LOG="hss-t1sqr_v2.11_global_${TIMESTAMP}.log"

# --- Logging functions ---
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}"
}

log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] (Session ${SESSION}) $1"
    echo "$msg" | tee -a "$GLOBAL_LOG" "${SUBJ_LOG:-/dev/null}" "${SUBJ_ERR:-/dev/null}" >&2
}

log_info "=== Hatano Skull Stripping Method - T1w v2.11 Started ==="

for SESSION in ${Subjlist}; do
    SUBJ_LOG="${BASE_PATH}/hss-t1sqr_v2.11_${SESSION}_${TIMESTAMP}.log"
    SUBJ_ERR="${BASE_PATH}/hss-t1sqr_v2.11_${SESSION}_${TIMESTAMP}.err"

    log_info "-----------------------------------------------------------"
    log_info " Starting Session: ${SESSION}"

    T1wFolder="${BASE_PATH}/${SESSION}/T1w"
    AtlasSpaceFolder="${BASE_PATH}/${SESSION}/MNINonLinear"
    MASK="${T1wFolder}/T1w_acpc_brain_mask.nii.gz"

    if [ -f "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" ]; then
        log_info " Step A: Creating T1w-based SynthStrip & Squared-Intensity Thresholding..."

        # --- 1. T1w processing: SynthStrip + squared-intensity thresholding ---
        if mri_synthstrip \
            -i "${T1wFolder}/T1w_acpc_dc_restore.nii.gz" \
            -o "${T1wFolder}/T1w_tmp_brain.nii.gz" \
            -m "${T1wFolder}/T1w_tmp_mask.nii.gz" \
            -b "${border_num}" \
            --no-csf >> "$SUBJ_LOG" 2>&1; then

            INPUT_BRAIN_T1="${T1wFolder}/T1w_tmp_brain.nii.gz"
            VOX_PRE_T1=$(fslstats "${INPUT_BRAIN_T1}" -V | awk '{print $1}')

            # Create a squared-intensity image only for threshold estimation.
            fslmaths "${INPUT_BRAIN_T1}" -sqr "${T1wFolder}/T1w_sqr_tmp.nii.gz"

            stats_sqr_t1=($(fslstats "${T1wFolder}/T1w_sqr_tmp.nii.gz" -M -S))
            M_S_T1=${stats_sqr_t1[0]}
            S_S_T1=${stats_sqr_t1[1]}

            # Estimate thresholds in squared-intensity space.
            AUTO_MIN_VAL=$(echo "scale=10; $M_S_T1 - ($SD_FACTOR_T1 * $S_S_T1)" | bc -l)
            AUTO_MAX_VAL=$(echo "scale=10; $M_S_T1 + ($SD_FACTOR_T1 * $S_S_T1)" | bc -l)

            # Prevent invalid square-root calculation.
            if (( $(echo "$AUTO_MIN_VAL < 0" | bc -l) )); then
                AUTO_MIN_VAL=0
            fi

            # Convert squared-space thresholds back to the original T1w intensity space.
            AUTO_MIN_T1=$(echo "scale=10; sqrt($AUTO_MIN_VAL)" | bc -l)
            AUTO_MAX_T1=$(echo "scale=10; sqrt($AUTO_MAX_VAL)" | bc -l)

            VOX_THR_T1=$(fslstats "${INPUT_BRAIN_T1}" -l "$AUTO_MIN_T1" -u "$AUTO_MAX_T1" -V | awk '{print $1}')
            DROP_PERCENT_T1=$(echo "scale=4; ($VOX_PRE_T1 - $VOX_THR_T1) * 100 / $VOX_PRE_T1" | bc -l)

            # --- 2. Backup original PreFS/HCP outputs ---
            log_info " Step B: Backing up original PreFS/HCP outputs..."

            # Backup the standard PreFS/HCP brain mask.
            if [ -f "$MASK" ]; then
                cp -n "$MASK" "${MASK%.nii.gz}_bet.nii.gz"
            fi

            # Backup standard PreFS brain-extracted images in the T1w folder.
            for img in T1w_acpc_dc_restore T1w_acpc_dc T1w_acpc T2w_acpc_dc_restore T2w_acpc; do
                target_img="${T1wFolder}/${img}_brain.nii.gz"
                if [ -f "$target_img" ]; then
                    cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
                fi
            done

            # Backup existing MNINonLinear brain-extracted images when present.
            for img in T1w_restore T1w T2w_restore T2w; do
                target_img="${AtlasSpaceFolder}/${img}_brain.nii.gz"
                if [ -f "$target_img" ]; then
                    cp -n "$target_img" "${target_img%.nii.gz}_bet.nii.gz"
                fi
            done

            # --- 3. Final mask generation ---
            log_info " Step C: Generating Final Mask from T1w Thresholds..."

            fslmaths "${INPUT_BRAIN_T1}" \
                -thr "$AUTO_MIN_T1" \
                -uthr "$AUTO_MAX_T1" \
                -bin \
                -fillh \
                -ero \
                -dilM \
                "$MASK"

            # --- 4. Statistics output ---
            {
                echo "---------------------------------------------------------"
                echo "====== T1w Squared-Intensity Thresholding Results ======"
                echo "Session: ${SESSION}"

                VOX_DROP_T1=$(echo "$VOX_PRE_T1 - $VOX_THR_T1" | bc)
                VOX_REM_T1=$VOX_THR_T1
                VOX_POST=$(fslstats "$MASK" -V | awk '{print $1}')

                echo " [T1w (Sqr)] Factor: ${SD_FACTOR_T1}SD"
                printf " Thresholds: %.2f - %.2f\n" "$AUTO_MIN_T1" "$AUTO_MAX_T1"
                printf " Squared-space limits: %.2f - %.2f\n" "$AUTO_MIN_VAL" "$AUTO_MAX_VAL"
                printf " Voxels : Initial: %d | Dropped: %d (%.2f%%)\n" "$VOX_PRE_T1" "$VOX_DROP_T1" "$DROP_PERCENT_T1"
                printf " Remaining: %d\n" "$VOX_REM_T1"

                echo " [Final Result]"
                echo " Final Mask Size: $VOX_POST voxels"
                echo " Steps: T1w sqr -> sqrt threshold -> fillh -> ero -> dilM"
                echo "---------------------------------------------------------"
            } | tee -a "$SUBJ_LOG" "$GLOBAL_LOG"

            # --- 5. Visual histogram ---
            {
                echo ""
                echo "--- T1w Visual Histogram (x: Out | o: In) ---"
                fslstats "${INPUT_BRAIN_T1}" -l 0.0001 -H 40 0 1000 | \
                awk -v low="$AUTO_MIN_T1" -v high="$AUTO_MAX_T1" \
                '{val=NR*25; line=sprintf("%5.0f: ", val); mark=(val>high||val<low)?"x":"o"; content=""; for(i=0;i<$1/5000;i++){content=content mark} print line content "|" $1}' | tac | \
                awk -F'|' 'found||$2>0{found=1; print $1}' | tac
                echo ""
            } >> "$SUBJ_LOG"

            # --- 6. Update standard PreFS brain-extracted images in the T1w folder ---
            log_info " Step D: Updating brain-extracted files in T1w folder..."

            for img in T1w_acpc_dc_restore T1w_acpc_dc T1w_acpc; do
                if [ -f "${T1wFolder}/${img}.nii.gz" ]; then
                    fslmaths "${T1wFolder}/${img}.nii.gz" \
                        -mas "$MASK" \
                        "${T1wFolder}/${img}_brain.nii.gz"
                fi
            done

            if [ -f "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" ]; then
                fslmaths "${T1wFolder}/T2w_acpc_dc_restore.nii.gz" \
                    -mas "$MASK" \
                    "${T1wFolder}/T2w_acpc_dc_restore_brain.nii.gz"
            fi

        else
            log_err "SynthStrip failed."
            continue
        fi

    else
        log_err "Required ACPC files missing."
        continue
    fi

    # --- 7. Synchronize to MNI space ---
    log_info " Step E: Synchronizing to MNI space..."

    if applywarp --rel --interp=nn \
        -i "$MASK" \
        -r "${AtlasSpaceFolder}/T1w_restore.nii.gz" \
        -w "${AtlasSpaceFolder}/xfms/acpc_dc2standard.nii.gz" \
        -o "${AtlasSpaceFolder}/tmp_m.nii.gz" >> "$SUBJ_LOG" 2>&1; then

        for img in T1w_restore T2w_restore; do
            if [ -f "${AtlasSpaceFolder}/${img}.nii.gz" ]; then
                fslmaths "${AtlasSpaceFolder}/${img}.nii.gz" \
                    -mas "${AtlasSpaceFolder}/tmp_m.nii.gz" \
                    "${AtlasSpaceFolder}/${img}_brain.nii.gz"
            fi
        done

        rm -f "${AtlasSpaceFolder}/tmp_m.nii.gz"
        log_info " [Done] MNI synchronization complete."

    else
        log_err "applywarp failed."
    fi

    # --- 8. Cleanup temporary files ---
    if [ "$KEEP_TMP" -eq 0 ]; then
        rm -f "${T1wFolder}/T1w_tmp_brain.nii.gz" \
              "${T1wFolder}/T1w_tmp_mask.nii.gz" \
              "${T1wFolder}/T1w_sqr_tmp.nii.gz" \
              "${AtlasSpaceFolder}/tmp_m.nii.gz"
        log_info " [Cleanup] Temporary files removed."
    else
        log_info " [Cleanup] Temporary files kept for debugging."
    fi

    log_info " Finished Session: ${SESSION}"

done

unset SUBJ_LOG

# ===================================================================================================
# Auto-Summary Generator
# ===================================================================================================

SUMMARY_FILE="hss_t1sqr_summary_${TIMESTAMP}.csv"

echo "Session,T1_SD,T1_Min,T1_Max,T1_Sqr_Min,T1_Sqr_Max,T1_Init,T1_Drop,T1_Drop%,T1_Rem,Final_Mask" > "$SUMMARY_FILE"

for SESSION in ${Subjlist}; do
    block=$(sed -n "/.*Starting Session: ${SESSION}/,/.*Finished Session: ${SESSION}/p" "$GLOBAL_LOG")

    t1_sd=$(echo "$block" | grep "\[T1w" | awk -F'Factor: ' '{print $2}' | awk '{print $1}' | sed 's/SD//' | head -n 1)
    t1_min=$(echo "$block" | grep -A 2 "\[T1w" | grep "Thresholds" | awk '{print $2}' | head -n 1)
    t1_max=$(echo "$block" | grep -A 2 "\[T1w" | grep "Thresholds" | awk '{print $4}' | head -n 1)
    t1_sqr_min=$(echo "$block" | grep -A 3 "\[T1w" | grep "Squared-space limits" | awk '{print $3}' | head -n 1)
    t1_sqr_max=$(echo "$block" | grep -A 3 "\[T1w" | grep "Squared-space limits" | awk '{print $5}' | head -n 1)
    t1_init=$(echo "$block" | grep -A 6 "\[T1w" | grep "Initial:" | awk -F'Initial: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t1_drop=$(echo "$block" | grep -A 6 "\[T1w" | grep "Dropped:" | awk -F'Dropped: ' '{print $2}' | awk '{print $1}' | head -n 1)
    t1_per=$(echo "$block" | grep -A 6 "\[T1w" | grep "Dropped:" | awk -F'(' '{print $2}' | awk -F'%' '{print $1}' | head -n 1)
    t1_rem=$(echo "$block" | grep -A 6 "\[T1w" | grep "Remaining:" | awk -F'Remaining: ' '{print $2}' | head -n 1)
    f_vox=$(echo "$block" | grep "Final Mask Size" | awk '{print $4}' | head -n 1)

    echo "${SESSION},${t1_sd},${t1_min},${t1_max},${t1_sqr_min},${t1_sqr_max},${t1_init},${t1_drop},${t1_per},${t1_rem},${f_vox}" >> "$SUMMARY_FILE"
done

log_info "---------------------------------------------------------------"
log_info " [HSS Summary CSV Created] --> ${SUMMARY_FILE}"
log_info "---------------------------------------------------------------"
log_info "t1sqr-strip.sh: Hatano Skull Stripping Method v2.11 Complete."