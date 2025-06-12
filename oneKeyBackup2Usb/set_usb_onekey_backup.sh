#!/bin/bash

source json_inc.sh

HEIGHT=15
WIDTH=40
BACKTITLE="Advantech"
TITLE="Advantech Rescue"
MENU="Choose Recovery Target Disk"

DPART_BOOT=1
DPART_STORAGE=2
MPT_USB_BOOT="/mnt/USBBOOT"
MPT_USB_STORAGE="/mnt/USBSTORAGE"
LABEL_USB_STORAGE="advBackupU"
LABEL_USB_BOOT="advRescueU"

DIR_MISSION="$MPT_USB_STORAGE"
PATH_MISSION="$DIR_MISSION/.rescue_mission.json"


# get all usb device
function get_usb_list()
{
    local ESEP="$1"
    local IFS=$'\n'
    local -a options=()

    readarray -t usb_list < <(lsblk -n -p -l -o TRAN,NAME /dev/sd* 2>/dev/null |grep '^usb' |awk '{print $2}')
    #echo "${usb_list[@]}"
    #echo "num: ${#usb_list[@]}"

    # change path to model
    for ((i=0;i<${#usb_list[@]};i++))
    do
        #echo "${usb_list[$i]}"
        local model=$(lsblk -n -o MODEL ${usb_list[$i]})
        local serial=$(lsblk -n -o SERIAL ${usb_list[$i]})
        options+=("$model:$serial")
    done
    
    IFS="${ESEP}"
    echo "${options[*]}"
    #declare -p options
}

function menu_select_device()
{
    local ESEP=$'\a'
    local IFS="${ESEP}"
    local -a disk_options=()
    mapfile -t disk_options < <(get_usb_list "${ESEP}")
    #declare -p disk_options
    
    if [[ ${#disk_options[@]} -eq 0 || -z "${disk_options[0]}" ]]; then
        echo "ERR:No USB device found"
        exit
    fi

    local cmd="dialog --clear --backtitle \"$BACKTITLE\" --title \"$TITLE\" --menu \"$MENU\" $HEIGHT $WIDTH ${#disk_options[@]}"
    local dst_option=""
    
    for ((i=0; i<${#disk_options[@]}; i++));
    do
        cmd="${cmd} $((i+1)) '${disk_options[i]}'"
    done
        
    #declare -p cmd
    select_idx=$(eval "${cmd}" 3>&1 1>&2 2>&3)
    clear
    
    #echo "select id = $select_idx"
    if [[ "$select_idx" -eq "" ]]; then
        dst_option=""
    else
        dst_option="${disk_options[$select_idx-1]}"
    fi
    echo "$dst_option"
}

function get_rootfs_dev()
{
    echo $(findmnt --noheadings / | awk '{print $2}')
}

function get_diskPath()
{
    # /dev/sda1 => /dev/sda
    local _dev=$(echo "$1" | awk -F'[0-9]' '{print $1}')
    echo "$_dev"
}

function map_serial2dev()
{
    local serial=$1
    local dev=$(lsblk -o PATH,SERIAL | grep "$serial" | awk '{print $1}')
    echo "$dev"
}

function map_dev2serial()
{
    local dev=$1
    local serial=$(lsblk -o PATH,SERIAL | grep "$dev" | awk '{print $2}')
    echo "$serial"
}

function map_dev2uuid()
{
    local _dev=$1
    local _uuid=$(lsblk -o NAME,PARTUUID -n -p -l |grep "$_dev" |awk '{print $2}')
    echo $_uuid
}

function clean_usb_dpart()
{
    local dev=$1
    sudo dd if=/dev/zero of=$dev bs=512 count=1
}

function setup_usb_dpart()
{
    local dev=$1
    sudo umount -f "$dev"1
    sudo umount -f "$dev"2
    clean_usb_dpart "$dev"
    
    # do partition
    (
    echo n
    echo p
    echo 1
    echo 
    echo +2G
    echo n
    echo p
    echo 2
    echo 
    echo 
    echo w
    echo p
    ) | sudo fdisk $dev
    
    # format
    sudo mkfs.vfat -F32 "$dev$DPART_BOOT"
    sudo e2label "$dev$DPART_BOOT" "$LABEL_USB_BOOT"
    sudo mkfs.ext4 -F "$dev$DPART_STORAGE"
    sudo e2label "$dev$DPART_STORAGE" "$LABEL_USB_STORAGE"
}

function write_grub_cfg()
{
    tmp_path=$1
    echo 'set timeout=0' > $tmp_path
    echo 'set default=0' >> $tmp_path
    echo 'set isofile="/advUsbRescue.iso"' >> $tmp_path
    echo 'menuentry "AdvRescueUSB" {' >> $tmp_path
    echo 'insmod part_gpt' >> $tmp_path
    echo '' >> $tmp_path
    echo 'loopback loop $isofile' >> $tmp_path
    echo 'linux (loop)/vmlinuz boot=live quiet splash toram=filesystem.squashfs findiso=$isofile' >> $tmp_path
    echo 'initrd (loop)/initrd' >> $tmp_path
    echo '}' >> $tmp_path
}

function setup_usb_rescue()
{
    local dev=$1
    local iso_path=$2
    
    sudo mkdir $MPT_USB_BOOT
    sudo mount "$dev$DPART_BOOT" $MPT_USB_BOOT
    
    # grub-install
    sudo grub-install --target=x86_64-efi --efi-directory=$MPT_USB_BOOT --boot-directory=$MPT_USB_BOOT/boot --removable
    
    # set usb grub.cfg
    sudo mkdir -p $MPT_USB_BOOT/boot/grub
    write_grub_cfg "/tmp/usb_grub.cfg"
    sudo cp -f /tmp/usb_grub.cfg $MPT_USB_BOOT/boot/grub/grub.cfg
    
    # copy iso
    sudo cp -f $iso_path $MPT_USB_BOOT
    
    sudo umount $MPT_USB_BOOT
    sudo rm -rf $MPT_USB_BOOT
    rm -f /tmp/usb_grub.cfg
}

function get_boot_type()
{
    if [ -d "/sys/firmware/efi" ]; then
	echo "UEFI"
    else
	echo "Legacy"
    fi
}

function get_disk_sz_by_serial()
{
    local _serial=$1
    local drive_bytes=$(lsblk --bytes -o SERIAL,SIZE -l |grep $_serial |awk '{print $2}')
    echo $drive_bytes
}

function get_sys_dpart_info()
{
    local _all=$1
    local _serial=$2
    local _dev=$(lsblk -o SERIAL,PATH |grep $_serial |awk '{print $2}')
    local _dpart_dev
    #echo $_dev
    SYS_DPART=2
    for (( i=1; i<=$SYS_DPART; i++ ));
    do
        if [[ $_dev =~ "nvme" ]]; then
            _dpart_dev="${_dev}p${i}"
        else
            _dpart_dev="${_dev}${i}"
        fi
        local _fstype="$(lsblk -n -p -l -o FSTYPE $_dpart_dev)"
        local _dpart_size=$(lsblk -n --bytes -o SIZE -l $_dpart_dev)
        local _dpart_used=$(lsblk -n --bytes -o FSUSED -l $_dpart_dev)
        #echo "$_dpart_dev $_fstype $_dpart_size $_dpart_used"
        local _dpart='{}'
        _dpart=$(js_setv "$_dpart" "partId" $i)
        _dpart=$(js_setv "$_dpart" "fs" "$_fstype")
        _dpart=$(js_setv "$_dpart" "bytes" "$_dpart_size")
        _dpart=$(js_setv "$_dpart" "fused" "$_dpart_used")

        _all=$(echo $_all | jq --argjson new_m "$_dpart" '.img_desc.partlist += [$new_m]')
    done
    echo $_all
}

function new_mission()
{
    local input=$1
    local mission=$2
    local type=$3
    local serial=$4
    local path=$5
    local uuid=$6
    local date=$(date +"%Y-%m-%d %H:%M:%S")
    local -i drive_bytes=$(get_disk_sz_by_serial "$serial")
    local osVersion=$(lsb_release -d |sed 's/Description:\t//g')
    local bootOpt=$(get_boot_type)
    #echo "drive_bytes $drive_bytes"

    _data=$(js_setv "$input" "mission" "$mission")
    _data=$(js_setv "$_data" "type" "$type")
    _data=$(js_setv "$_data" "start_ts" "$date")
    _data=$(js_setv "$_data" "state" "Accept")
    _data=$(js_setv "$_data" "drive_bytes" $drive_bytes)
    _data=$(js_setv "$_data" "osVersion" "$osVersion")
    _data=$(js_setv "$_data" "bootOption" $bootOpt)

    _data=$(echo $_data | jq --arg v "$uuid" '.connect.uuid = $v')
    _data=$(echo $_data | jq --arg v "$path" '.connect.path = $v')
    _data=$(echo $_data | jq --arg k "$mission" --arg m "$serial" '. + { ($k): { "serial": $m } }')

    if [ "backup" == "$mission" ]; then 
        _data=$(get_sys_dpart_info "$_data" "$serial")
    fi

    echo $_data
}


### start ###
iso_path=$1

if [ ! $# -eq 1 ]; then
    echo "Err：Please input parameter"
    echo "Usage：$0 <iso_path> "
    exit 1
fi

# 1. get all usb devices and show list to select
usb_info=$(menu_select_device)
#echo "usb device: $usb_info"
if [[ "$usb_info" == "ERR:No USB device found" ]];then 
    echo "ERR:No USB device found"
    exit 0
fi

# 2. get dev by serial
usb_serial=$(echo "$usb_info" | cut -d':' -f2)
usb_dev=$(map_serial2dev "$usb_serial")
#usb_uuid=$(map_dev2uuid $usb_dev)
echo "usb_dev= $usb_dev"
#echo "usb_uuid= $usb_uuid"

if [[ ! $usb_dev =~ "/dev/sd" ]]; then
    exit 0
fi

# 3. format the usb, setup partitions:
setup_usb_dpart "$usb_dev"
usb_storage_uuid=$(map_dev2uuid $usb_dev$DPART_STORAGE)

# 4. grub install and copy iso files
setup_usb_rescue "$usb_dev" "$iso_path"

# 5. write mission config file - backup
disk=$(get_rootfs_dev)
disk_dev=$(get_diskPath "$disk")
disk_serial=$(map_dev2serial "$disk_dev")

basic_data=$(jq -n '{"version":"","mission":"","type":"","start_ts":"","state":"","connect":{"uuid":"","path":""},"img_desc":{"partlist":[]}}')
new_data=$(new_mission "$basic_data" "backup" "local" "$disk_serial" "/" "$usb_storage_uuid")
echo "$new_data" | jq .

sudo mkdir $MPT_USB_STORAGE
sudo mount "$usb_dev$DPART_STORAGE" $MPT_USB_STORAGE

echo "$new_data" | jq . > $PATH_MISSION

sudo umount $MPT_USB_STORAGE
sudo rm -rf $MPT_USB_STORAGE
#sudo -u $USER echo $new_data > $PATH_MISSION
