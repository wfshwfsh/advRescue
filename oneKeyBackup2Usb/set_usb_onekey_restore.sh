#!/bin/bash

source json_inc.sh

MPT_USB_BOOT="/mnt/USBBOOT"
MPT_USB_STORAGE="/mnt/USBSTORAGE"
MPT_TMP_STORAGE="/mnt/_storage"
LABEL_USB_STORAGE="advBackupU"
LABEL_USB_BOOT="advRescueU"

function get_advStorage_dev()
{
    local dev=$(lsblk -o PATH,LABEL | grep "$LABEL_USB_STORAGE" | awk '{print $1}')
    echo $dev
}

function map_dev2serial()
{
    local dev=$1
    local serial=$(lsblk -o PATH,SERIAL | grep "$dev" | awk '{print $2}')
    echo "$serial"
}

function set_rescue_mission()
{
    local serial=$1
    local imgPath=$2
    #local dev=$3
    
    #sudo mv $MPT_USB_STORAGE/advRescue_backup_result.json $MPT_USB_STORAGE/.rescue_mission.json
    sudo cp $MPT_USB_STORAGE/advRescue_backup_result.json $MPT_USB_STORAGE/.rescue_mission.json
    local mission_conf=$(cat $MPT_USB_STORAGE/.rescue_mission.json)
    #echo "$mission_conf"
    #local model=$(get_dev_model "$dev")
    local model=""
    local date=$(date +"%Y-%m-%d %H:%M:%S")
    #local uuid=$(get_usb_storage_uuid "$dev"2)
    mission_conf=$(js_setv "$mission_conf" "mission" "restore")
    mission_conf=$(js_setv "$mission_conf" "type" "usb")
    mission_conf=$(js_setv "$mission_conf" "start_ts" "$date")
    mission_conf=$(js_setv "$mission_conf" "state" "Accept")
    #mission_conf=$(echo $mission_conf | jq --arg v "$uuid" '.connect.uuid = $v')
    #mission_conf=$(echo $mission_conf | jq --arg v "$imgPath" '.connect.path = $v')
    mission_conf=$(js_delObj "$mission_conf" "finish_ts")
    mission_conf=$(js_delObj "$mission_conf" "backup")
    mission_conf=$(echo $mission_conf | jq  --arg v "$model" '.restore.model = $v')
    mission_conf=$(echo $mission_conf | jq  --arg v "$serial" '.restore.serial = $v')
    
    echo $mission_conf > $MPT_USB_STORAGE/.rescue_mission.json
}


### main ###
imgPath="/"
usb_devStorage=$(get_advStorage_dev)
echo "usb_devStorage: $usb_devStorage"

usb_serial=$(map_dev2serial "$usb_devStorage")
echo "usb_serial: $usb_serial"

sudo mkdir $MPT_USB_STORAGE
sudo mount "$usb_devStorage" $MPT_USB_STORAGE

set_rescue_mission "$usb_serial" "$MPT_USB_STORAGE$imgPath"

sudo umount $MPT_USB_STORAGE
sudo rm -rf $MPT_USB_STORAGE
