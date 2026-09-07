#!/bin/bash
#
# Compute CSF fraction inside the MRS voxel + overlap of the voxel between visits.
# Expects the BIDS dataset produced by 01_dcm2bids.sh.
#
# Per subject / session:
#   1. mrs_voxel_mask.py places each MRS voxel in the T2 space,
#   2. sct_deepseg segments the spinal cord,
#   3. the voxel is masked by the cord --> two fractions: cord and CSF,
#   4. disc labels + registration to the PAM50 template, used by
#      the anatomical overlap below.
#
# Per subject, three voxel-overlap metrics between ses-1 and ses-2 (Dice):
#   dice_native     : ses-2 is rigidly registered to ses-1 (removes patient repositioning only)
#   dice_pam50      : both voxels are warped to the PAM50 template (sct_register_to_template)
#   dice_straighten : ses-2 registered to ses-1 by matching discs, in native space
#                     (sct_straighten_spinalcord -dest; no template S-I scaling; context: https://github.com/neuropoly/idea-projects/issues/17#issuecomment-1584916867)
#
# Run inside the SCT environment:
#   source ${SCT_DIR}/python/etc/profile.d/conda.sh && conda activate venv_sct
#
# Usage:
#   ./02_compute_csf_and_overlap.sh <bids_root> <output_dir>
#
# Author: Jan Valosek

BIDS_ROOT="${1:?Usage: $0 <bids_root> <output_dir>}"
OUTPUT_DIR="${2:?Usage: $0 <bids_root> <output_dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PAM50_T2="$SCT_DIR/data/PAM50/template/PAM50_t2.nii.gz"

MRS_ACQ="MoCoOFF MoCoON"
CSF_CSV="$OUTPUT_DIR/csf_fractions.csv"
OVERLAP_CSV="$OUTPUT_DIR/voxel_overlap.csv"
QC="$OUTPUT_DIR/qc"   # open $QC/index.html to review


# Dice coefficient between two binary masks (parses the result line only)
dice() {
    sct_dice_coefficient -i "$1" -d "$2" 2>&1 | grep -i 'dice coefficient' | grep -oE '[0-9]+\.[0-9]+' | head -1
}

# Steps 1-4 (see the beginning of the script) for one session
process_session() {
    local sub="$1" ses="$2" out_dir="$3"
    mkdir -p "$out_dir"
    local t2="$BIDS_ROOT/$sub/$ses/anat/${sub}_${ses}_T2w.nii.gz"
    local seg_file="$out_dir/${sub}_${ses}_T2w_seg.nii.gz"

    # spinal cord segmentation
    if [ ! -f "$seg_file" ]; then
        sct_deepseg spinalcord -i "$t2" -o "$seg_file"
        sct_qc -i "$t2" -s "$seg_file" -p sct_deepseg_sc -qc "$QC" -qc-subject "${sub}_${ses}"
    fi

    # voxel mask (+ QC) + cord/CSF fractions for each MRS acquisition
    for acq in $MRS_ACQ; do
        local svs="$BIDS_ROOT/$sub/$ses/mrs/${sub}_${ses}_acq-${acq}_svs.nii.gz"

        python "$SCRIPT_DIR/mrs_voxel_mask.py" "$svs" "$t2" "$out_dir/${acq}_voxel.nii.gz"
        # sagittal view of the spectroscopic voxel on the T2 (voxel as -d, cord as -s)
        sct_qc -i "$t2" -s "$seg_file" -d "$out_dir/${acq}_voxel.nii.gz" -p sct_deepseg_lesion -plane sagittal -qc "$QC" -qc-subject "${sub}_${ses}_${acq}"
        sct_maths -i "$out_dir/${acq}_voxel.nii.gz" -mul "$seg_file" -o "$out_dir/${acq}_voxel_cord.nii.gz"

        read -r _ vol_vox  <<< "$(fslstats "$out_dir/${acq}_voxel.nii.gz" -V)"
        read -r _ vol_cord <<< "$(fslstats "$out_dir/${acq}_voxel_cord.nii.gz" -V)"
        awk -v s="$sub" -v se="$ses" -v t="$acq" -v vv="$vol_vox" -v vc="$vol_cord" \
            'BEGIN{printf "%s,%s,%s,%.1f,%.3f,%.3f,%.1f,%.1f\n", s,se,t, vv, vc/vv, 1-vc/vv, vc, vv-vc}' \
            >> "$CSF_CSV"
    done

    if [ ! -f "$out_dir/warp_anat2template.nii.gz" ]; then
        sct_label_vertebrae -i "$t2" -s "$seg_file" -c t2 -ofolder "$out_dir" -qc "$QC" -qc-subject "${sub}_${ses}"
        local discs="$out_dir/${sub}_${ses}_T2w_seg_labeled_discs.nii.gz"
        sct_register_to_template -i "$t2" -s "$seg_file" -ldisc "$discs" -c t2 \
            -ofolder "$out_dir" -qc "$QC" -qc-subject "${sub}_${ses}"
    fi
}

# Voxel overlap between ses-1 and ses-2: for different methods
compute_overlap() {
    local sub="$1"
    local dir_ses1="$OUTPUT_DIR/$sub/ses-1"
    local dir_ses2="$OUTPUT_DIR/$sub/ses-2"
    local odir="$OUTPUT_DIR/$sub/overlap"; mkdir -p "$odir"
    local t2_ses1="$BIDS_ROOT/$sub/ses-1/anat/${sub}_ses-1_T2w.nii.gz"
    local t2_ses2="$BIDS_ROOT/$sub/ses-2/anat/${sub}_ses-2_T2w.nii.gz"
    local seg_ses1="$dir_ses1/${sub}_ses-1_T2w_seg.nii.gz"
    local seg_ses2="$dir_ses2/${sub}_ses-2_T2w_seg.nii.gz"

    # rigid registration ses-2 -> ses-1
    sct_register_multimodal -i "$t2_ses2" -d "$t2_ses1" -iseg "$seg_ses2" -dseg "$seg_ses1" \
        -param step=1,type=seg,algo=centermassrot:step=2,type=im,algo=rigid \
        -owarp "$odir/warp_ses2_to_ses1.nii.gz" -ofolder "$odir" -x linear \
        -qc "$QC" -qc-subject "${sub}_overlap"

    # Disc-based alignment of ses-2 to ses-1
    # Context: https://github.com/neuropoly/idea-projects/issues/17#issuecomment-1584916867
    local disc_ses1="$dir_ses1/${sub}_ses-1_T2w_seg_labeled_discs.nii.gz"
    local disc_ses2="$dir_ses2/${sub}_ses-2_T2w_seg_labeled_discs.nii.gz"
    sct_straighten_spinalcord -i "$t2_ses2" -s "$seg_ses2" -dest "$seg_ses1" \
        -ldisc-input "$disc_ses2" -ldisc-dest "$disc_ses1" -ofolder "$odir/align_ses2_to_ses1"

    for acq in $MRS_ACQ; do

        # 1. Warp ses-2 voxel into ses-1 space
        sct_apply_transfo -i "$dir_ses2/${acq}_voxel.nii.gz" -d "$t2_ses1" -w "$odir/warp_ses2_to_ses1.nii.gz" \
            -x nn -o "$odir/${acq}_voxel_ses2_in_ses1.nii.gz"
        # QC: voxel from ses-2 warped into ses-1 space, overlaid on the T2 of ses-1
        sct_qc -i "$t2_ses1" -s "$seg_ses1" -d "$odir/${acq}_voxel_ses2_in_ses1.nii.gz" -p sct_deepseg_lesion -plane sagittal -qc "$QC" -qc-subject "${sub}_overlap_${acq}"
        local dice_native; dice_native=$(dice "$dir_ses1/${acq}_voxel.nii.gz" "$odir/${acq}_voxel_ses2_in_ses1.nii.gz")

        # 2. Warp voxels from both sessions into the common space of the PAM50 spinal cord template
        sct_apply_transfo -i "$dir_ses1/${acq}_voxel.nii.gz" -d "$PAM50_T2" -w "$dir_ses1/warp_anat2template.nii.gz" \
            -x nn -o "$odir/${acq}_voxel_ses1_in_pam50.nii.gz"
        sct_apply_transfo -i "$dir_ses2/${acq}_voxel.nii.gz" -d "$PAM50_T2" -w "$dir_ses2/warp_anat2template.nii.gz" \
            -x nn -o "$odir/${acq}_voxel_ses2_in_pam50.nii.gz"
        local dice_pam50; dice_pam50=$(dice "$odir/${acq}_voxel_ses1_in_pam50.nii.gz" "$odir/${acq}_voxel_ses2_in_pam50.nii.gz")

        # 3. Disc-based alignment: warp ses-2 voxel into ses-1 space with the single warp
        # from the registration above
        sct_apply_transfo -i "$dir_ses2/${acq}_voxel.nii.gz" -d "$t2_ses1" \
            -w "$odir/align_ses2_to_ses1/warp_curve2straight.nii.gz" \
            -x nn -o "$odir/${acq}_voxel_ses2_in_ses1_disc.nii.gz"
        # QC: ses-2 voxel disc-aligned to ses-1, overlaid on the T2 of ses-1
        sct_qc -i "$t2_ses1" -s "$seg_ses1" -d "$odir/${acq}_voxel_ses2_in_ses1_disc.nii.gz" -p sct_deepseg_lesion -plane sagittal -qc "$QC" -qc-subject "${sub}_overlap-disc_${acq}"
        local dice_straighten; dice_straighten=$(dice "$dir_ses1/${acq}_voxel.nii.gz" "$odir/${acq}_voxel_ses2_in_ses1_disc.nii.gz")

        echo "$sub,$acq,$dice_native,$dice_pam50,$dice_straighten" >> "$OVERLAP_CSV"
    done
}


main() {
    mkdir -p "$OUTPUT_DIR"
    echo "subject,session,mrs_type,voxel_volume_mm3,cord_fraction,csf_fraction,cord_volume_mm3,csf_volume_mm3" > "$CSF_CSV"
    echo "subject,mrs_type,dice_native,dice_pam50,dice_straighten" > "$OVERLAP_CSV"

    for sub_dir in "$BIDS_ROOT"/sub-*; do
        local sub; sub=$(basename "$sub_dir")
        echo "=== $sub ==="
        for ses_dir in "$sub_dir"/ses-*; do
            local ses; ses=$(basename "$ses_dir")
            echo "- $ses"
            process_session "$sub" "$ses" "$OUTPUT_DIR/$sub/$ses"
        done
        echo "- overlap ses-1 vs ses-2"
        compute_overlap "$sub"
    done

    echo ""
    echo "Done. Results:"
    echo "  $CSF_CSV"
    echo "  $OVERLAP_CSV"
}

main
