#!/bin/bash

MPT="/mnt/storage"
MISSION_FILE=".rescue_mission.json"
LABEL_USB_STORAGE="advBackupU"
LABEL_USB_BOOT="advRescueU"

HEIGHT=15
WIDTH=40
BACKTITLE="Advantech"
TITLE="Advantech Rescue"
MENU="Choose Recovery Target Disk"

function get_disk_list()
{
    local ESEP="$1"
    local IFS=$'\n'
    local -a sata_list=($(lsblk -n -p -l -o TRAN,NAME |grep '/dev/sd*' |grep sata |awk '{print $2}'))
    local -a nvme_list=($(lsblk -n -p -l -o TRAN,NAME |grep -v 'p[0-9]*$' |grep '/dev/nvme[0-9]*n[0-9]*' |awk '{print $2}'))
    local -a list=("${sata_list[@]}" "${nvme_list[@]}")
    local -a options=()
    #echo "${list[@]}"
    
    # change path to model
    for ((i=0;i<${#list[@]};i++))
    do
        #echo "${list[$i]}"
        local model=$(lsblk -n -o MODEL ${list[$i]})
        local serial=$(lsblk -n -o SERIAL ${list[$i]})
        options+=("$model:$serial")
    done
    
    IFS="${ESEP}"
    echo "${options[*]}"
    #declare -p options
}

function menu_select_dst_device()
{
    ESEP=$'\a'
    IFS="${ESEP}"
    #get_disk_list "${ESEP}"
    local -a disk_options=( $(get_disk_list "${ESEP}") )
    #declare -p disk_options
    local cmd="dialog --clear --backtitle \"$BACKTITLE\" --title \"$TITLE\" --menu \"$MENU\" $HEIGHT $WIDTH ${#disk_options[@]}"
    local dst_option=""
    
    for ((i=0; i<${#disk_options[@]}; i++));
    do
        cmd="${cmd} $((i+1)) '${disk_options[i]}'"
    done
        
    #declare -p cmd
    select_idx=$(eval "${cmd}" 3>&1 1>&2 2>&3)
    #clear
    
    #echo "select id = $select_idx"
    if [[ $select_idx -eq "" ]]; then
        dst_option=""
    else
        dst_option="${disk_options[$select_idx-1]}"
    fi
    echo "$dst_option"
}

function menu_select_src_device()
{
    # Src usb uuid determine at deploy time
    echo ""
}

function update_mission_conf()
{
    # get mission conf
    usb_dev=$(lsblk -n -p -l -o PATH,LABEL /dev/sd* |grep "$LABEL_USB_STORAGE" |awk '{print $1}')
    #echo "usb_dev: $usb_dev"
    mount $usb_dev $MPT
    local mission_conf=$(cat $MPT/$MISSION_FILE)
    
    #echo "$mission_conf"
    # update dst serial/model
    local dst_info="$1"
    echo " $dst_info"
    local serial=$(echo "$dst_info" | awk -F':' '{print $2}')
    local model=$(echo "$dst_info" | awk -F':' '{print $1}')
    
    echo "model: $model"
    echo "serial: $serial"
    
    mission_conf=$(echo $mission_conf | jq  --arg v "$model" '.restore.model = $v')
    mission_conf=$(echo $mission_conf | jq  --arg v "$serial" '.restore.serial = $v')
    
    echo $mission_conf > $MPT/$MISSION_FILE
}


mkdir $MPT
# 1. Select Dst device(disk)
#menu_select_dst_device
dst_info=$(menu_select_dst_device)
echo "dst device: $dst_info"

if [[ $dst_info -eq "" ]]; then 
    echo "user cancel, reboot system in 3 seconds..."
    sleep 3
    reboot
fi

# 2. Select Src device(usb) => Src usb uuid determine at deploy time
#menu_select_src_device

# 3. fill mission conf file
update_mission_conf "$dst_info"

# 5. rescue mission start (do advRescue.sh)
/root/advUsbRescue.sh
