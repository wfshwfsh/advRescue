#!/bin/bash

function is_integer()
{
    local var=$1
    if [[ "$var" =~ ^[0-9]+$ ]];then
	    #return 0 for integer
	    return 0
    else
	    return 1
    fi
}

# 
function js_getv()
{
	local _all=$1
	local _key=$2
	local _val=$(echo $_all | jq -r ".$_key")
	echo $_val
}

# modify exist key's value
function js_setv()
{
    local _all=$1
    local _key=$2
    local _new_val=$3
    if is_integer "$_new_val" ; then 
        local _data=$(echo "$_all" | jq --arg k "$_key" --arg v "$_new_val" '.[$k] = ($v|tonumber)')
    elif [[ "$_new_val" == "true" || "$_new_val" == "false" ]]; then
        local _data=$(echo "$_all" | jq --arg k "$_key" --argjson v "$_new_val" '.[$k] = $v')
    else
        local _data=$(echo $_all | jq --arg k "$_key" --arg v "$_new_val" '.[$k] = $v')
    fi
    #local _data=$(echo "$_all" | jq --arg k "$_key" --arg v ${_new_val} '.[$k] = ($v|tonumber)')
    echo $_data
}

# 
function js_setObj()
{
	local _all=$1
	local _o_key=$2
	local _o_val=$3
	local _data=$(echo $_all | jq --argjson v "$_o_val" --arg k "$_o_key" '.[$k] = $v')
	echo $_data
}

#
function js_addObj()
{
    local _all=$1
    local _o_key=$2
    local _o_val=$3
    #local _data=$(echo $_all | jq ". += {$_o_key: $_o_val}")
    local _data=$(echo $_all | jq ". += {\"$_o_key\": \"$_o_val\"}")
    echo $_data
}

# 
function js_delObj()
{
	local _all=$1
	local _key=$2
	local _data=$(echo $_all | jq "del(.$_key)")
	echo $_data
}

#
function js_getObj()
{
    local _all=$1
    local _key=$2
    local _data=$(echo $_all | jq ".$_key")
    echo $_data
}

#
function js_addStr2Array()
{
    local _all=$1
    local _arrayName=$2
    local _str=$3
    
    #local _data=$(echo $_all | jq ".$_arrayName += [{$_o_obj}]")
    local _data=$(echo "$_all" | jq ".${_arrayName} += [\"$_str\"]")
    echo $_data
}

#
function js_addObj2Array()
{
    local _all=$1
    local _arrayName=$2
    local _o_obj=$3
    
    #local _data=$(echo $_all | jq ".$_arrayName += [{$_o_obj}]")
    local _data=$(echo "$_all" | jq --argjson obj "$_o_obj" ".${_arrayName} += [\$obj]")
    echo $_data
}

