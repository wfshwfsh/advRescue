#!/bin/bash

source /root/json_inc.sh

### global Var ###
DEV_UBUNTU=""
MNT_UBUNTU="/mnt/ubuntu"
DEV_STORAGE=""
MPT="/mnt/storage"

CONF_PATH="$MNT_UBUNTU/var/tmp_adv"
CONF_FILE="$CONF_PATH/.rescue_mission.json"

RESULT_PATH="$MPT"
RESULT_FILE=""
LOG_PATH="$MPT"
LOG_FILE=""

TEST_ONLY=0

#
mission=""
type=""
start_ts=""
base64_mbr=""
base64_sfd=""

##############################
function disable_keys()
{
    dumpkeys | sed 's/keycode  29 = Control/keycode  29 = VoidSymbol/g; s/keycode  56 = Alt/keycode  56 = VoidSymbol/g' | sudo loadkeys
}

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

function mount_storage()
{
    local _json_conf=$1
    local _type=$type
    local _path=$(js_getv "$_json_conf" "connect.path")
    local _mount_cmd="" _err=""
    # disk 
    local _dpart_uuid="" _dev=""
    # network
    local _host="" _user="" _pswd=""
    
    case $_type in
        "local" | "usb" | "extDisk")
            # Search diskpart by UUID & mount
            _dpart_uuid=$(js_getv "$_json_conf" "connect.uuid")
            _dev=$(lsblk -o NAME,PARTUUID -n -p -l |grep "$_dpart_uuid" |awk '{print $1}')
            _err=$(mount $_dev $MPT)
            ;;
            
        "nfs")
            # Mount nfs server
            _host=$(js_getv($_json_conf, "connect.ip"))
            #_mount_cmd="mount $_host:$_path ".$MPT.' 2>&1'
            #_err=$(_mount_cmd)
            ;;
            
        "ssh" | "cifs" | "ftp")
            # TBD
            #_err=$(_mount_cmd)
            ;;
        
        *)
            _err="Err: unkown type ???"
            ;;
    esac
    
    #echo "$_err"> $LOG_FILE
    echo "$_err"
    #return 0
}

##### backup #####
function clean_exist_img_files()
{
    local _storage=$1
    if [ "$TEST_ONLY" -eq 1 ]; then
        echo "clean $_storage"
    else
        rm -f $_storage/en64_mbr.txt
        rm -f $_storage/en64_sfdata.txt
        rm -f $_storage/*.img
    fi
}

function fetch_mbr()
{
    local _storage=$1
    local _disk=$2
    echo "$_disk"
    
    if [ "$TEST_ONLY" -eq 1 ]; then
        echo "fetch $_disk mbr.bin"
    else
        dd if=$_disk of=/tmp/mbr.bin bs=32k count=1 &>> $LOG_FILE
        # Note: using tr -d '\n' to fix ctrl+j issue
        #cat /tmp/mbr.bin | base64 | tr -d '\n' > $_storage/en64_mbr.txt
        base64_mbr=$(cat /tmp/mbr.bin | base64 | tr -d '\n')
    fi
}

function fetch_sfd()
{
    local _storage=$1
    local _disk=$2
    
    if [ "$TEST_ONLY" -eq 1 ]; then
        echo "fetch $_disk sfdisk"
    else
        sfdisk --dump $_disk > /tmp/sfdata.txt
        # Note: using tr -d '\n' to fix ctrl+j issue
        #cat /tmp/sfdata.txt | base64 | tr -d '\n' > $_storage/en64_sfdata.txt
        base64_sfd=$(cat /tmp/sfdata.txt | base64 | tr -d '\n')
    fi
}

function compose_backup_cmd()
{
    local fmt=$1
    local disk=$2
    local partId=$3
    local storage_path=$4
    
    local source=""
    local fs_tool=$(get_fs_tool "$fmt")
    local fs_mode=""
    if [ "$fs_tool" != "dd" ]; then 
        fs_mode="--clone"
    fi
    
    local partclone_clone="partclone.$fs_tool $fs_mode --force --UI-fresh 1"
    local log="--logfile /tmp/$src_dev.log"
    
    if [[ $disk =~ "nvme" ]]; then
        source="--source ${disk}p${partId} --no_block_detail"
    else
        source="--source ${disk}${partId} --no_block_detail"
    fi
    local compress="pigz --stdout"
    local split="split --numeric-suffixes=1 --suffix-length=3 --additional-suffix=.img --bytes=4096M -"
    ##local date=`date +%Y%m%d`
    local name="diskpart$partId"_
    local output_path="$storage_path$name"

    local o_cmd="$partclone_clone $log $source | $compress | $split $output_path"

    #return string
    echo $o_cmd
}

function do_backup()
{
    local _json_conf=$1
    local _serial=$(js_getv "$_json_conf" "backup.serial")
    local _disk=$(lsblk -o NAME,SERIAL -n -p -l |grep "$_serial" |awk '{print $1}')
    
    LOG_FILE="${LOG_PATH}/adv_${mission}.log"
    # 1. mount backup disk
    local _err=$(mount_storage "$_json_conf")
    echo "mount $type: $_err"
    
    # 2. fetch disk partition header & info
    clean_exist_img_files "$MPT"
    fetch_mbr "$MPT" "$_disk"
    fetch_sfd "$MPT" "$_disk"
    
    # 3. partclone backup
    local _path=$(js_getv "$_json_conf" "connect.path")
    local _storage_path="$MPT$_path"
    local _nof_src_disk=$(echo "$_json_conf" | jq '.img_desc.partlist | length')

    echo "serial: $_serial"
    echo "disk: $_disk"
    echo "path: $_path"
    echo "storage_path: $_storage_path"
    echo "nof disk: $_nof_src_disk"

    for ((i = 0; i < $_nof_src_disk; i++));
    do
        local _obj_partlist=$(echo $_json_conf | jq -r ".img_desc.partlist[$i]")
        local _dpartId=$(echo $_obj_partlist | jq -r ".partId")
        local _fs=$(echo $_obj_partlist | jq -r ".fs")
        local _dpartSz=$(echo $_obj_partlist | jq -r ".bytes")
        local _dpartUsed=$(echo $_obj_partlist | jq -r ".fused")
        # TBD - extra info ???
        
        echo "diskpart[$_dpartId]: $_fs"
        cmd_backup=$(compose_backup_cmd "$_fs" "$_disk" "$_dpartId" "$_storage_path")
        if [ "$TEST_ONLY" -eq 1 ]; then
            echo $cmd_backup
        else
            eval $cmd_backup |& tee -a $LOG_FILE
        fi
    done
    
    umount $MPT
}

##### restore #####
function get_disk_sz_by_serial()
{
    local _serial=$1
    local -i _disk_sz=$(lsblk --bytes -o SERIAL,SIZE -l |grep "$_serial" |awk '{print $2}')
    echo $_disk_sz
}

function clear_mbr()
{
    local _disk=$1
    
    if [ "$TEST_ONLY" -eq 1 ]; then
        echo "clear_mbr $_disk"
    else
        wipefs --all --force $_disk &>> $LOG_FILE
    fi
}

function restore_mbr()
{
    #local _storage=$1
    local _base64_mbr=$1
    local _disk=$2

    if [ "$TEST_ONLY" -eq 1 ]; then
        #echo "_base64_mbr: $_base64_mbr"
        echo "restore $_disk to mbr.bin"
    else
        echo $_base64_mbr | base64 --decode > /tmp/en64_mbr.bin
        dd if=/tmp/en64_mbr.bin of=$_disk bs=32k count=1 &>> $LOG_FILE
    fi
}

function restore_sfd()
{
    #local _storage=$1
    local _base64_sfd=$1
    local _disk=$2
    local _type=$type
    local _xnof_src_disk=10
    
    if [ "$TEST_ONLY" -eq 1 ]; then
        #echo "_base64_sfd: $_base64_sfd"
        echo "restore sfdisk $_disk"
    else
        echo $_base64_sfd | base64 --decode > /tmp/sfdata.txt
        
        # remove disk partition in sfdata.txt => leave only system disk partition
        if [ "local" != $_type ]; then
            for ((i = 3; i <= $_xnof_src_disk; i++));
            do
                sed -i "\|${_disk}${i} :|d" /tmp/sfdata.txt
            done
        fi
        sfdisk --force $_disk < /tmp/sfdata.txt &>> $LOG_FILE
    fi
}

function update_diskpart()
{
    local _disk=$1
    
    if [ "$TEST_ONLY" -eq 1 ]; then
        echo "update_diskpart $_disk"
    else
        partprobe "$_disk"
    fi
}

function compose_restore_cmd()
{
    local fmt=$1
    local disk=$2
    local partId=$3
    local storage_path=$4
    
    local restore_opt=""
    local fs_tool=$(get_fs_tool "$fmt")
    
    local partclone_restore="partclone.$fs_tool --restore --force --UI-fresh 1"
    local log="--logfile /tmp/diskpart$partId.log"

    local decompress="pigz --decompress --stdout"
    if [[ $disk =~ "nvme" ]]; then
        restore_opt="--overwrite ${disk}p${partId} --no_block_detail"
    else
        restore_opt="--overwrite ${disk}${partId} --no_block_detail"
    fi

    #local date=`date +%Y%m%d`
    local name="diskpart$partId"_??*.img
    local image_path="$storage_path$name"
    #echo $image_path

    local o_cmd="cat $image_path | $decompress | $partclone_restore $log $restore_opt"

    #return string
    echo $o_cmd
}

function growpart()
{
    local _disk=$1
    mkdir /mnt/ubuntu
    mount ${_disk}2 /mnt/ubuntu
    mount -o bind /dev /mnt/ubuntu/dev
    mount -o bind /dev/pts /mnt/ubuntu/dev/pts
    mount -o bind /proc /mnt/ubuntu/proc
    mount -o bind /run /mnt/ubuntu/run
    mount -o bind /sys /mnt/ubuntu/sys
    #last partition num is 2(ubuntu disk partition)
    chroot /mnt/ubuntu /bin/sh -c "growpart $_disk 2"
    chroot /mnt/ubuntu /bin/sh -c "resize2fs ${_disk}2"
    
    # umount before leave    
    umount /mnt/ubuntu/dev/pts
    umount /mnt/ubuntu/dev
    umount /mnt/ubuntu/proc
    umount /mnt/ubuntu/run
    umount /mnt/ubuntu/sys
    
    umount /mnt/ubuntu
}

function do_restore()
{
    local _json_conf=$1
    local _type=$type
    local _serial=$(js_getv "$_json_conf" "restore.serial")
    local _disk=$(lsblk -o NAME,SERIAL -n -p -l |grep "$_serial" |awk '{print $1}')
    local -i _conf_drive_sz=$(js_getv "$_json_conf" "drive_bytes")
    local -i _disk_sz=$(get_disk_sz_by_serial "$_serial")

    echo "$_conf_drive_sz to $_disk_sz"
    if [ $_disk_sz -lt $_conf_drive_sz ]; then
        echo "Dest disk size Not enough, require $_conf_drive_sz bytes (only $_disk_sz)"
        exit 0
    fi
    
    LOG_FILE="${LOG_PATH}/adv_${mission}.log"
    # 1. mount restore disk
    local _err=$(mount_storage "$_json_conf")
    echo "mount $type: $_err"
    
    # 2. clear and write mbr, disk header
    clear_mbr "$_disk"
    local _bin_mbr=$(js_getv "$_json_conf" "mbr_bin")
    local _bin_sfd=$(js_getv "$_json_conf" "sfd_bin")
    restore_mbr "$_bin_mbr" "$_disk"
    sync
    restore_sfd "$_bin_sfd" "$_disk"
    sync
    update_diskpart "$_disk"
    sync
    
    # 3. partclone restore
    local _path=$(js_getv "$_json_conf" "connect.path")
    local _storage_path="$MPT$_path"
    local _nof_src_dpart=$(echo "$_json_conf" | jq '.img_desc.partlist | length')

    echo "serial: $_serial"
    echo "disk: $_disk"
    echo "path: $_path"
    echo "storage_path: $_storage_path"
    echo "nof diskpart: $_nof_src_dpart"
    
    for ((i = 0; i < $_nof_src_dpart; i++));
    do
        local _obj_partlist=$(echo $_json_conf | jq -r ".img_desc.partlist[$i]")
        local _dpartId=$(echo $_obj_partlist | jq -r ".partId")
        local _fs=$(echo $_obj_partlist | jq -r ".fs")
        local _dpartSz=$(echo $_obj_partlist | jq -r ".bytes")
        local _dpartUsed=$(echo $_obj_partlist | jq -r ".fused")
        # TBD - extra info ???
        
        echo "diskpart[$_dpartId]: $_fs"
        cmd_restore=$(compose_restore_cmd "$_fs" "$_disk" "$_dpartId" "$_storage_path")
        if [ "$TEST_ONLY" -eq 1 ]; then
            echo $cmd_restore
        else
            eval $cmd_restore |& tee -a $LOG_FILE
        fi
    done
    
    umount $MPT
    if [ "local" != $_type ]; then
        # grow last disk partition
        growpart "$_disk" &>> $LOG_FILE
    fi
}

##############################
function starting_dialog()
{
    clear
    local sel, wait_sec=3
    for ((i=$wait_sec;i>0;i--))
    do
        dialog --timeout 1 --ok-label "cancel" --title "Advantech" --msgbox "Rescue starts in $i seconds..." 10 50
        sel=$?
        if [ $sel -eq 0 ]; then
            break
        fi
    done
    clear
    return $sel
}

function get_mission()
{
    mkdir -p $MNT_UBUNTU
    
    # Search ubuntu rootfs diskpart
    DEV_UBUNTU="$(lsblk -o NAME,TYPE,LABEL -n -p -l |grep "rfs" |awk '{print $1}')"
    
    # Mount and Get mission.json data
    mount "$DEV_UBUNTU" "$MNT_UBUNTU"
    local _json_conf=$(cat $CONF_FILE)

    # Clean mission configure file
    rm -f $CONF_FILE
    umount $MNT_UBUNTU

    echo $_json_conf
}

function parse_mission()
{
    local json_conf=$1
    #echo $json_conf

    # get mission: "backup" or "restore"
    version=$(js_getv "$json_conf" "version")
    mission=$(js_getv "$json_conf" "mission")
    state=$(js_getv "$json_conf" "state")
    type=$(js_getv "$json_conf" "type")
    start_ts=$(js_getv "$json_conf" "start_ts")
    uuid=$(js_getv "$json_conf" "connect.uuid")
    DEV_STORAGE=$(lsblk -o NAME,PARTUUID -n -p -l |grep "$uuid" |awk '{print $1}')

    echo "Version: $version"
    echo "Mission: $mission"
    echo "State: $state"
    echo "Type: $type"
    echo "MPT Device: $DEV_STORAGE"
    
    # Checking Params
    if [ "restore" != "$mission" ] && [ "backup" != "$mission" ]; then
        #echo "Err: Unkown mission type"
        return -1
    elif [ "Accept" != "$state" ]; then
        #echo "Err: Invalid State DEV_STORAGE"
        return -2
    else
        return 0
    fi
}


function preHandle_mission()
{
    echo "# preHandle_mission"
    json_conf=$1
    # Disable Keyboard Specific key
    disable_keys

    mount $DEV_STORAGE $MPT
    local _result_file="$RESULT_PATH/advRescue_""$mission"_result.json
    
    # Update state
    local _update=$(js_setv "$json_conf" "state" "Processing")
    echo "$_update" > $_result_file
    
    umount $MPT
}

function Handle_mission()
{
    echo "# Handle_mission"
    json_conf=$1
    if [ "backup" == "$mission" ]; then
        do_backup "$json_conf"
    fi
    
    if [ "restore" == "$mission" ]; then
        do_restore "$json_conf"
    fi
}

function postHandle_mission()
{
    echo "# postHandle_mission"
    # Timestamp
    local _start_time=$1
    local _end_time=$2
    local _json_conf=$3
    local _errCode=$4
    local _errMsg=$5
    local _dur=$((_end_time - _start_time))
    local _sec_start_ts=$(date -d "$start_ts" +"%s")
    local _sec_finish_ts=$((_sec_start_ts + _dur))
    local _finish_ts=$(date -d "@$_sec_finish_ts" +"%Y-%m-%d %H:%M:%S")
    local _result_file="$RESULT_PATH/advRescue_""$mission"_result.json
    local _result_md5="$RESULT_PATH/advRescue_""$mission"_result.md5

    #echo "$_json_conf"
    local _update=$(echo "$_json_conf" | jq --arg v "$_finish_ts" '. + {"finish_ts": $v}')
    
    if [ 0 -eq $errCode ]; then
        _update=$(echo "$_update" | jq --arg k "state" --arg v "Done" '.[$k] = $v')
        
        # Adding mbr & sfdisk info
        #echo "base64_mbr: $base64_mbr"
        #echo "base64_sfd: $base64_sfd"
        _update=$(js_addObj "$_update" "mbr_bin" "$base64_mbr")
        _update=$(js_addObj "$_update" "sfd_bin" "$base64_sfd")
    else
        _update=$(echo "$_update" | jq --arg k "state" --arg v "Fail" '.[$k] = $v')
        _update=$(js_setv "$_update" "errcode" $errCode)
        _update=$(js_addObj "$_update" "errmsg" "$errMsg")
    fi
    
    if [ 255 -ne $errCode ] || [ "restore" == "$mission" ]; then
	mount $DEV_STORAGE $MPT
        echo "$_update" > $_result_file
	md5sum $_result_file > $_result_md5
	umount $MPT
    fi
}



### main start ###
errCode=0
#sleep 3
echo "=== rescue begin ==="
start_time=$(date +%s)

mkdir -p $MPT
# 1. get mission conf
json_conf=$(get_mission)
#echo "$json_conf"

# 2. parse mission
if [ 0 -eq $errCode ]; then
    parse_mission "$json_conf"
    errCode=$?
    if [ 0 -eq $errCode ]; then
        errMsg="parse mission failed"
    fi
fi

# 3. show dialog menu
starting_dialog
select=$?
if [ 0 -eq $select ]; then
    echo "User Canceled rescue, reboot in 3 seconds"
    sleep 3
    errCode=255
    errMsg="User Canceled"
fi

# 4.1 mount device
if [ 0 -eq $errCode ]; then
    preHandle_mission "$json_conf"
    errCode=$?
    if [ 0 -ne $errCode ]; then
        # Err: mount device failed
        errMsg="mount device failed"
    fi
fi

# 4.2 start backup/restore
if [ 0 -eq $errCode ]; then
    Handle_mission "$json_conf"
    errCode=$?
    if [ 0 -ne $errCode ]; then
        # Err: backup/restore failed
        errMsg="backup/restore failed"
    fi
fi

# 5. fill result descript file
end_time=$(date +%s)
postHandle_mission "$start_time" "$end_time" "$json_conf" $errCode "$errMsg"

echo "=== rescue end ==="
reboot
