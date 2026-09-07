#!/usr/bin/env python3
"""
Create a binary mask of the single MRS voxel in the anatomical T2 space.

Usage:
    mrs_voxel_mask.py <nifti_mrs.nii.gz> <ref_t2.nii.gz> <out_mask.nii.gz>

The NIfTI-MRS file (from spec2nii) is a 1x1x1 image whose affine holds the MRS
voxel position, orientation and size in scanner coordinates. An anatomical voxel
belongs to the MRS voxel when its centre, expressed in MRS voxel-index space, lies
within [-0.5, 0.5] along every axis.

This is the one geometric step that the command-line tools cannot do (FSL cannot
even read the complex NIfTI-MRS file); everything else is done with SCT in the
accompanying bash script.
"""

import sys
import numpy as np
import nibabel as nib

mrs_file, ref_file, out_file = sys.argv[1:4]
mrs = nib.load(mrs_file)
ref = nib.load(ref_file)

ijk = np.indices(ref.shape[:3]).reshape(3, -1).T               # all anatomical voxel indices
world = nib.affines.apply_affine(ref.affine, ijk)              # -> scanner coordinates
mrs_index = nib.affines.apply_affine(np.linalg.inv(mrs.affine), world)  # -> MRS voxel-index space
inside = np.all(np.abs(mrs_index) <= 0.5, axis=1).reshape(ref.shape[:3])

nib.save(nib.Nifti1Image(inside.astype(np.uint8), ref.affine), out_file)
print(f"  {out_file}: {int(inside.sum())} voxels inside the MRS voxel")
