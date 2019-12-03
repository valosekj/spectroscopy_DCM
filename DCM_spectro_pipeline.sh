# Script for calculation SC and CSF fraction of spectroscopic voxel
# Script performes SC segmentation from T2SAG image, its dilation and errosion (for correction of segmentation) and masking of spectroscopic
# voxel by this segmetnation. Than script computes volumes of original and masked spectroscopix voxels.

# Segmentation report is saved into qc folder (non testes and used)

# JV, 14-11-2019


#!/bin/bash

DATA_DIR=/md1/DCM_spectroscopy/
#SCT_VER=4.0.0
SCT_VER=4.1.0

if [ $SCT_VER == "4.0.0" ];then
	PATH_SCT=/usr/local/lib/sct/bin
elif [ $SCT_VER == "4.1.0" ];then
	PATH_SCT=/usr/local/lib/sct_v4.1.0/bin
fi


main()
{
	if [[ $1 == "-h" ]];then
		echo -e "Script for calculation SC and CSF fraction of spectroscopic voxel for SC DCM data.\nJan Valosek, 2019"
		exit
	fi

	cd $DATA_DIR

	# Unzip downloaded files
	if [ -f [0-9][0-9][0-9][0-9][A]*.zip ];then
		for file in *.zip;do
		
			unzip $file
			rm $file

		done
	fi

	#for SUB in [0-9][0-9][0-9][0-9][A];do
	for SUB in 2885A;do

		echo "Starting processing of $SUB with SCT located in $PATH_SCT"
		cd $SUB

		if [ ! -f mones.nii.gz ];then	
			gzip *.nii
		fi

		if [  ! -f t2sag.nii.gz ];then
			cp s*01*.nii.gz t2sag.nii.gz
		fi

		# Resampling to 0.5 isotropic voxel
		if [  ! -f t2sag_resample.nii.gz ];then
			$PATH_SCT/sct_resample -i t2sag.nii.gz -mm 0.5x0.5x0.5 -o t2sag_resample.nii.gz
		fi

		if [  ! -d ${SUB}_dicom ];then
			mkdir ${SUB}_dicom
		fi

		# Convert resampled t2sag from nifti to dicom
		if [  ! -f ${SUB}_dicom/${SUB}_0001.dcm ];then
			nifti2dicom -# 4 -s .dcm -p ${SUB}_ -o dicom/ -i t2sag_resample.nii.gz -y
		fi

		if [  ! -f t2sag_seg.nii.gz ];then
			$PATH_SCT/sct_deepseg_sc -i t2sag.nii.gz -c t2 -qc $DATA_DIR/qc -v 0
		fi

		if [  ! -f t2sag_resample_seg.nii.gz ];then
			$PATH_SCT/sct_deepseg_sc -i t2sag_resample.nii.gz -c t2 -qc $DATA_DIR/qc -v 0
		fi

		if [  ! -f t2sag_seg_dil.nii.gz ];then
			fslmaths t2sag_seg.nii.gz -kernel 2D -dilM -kernel 2D -ero t2sag_seg_dil.nii.gz
		fi


		if [  ! -f $DATA_DIR/resampled_masks/$SUB/sid-0001-00001-000001_seg.nii ];then
			cd $DATA_DIR/resampled_masks/$SUB
			$PATH_SCT/sct_deepseg_sc -i sid-0001-00001-000001.nii -c t2 -v 0
			fslmaths mones.nii -mas sid-0001-00001-000001_seg.nii mones_masked.nii
		
			echo "$SUB $(fslstats mones_masked.nii -V) $(fslval mones_masked.nii pixdim1) $(fslval mones_masked.nii pixdim2) $(fslval mones_masked.nii pixdim3) $(fslval mones_masked.nii dim1) $(fslval mones_masked.nii dim2) $(fslval mones_masked.nii dim3)" >> ../volumes_masked_voxel_SCT-v$SCT_VER.txt
			echo "$SUB $(fslstats mones.nii -V) $(fslval mones.nii pixdim1) $(fslval mones.nii pixdim2) $(fslval mones.nii pixdim3) $(fslval mones.nii dim1) $(fslval mones.nii dim2) $(fslval mones.nii dim3)" >> ../volumes_original_voxel_SCT-v$SCT_VER.txt

		fi
		
		cd $DATA_DIR/$SUB
		# Mask spectro voxel and compute volumes of original and masked voxels
		if [  ! -f mones_masked.nii.gz ];then
			fslmaths mones.nii.gz -mas t2sag_seg_dil.nii.gz mones_masked.nii.gz
			echo "$SUB $(fslstats mones_masked.nii.gz -V)" >> ../volumes_masked_voxel_SCT-v$SCT_VER.txt
			echo "$SUB $(fslstats mones.nii.gz -V)" >> ../volumes_original_voxel-v$SCT_VER.txt
		fi
			
		cd ..	
		
		echo "Processing of $SUB is done!"

	done


	# Reg to template
	# Do labeling (neccesary for registration)
	#sct_label_vertebrae -i t2sag.nii.gz -s t2sag_seg.nii.gz -c t2
	# Registration itself
	#/usr/local/lib/sct_v4.0.2/bin/sct_register_to_template -i t2sag.nii.gz -s t2sag_seg.nii.gz -ldisc t2sag_seg_labeled_discs.nii.gz
	# Warp spectro voxel do template
	#/usr/local/lib/sct_v4.0.2/bin/sct_apply_transfo -i mones.nii.gz -d /usr/local/lib/sct_v4.0.2/data/PAM50/template/PAM50_t2.nii.gz -w warp_anat2template.nii.gz
}

main $@

