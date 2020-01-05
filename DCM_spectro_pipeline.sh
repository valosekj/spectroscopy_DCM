# Script for calculation SC and CSF fraction of spectroscopic voxel
# Script performes:
#		- T2SAG resampling to 0.5mm isotropic voxel and conversion to dicom
#		- SC segmentation of original T2SAG and masking of spectroscopic voxel
#		- SC segmentation of resampled T2SAG and masking of spectroscopic voxel

# Segmentation report is saved into qc folder (non testes and used)

# JV, 17-12-2019


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

	for SUB in [0-9][0-9][0-9][0-9][A];do
	#for SUB in 2470A;do

		echo "Starting processing of $SUB with SCT located in $PATH_SCT"

		# t2sag_volume

		# t2sag_resample

		volume_sc_spectro_voxel

		# t2sag_resample_exclude_csf

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

# Function for renaming original nifti files, segmentation of SC from T2SAG and volume computation
t2sag_volume()
{
	cd $SUB

	if [ ! -f mones.nii.gz ];then
		gzip *.nii
	fi

	if [  ! -f t2sag.nii.gz ];then
		cp s*01*.nii.gz t2sag.nii.gz
	fi

	# SC segmentation of original t2sag
	if [  ! -f t2sag_seg.nii.gz ];then
		$PATH_SCT/sct_deepseg_sc -i t2sag.nii.gz -c t2 -qc $DATA_DIR/qc -v 0
	fi

	if [  ! -f t2sag_seg_dil.nii.gz ];then
		fslmaths t2sag_seg.nii.gz -kernel 2D -dilM -kernel 2D -ero t2sag_seg_dil.nii.gz
	fi

	# Mask spectro voxel and compute volumes of original and masked voxels
	if [  ! -f mones_masked.nii.gz ];then
		fslmaths mones.nii.gz -mas t2sag_seg_dil.nii.gz mones_masked.nii.gz
		echo "$SUB $(fslstats mones_masked.nii.gz -V)" >> ../volumes_masked_voxel_SCT-v$SCT_VER.txt
		echo "$SUB $(fslstats mones.nii.gz -V)" >> ../volumes_original_voxel-v$SCT_VER.txt
	fi

}

# Function for resampling T2SAG, SC segmentation from T2SAG_resampled and converting T2SAG_resampled.nii to dicom
t2sag_resample()
{
	cd $SUB

	# Resampling t2sag to 0.5 isotropic voxel
	if [  ! -f t2sag_resample.nii.gz ];then
		$PATH_SCT/sct_resample -i t2sag.nii.gz -mm 0.5x0.5x0.5 -o t2sag_resample.nii.gz
	fi

	# SC segmentation of resampled 0.5 mm isotropic t2sag
	if [  ! -f t2sag_resample_seg.nii.gz ];then
		$PATH_SCT/sct_deepseg_sc -i t2sag_resample.nii.gz -c t2 -qc $DATA_DIR/qc -v 0
	fi

	# Create dicom folder
	if [  ! -d ${SUB}_dicom ];then
		mkdir ${SUB}_dicom
	fi

	# Convert resampled 0.5 mm isotropic t2sag from nifti to dicom
	if [  ! -f ${SUB}_dicom/${SUB}_0001.dcm ];then
		nifti2dicom -# 4 -s .dcm -p ${SUB}_ -o dicom/ -i t2sag_resample.nii.gz -y
	fi

}

# Function for comptuting volume of SC in range of spectroscopic voxel
volume_sc_spectro_voxel()
{
	cd $DATA_DIR/resampled_masks/$SUB

	# Get position of scpetro voxel and save it to .csv file
#		echo "$SUB $( fslstats $SUB/mones.nii -w)" >> spectro_voxel_position.csv

	# Get size of spectro voxel in z_axis (fslstats extracts only z_min and z_size)
	z_min=$(fslstats mones.nii -w | awk '{ print $5 }')		# z_axis minimum
	z_size=$(fslstats mones.nii -w | awk '{ print $6 }')	# z_axis size

	z_max=$(($z_min + $z_size - 1))						# compute z_axis maximum
	z_start=$(($z_max - 89))									#	compute low limit (same number of slices for every subject)

	output_file="${DATA_DIR}/resampled_masks/T2SAG_resampled_SC_volume_in_range_of_spectro_voxel_SCT_v${SCT_VER}_$(date +%F)"

	$PATH_SCT/sct_extract_metric -i $DATA_DIR/resampled_masks/$SUB/sid-0001-00001-000001.nii -f $DATA_DIR/resampled_masks/$SUB/sid-0001-00001-000001_seg.nii -method bin -z $z_start:$z_max -o ${output_file}.csv -append 1
	if [[ $(echo $?) == 1 ]];then "echo $subID" >> ${output_file}_error_log.txt;fi
}

# Function for exclusion of CSF voxels from spectroscopic voxel for T2SAG 0.5mm resampled image
t2sag_resample_exclude_csf()
{
	# Segmentation of t2sag resampled image (send from Tomas from SPM SW) and masking od spectroscopic voxel by this segmentation
	if [  ! -f $DATA_DIR/resampled_masks/$SUB/sid-0001-00001-000001_seg.nii ];then
		cd $DATA_DIR/resampled_masks/$SUB
		$PATH_SCT/sct_deepseg_sc -i sid-0001-00001-000001.nii -c t2 -v 0				# SC segmetnation
		fslmaths mones.nii -mas sid-0001-00001-000001_seg.nii mones_masked.nii	# Masking of spectroscopic voxel (=exclude CSF voxels)

		# Get volumes of masked and original spectroscopic voxels
		echo "$SUB $(fslstats mones_masked.nii -V) $(fslval mones_masked.nii pixdim1) $(fslval mones_masked.nii pixdim2) $(fslval mones_masked.nii pixdim3) $(fslval mones_masked.nii dim1) $(fslval mones_masked.nii dim2) $(fslval mones_masked.nii dim3)" >> ../volumes_masked_voxel_SCT-v$SCT_VER.txt
		echo "$SUB $(fslstats mones.nii -V) $(fslval mones.nii pixdim1) $(fslval mones.nii pixdim2) $(fslval mones.nii pixdim3) $(fslval mones.nii dim1) $(fslval mones.nii dim2) $(fslval mones.nii dim3)" >> ../volumes_original_voxel_SCT-v$SCT_VER.txt

	fi
}

main $@
