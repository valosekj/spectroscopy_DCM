#!/bin/bash
#
# Convert the raw MRS DICOMs to a BIDS-like dataset.
#
# Input layout (one scan folder per session):
#   <dicom_root>/sub-XX/ses-Y/<scanID>/
#       std*_t2_tse_sag*/                 anatomical T2 DICOM series
#       std*_*_MoCo-OFF_SUM/*.dcm          summed MRS spectrum (MoCo-OFF)
#       std*_*_MoCo-ON_SUM/*.dcm           summed MRS spectrum (MoCo-ON)
#
# Output (BIDS):
#   <bids_root>/sub-XX/ses-Y/anat/sub-XX_ses-Y_T2w.nii.gz            (+ .json)
#   <bids_root>/sub-XX/ses-Y/mrs/ sub-XX_ses-Y_acq-MoCoOFF_svs.nii.gz (+ .json)
#                                 sub-XX_ses-Y_acq-MoCoON_svs.nii.gz  (+ .json)
#
# The LAST acquired t2_tse_sag and the LAST measurement of each MRS type are used.
# T2 is converted with dcm2niix; MRS with spec2nii (-> NIfTI-MRS). Both from FSL.
#
# Usage:
#   ./01_dcm2bids.sh <dicom_root> <bids_root>
#
# Author: Jan Valosek

DICOM_ROOT="${1:?Usage: $0 <dicom_root> <bids_root>}"
BIDS_ROOT="${2:?Usage: $0 <dicom_root> <bids_root>}"

: "${FSLDIR:=/Users/valosek/code/fsl_6.0.6.2}"
export FSLDIR
export PATH="$FSLDIR/bin:$FSLDIR/share/fsl/bin:$PATH"
export FSLOUTPUTTYPE=NIFTI_GZ

# acq label (BIDS, alphanumeric) -> series-name fragment in the DICOM folder name
MRS_ACQ="MoCoOFF MoCoON"
acq_token() { case "$1" in MoCoOFF) echo "MoCo-OFF";; MoCoON) echo "MoCo-ON";; esac; }


# Highest-numbered t2_tse_sag DICOM folder (last acquired)
find_t2_dicom_dir() {
    ls -d "$1"/std*_t2_tse_sag* 2>/dev/null \
        | while read -r d; do echo "$(basename "$d" | cut -d_ -f2) $d"; done \
        | sort -n | tail -1 | cut -d' ' -f2-
}

# DICOM of the last summed MRS spectrum of a given type (folder std*_<NN>_..._SUM)
find_mrs_dicom() {
    local last_dir
    last_dir=$(ls -d "$1"/*"$2"_SUM 2>/dev/null \
        | while read -r d; do echo "$(basename "$d" | cut -d_ -f2) $d"; done \
        | sort -n | tail -1 | cut -d' ' -f2-)
    [ -n "$last_dir" ] && ls "$last_dir"/*.dcm 2>/dev/null | head -1
}


for sub_dir in "$DICOM_ROOT"/sub-*; do
    sub=$(basename "$sub_dir")
    for ses_dir in "$sub_dir"/ses-*; do
        ses=$(basename "$ses_dir")
        scan_dir=$(find "$ses_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
        echo "=== $sub $ses ($(basename "$scan_dir")) ==="

        # --- anatomical T2 -> anat/ ---
        anat_dir="$BIDS_ROOT/$sub/$ses/anat"; mkdir -p "$anat_dir"
        t2_dcm=$(find_t2_dicom_dir "$scan_dir")
        if [ -n "$t2_dcm" ] && [ ! -f "$anat_dir/${sub}_${ses}_T2w.nii.gz" ]; then
            dcm2niix -z y -f "${sub}_${ses}_T2w" -o "$anat_dir" "$t2_dcm" >/dev/null 2>&1
            echo "  T2w  <- $(basename "$t2_dcm")"
        fi

        # --- MRS spectra -> mrs/ ---
        mrs_dir="$BIDS_ROOT/$sub/$ses/mrs"; mkdir -p "$mrs_dir"
        for acq in $MRS_ACQ; do
            dcm=$(find_mrs_dicom "$scan_dir" "$(acq_token "$acq")")
            if [ -n "$dcm" ] && [ ! -f "$mrs_dir/${sub}_${ses}_acq-${acq}_svs.nii.gz" ]; then
                spec2nii dicom -f "${sub}_${ses}_acq-${acq}_svs" -o "$mrs_dir" "$dcm" >/dev/null 2>&1
                echo "  $acq <- $(basename "$(dirname "$dcm")")"
            fi
        done
    done
done

echo ""
echo "Done. BIDS dataset written to $BIDS_ROOT"
