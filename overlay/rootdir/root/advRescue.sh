#!/bin/bash

mission=""
type=""
ts=""
state=""

DEV_UBUNTU="/dev/sda2"
MNT_UBUNTU="/mnt/ubuntu"
MNT_STORAGE="/mnt/storage"


CONF_PATH="/mnt/ubuntu/var/tmp_adv"
CONF_FILE="$CONF_PATH/.rescue_mission.json"
#CONF_FILE=".rescue_mission.conf"


##### backup #####
function clean_exist_img_files()
{
	rm -f $storage/en64_mbr.txt
	rm -f $storage/en64_sfdata.txt
	rm -f $storage/*.img
}

function fetch_mbr()
{
	local storage=$1
	local disk=$2
	echo "fetch mbr.bin"
	dd if=/dev/$disk of=/tmp/mbr.bin bs=32k count=1
	cat /tmp/mbr.bin | base64 > $storage/en64_mbr.txt
}

function fetch_sfd()
{
	local storage=$1
	local disk=$2
	echo "fetch sfdisk"
	sfdisk --dump /dev/$disk > /tmp/sfdata.txt
	cat /tmp/sfdata.txt | base64 > $storage/en64_sfdata.txt
}

##### restore #####
function clear_mbr()
{
	local disk=$1
	wipefs --all --force /dev/$disk
}

function restore_mbr()
{
	echo "restore mbr.bin"
	local storage=$1
	local disk=$2
	
	cat $storage/en64_mbr.txt | base64 --decode > /tmp/en64_mbr.bin
	dd if=/tmp/en64_mbr.bin of=/dev/$disk bs=32k count=1
}

function restore_sfd()
{
	echo "restore sfdisk"
	local storage=$1
	local disk=$2
	
	cat $storage/en64_sfdata.txt | base64 --decode > /tmp/sfdata.txt
	sfdisk --force /dev/$disk < /tmp/sfdata.txt
}

function update_diskpart()
{
	echo "update_diskpart"
	local disk=$1
	
	partprobe "/dev/$dsik"
}

# system mbr or disk partition info
function exec_init()
{
	local mission=$1
	local disk=$2
	if [ "backup" == "$mission" ]; then
		fetch_mbr "$MNT_STORAGE" "$disk"
		fetch_sfd "$MNT_STORAGE" "$disk"
	elif [ "restore" == "$mission" ]; then
		clear_mbr "sda"
		restore_mbr "$MNT_STORAGE" "$disk"
		restore_sfd "$MNT_STORAGE" "$disk"
		sync
		update_diskpart "$disk"
	fi
}

###############
function get_fs_tool()
{
    fs="$1"
    if [[ "$fs" =~ "btrfs" ]]; then
        echo "btrfs"
    elif [[ "$fs" =~ "exfat" ]]; then
        echo "exfat"
    elif [[ "$fs" =~ "ext" ]]; then
        echo "extfs"
    elif [[ "$fs" =~ "f2fs" ]]; then
        echo "f2fs"
    elif [[ "$fs" =~ "fat" ]]; then
        echo "fat"
    elif [[ "$fs" =~ "hfs" ]]; then
        echo "hfsp"
    elif [[ "$fs" =~ "minix" ]]; then
        echo "minix"
    elif [[ "$fs" =~ "nilfs" ]]; then
        echo "nilfs2"
    elif [[ "$fs" =~ "ntfs" ]]; then
        echo "ntfs"
    elif [[ "$fs" =~ "reiser" ]]; then
        echo "reiser4"
    elif [[ "$fs" =~ "xfs" ]]; then
        echo "xfs"
    else
        echo "dd"
    fi
}

function compose_backup_cmd()
{
	local fmt=$1
	local src_dev=$2
	local dir=$3
	
	local fs_tool=$(get_fs_tool "$fmt")
	
	local partclone_clone="partclone.$fs_tool --clone --force --UI-fresh 1"
	local log="--logfile /tmp/$src_dev.log"
	local source="--source /dev/$src_dev --no_block_detail"
	local compress="pigz --stdout"
	local split="split --numeric-suffixes=1 --suffix-length=3 --additional-suffix=.img --bytes=4096M -"
	##local date=`date +%Y%m%d`
	local name="$src_dev"_
	local output_path="$dir/$name"
	#echo $output_path
	
	local o_cmd="$partclone_clone $log $source | $compress | $split $output_path"
	
	#return string
	echo $o_cmd
}

function compose_restore_cmd()
{
	local fmt=$1
	local dst_dev=$2
	local dir=$3
	
	local fs_tool=$(get_fs_tool "$fmt")
	
	local partclone_restore="partclone.$fs_tool --restore --force --UI-fresh 1"
	local log="--logfile /tmp/$dst_dev.log"
	
	local decompress="pigz --decompress --stdout"
	local restore_opt="--overwrite /dev/$dst_dev --no_block_detail"
	
	#local date=`date +%Y%m%d`
	local name="$dst_dev"_??*.img
	local image_path="$dir/$name"
	#echo $image_path
	
	local o_cmd="cat $image_path | $decompress | $partclone_restore $log $restore_opt"
	
	#return string
	echo $o_cmd
}

function exec_partclone()
{
	local mission=$1
	local type=$2
	local diskpart=$3
	local fs=$4
	local storage=$5
	
	if [ "backup" == "$mission" ]; then
		# clean disk
		#mkfs.$fs $storage
		# compress imagelist => save to storage
		do_backup=$(compose_backup_cmd "$fs" "$diskpart" "$storage")
		#echo $do_backup
		eval $do_backup
	elif [ "restore" == "$mission" ]; then
		# get imagelist's image from storage, do restore
	        do_restore=$(compose_restore_cmd "$fs" "$diskpart" "$storage")
		#echo $do_restore
		eval $do_restore
	fi
}


function get_mission()
{
	mkdir -p $MNT_UBUNTU
	mount $DEV_UBUNTU $MNT_UBUNTU
	
	local json_conf=$(cat $CONF_FILE)
	
	umount $MNT_UBUNTU
	echo "$json_conf"
}

function parse_mission_and_exec()
{
	json_conf=$1
	local start_time=$(date +%s)

	# get mission: "backup" or "restore"
	mission=$(echo $json_conf | jq -r ".mission")
	type=$(echo $json_conf | jq -r ".type")
	ts=$(echo $json_conf | jq -r ".timestamp")
	state=$(echo $json_conf | jq -r ".state")
	disk=$(echo $json_conf | jq -r ".disk")
	local storage=$(echo $json_conf | jq -r ".storage")
	
	echo "Mission: $mission"
	echo "storage: $storage"
	echo "state: $state"
	echo "Timestamp: $ts"
	
	local RESULT_FILE="$CONF_PATH/.advRescue_""$mission"_result.json


	#Checking Params 
	if [ "restore" != "$mission" ] && [ "backup" != "$mission" ]; then
		return -1
	elif [ "Accept" != "$state" ]; then
		return -2
	else
		#update state
		local update=$(echo "$json_conf" | jq --arg k "state" --arg v "Processing" '.[$k] = $v')
		echo "$update" > $RESULT_FILE
	fi


        mkdir -p $MNT_STORAGE
        mount "/dev/$storage" $MNT_STORAGE

	# remove existed backup files
	if [ "backup" != "$mission" ]; then
		clean_exist_img_files
	fi

	# system disk info backup/restore
	exec_init "$mission" "$disk"
	
	# image backup/restore
	local nof_src_disk=$(echo "$json_conf" | jq '.imagelist | length')
	for ((i = 0; i < $nof_src_disk; i++));
	do
		local obj_imagelist=$(echo $json_conf | jq -r ".imagelist[$i]")
		local diskpart=$(echo $obj_imagelist | jq -r ".name")
		local fs=$(echo $obj_imagelist | jq -r ".fs")
		echo "diskpart: $diskpart, $fs"
		
		exec_partclone "$mission" "$type" "$diskpart" "$fs" "$MNT_STORAGE"
	done
	
	# Adding Duration Time, update State
	local end_time=$(date +%s)
	local dur=$((end_time - start_time))
	update=$(echo "$update" | jq --arg v "$dur" '. + {"duration_sec": $v}')
	update=$(echo "$update" | jq --arg k "state" --arg v "Done" '.[$k] = $v')

	mount $DEV_UBUNTU $MNT_UBUNTU
	#echo "$update" > $CONF_FILE
	echo "$update" > $RESULT_FILE
	
	# Remove mission conf file
	rm -f $CONF_FILE

	umount $MNT_UBUNTU
	umount $MNT_STORAGE
}

function grub_switch()
{
	ubuntu_disk="$1"
	boot_opt="$2"
	mkdir $MNT_UBUNTU
	mount $ubuntu_disk $MNT_UBUNTU
	mount -o bind /dev $MNT_UBUNTU/dev
	mount -o bind /dev/pts $MNT_UBUNTU/dev/pts
	mount -o bind /proc $MNT_UBUNTU/proc
	mount -o bind /run $MNT_UBUNTU/run
	mount -o bind /sys $MNT_UBUNTU/sys

	path="/mnt/ubuntu/etc/default/grub"
	sed -i "s/GRUB_DEFAULT=.*$/GRUB_DEFAULT='$boot_opt'/" $path

	chroot /mnt/ubuntu /bin/bash -c "update-grub"

	umount $MNT_UBUNTU/dev/pts
	umount $MNT_UBUNTU/dev
	umount $MNT_UBUNTU/proc
	umount $MNT_UBUNTU/run
	umount $MNT_UBUNTU/sys
	umount $MNT_UBUNTU
}

### main start ###
echo "=== rescue begin ==="

json_conf=$(get_mission)
parse_mission_and_exec "$json_conf"
#grub_switch $DEV_UBUNTU "Ubuntu"

echo "=== rescue end ==="

