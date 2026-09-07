# spectroscopy_DCM

Tools for analyzing single-voxel MR spectroscopy (MRS) of the spinal cord.

The workflow is two steps: **(1)** convert the raw DICOMs to a BIDS NIfTI dataset,
then **(2)** run the analysis on that dataset.

## 1. `01_dcm2bids.sh` — DICOM → BIDS

Converts the raw MRS DICOM tree to a BIDS-like NIfTI dataset:
- the **last acquired** `t2_tse_sag` series → `anat/sub-XX_ses-Y_T2w.nii.gz` (dcm2niix)
- the **last** MoCo-OFF and MoCo-ON spectra → `mrs/sub-XX_ses-Y_acq-MoCoOFF_svs.nii.gz`
  and `…_acq-MoCoON_svs.nii.gz` (spec2nii → NIfTI-MRS, carrying the voxel geometry)

```bash
./01_dcm2bids.sh <dicom_root> <bids_root>
```

Requirements:

- `dcm2niix` (for the T2 DICOMs)
- `spec2nii` (for the MRS DICOMs)

Expected input layout:
```
<dicom_root>/sub-XX/ses-Y/<scanID>/
    std*_t2_tse_sag*/                  anatomical T2 DICOM series
    std*_*_MoCo-OFF_SUM/*.dcm           summed MRS spectrum (MoCo-OFF)
    std*_*_MoCo-ON_SUM/*.dcm            summed MRS spectrum (MoCo-ON)
```

## 2. `02_compute_csf_and_overlap.sh` — analysis

A bash pipeline (with SCT functions) + one small Python helper (`mrs_voxel_mask.py`).
Two things:

### a) CSF fraction inside the MRS voxel
For each subject / session:
1. `mrs_voxel_mask.py` creates a binary mask of the single MRS voxel in the anatomical T2w space.
2. SCT segments the **spinal cord** (`sct_deepseg spinalcord`). Known issue: the MRS voxel goes above the cord segmentation ([#1](https://github.com/valosekj/spectroscopy_DCM/issues/1))
3. The voxel is masked by the cord (`sct_maths`, `fslstats`) → **cord (tissue)
   fraction** and **CSF fraction**, where CSF = everything inside the voxel that is
   not cord. Matches the earlier DCM spectroscopy method (`DCM_spectro_pipeline.sh`,
   Horák et al.).

### b) Voxel overlap between visits (ses-1 vs ses-2)
Three Dice-like metrics are explored:
- **`dice_native`** — ses-2 is **rigidly** registered to ses-1
  (`sct_register_multimodal`, cord-seg used for initialization), removing only patient
  repositioning.
- **`dice_pam50`** — both voxels are warped to the **PAM50 template** via disc-based
  template registration (`sct_label_vertebrae` → `sct_register_to_template`).
- **`dice_straighten`** — ses-2 is registered to ses-1 by **matching the discs in
  native space** (`sct_straighten_spinalcord -dest`; no template, hence no S-I
  scaling distortion. Context: https://github.com/neuropoly/idea-projects/issues/17#issuecomment-1584916867).

```bash
# activate the SCT environment first
source ${SCT_DIR}/python/etc/profile.d/conda.sh && conda activate venv_sct

./02_compute_csf_and_overlap.sh <bids_root> <output_dir>
```

### Output (in `<output_dir>`)
- `csf_fractions.csv` — per subject/session/MRS type: `voxel_volume_mm3`,
  `cord_fraction`, `csf_fraction`, `cord_volume_mm3`, `csf_volume_mm3`.
- `voxel_overlap.csv` — per subject/MRS type: `dice_native`, `dice_pam50`,
  `dice_straighten`.
- `qc/index.html` — **QC report** (voxel placement, cord seg, disc labels,
  registration, and the ses-1↔ses-2 overlap maps). Open this to review.
- Per subject/session: voxel masks, segmentations, warps.

## Requirements
- **SCT** (Spinal Cord Toolbox) — `sct_*`, plus `python` with `nibabel`/`numpy`.
- **FSL** — provides `dcm2niix`, `spec2nii`, `fslstats`
  (auto-detected via `FSLDIR`, default `/Users/valosek/code/fsl_6.0.6.2`).
