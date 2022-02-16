#!/bin/bash
set -eufCo pipefail

readonly \
    SCRIPT=$(basename $(readlink -f "$0")) \
    EXIT_OK=0 \
    EXIT_WARNING=1 \
    EXIT_CRITICAL=2 \
    EXIT_UNKNOWN=3

declare \
    FLAG_HELP=0 \
    FLAG_DEVICE='' \
    DEVICE='' \
    WARNING_THRESHOLD=20 \
    CRITICAL_THRESHOLD=10


usage(){
    echo "
Usage:
    ${SCRIPT} -d device [-w limit] [-c limit]

Require:
    -d [device]    # Target block device

Optional:
    -w [limit]     # WARNING  threshold（default:20） 
    -c [limit]     # CRITICAL threshold（default:10） 

"
    return 3
}

raise() {
    echo ${1} 1>&2
    return 3
}

require_command() {
    local package cmd error
    required=0
    for string in $@ ;do
        package=${string%%:*}
        cmd=${string##*:}
        type ${cmd} &>/dev/null || { raise "${package} is required."; required=1; } ||:
    done
    [[ ${required} == 1 ]] && return 3
}

main() {
    require_command 'nvme-cli:nvme' 'jq:jq'

    opt_parse "$@"
    [[ ${FLAG_HELP} == 1 ]] && usage
    [[ ${FLAG_DEVICE} != 1 ]] && usage

    result_value=$(get_spare)
    result_msg="Available spare ${result_value} % |spare=${result_value};${WARNING_THRESHOLD};${CRITICAL_THRESHOLD};;"

    if [[ ${result_value} -le ${CRITICAL_THRESHOLD} ]] ;then
        echo "CRITICAL: ${result_msg}"
        exit ${EXIT_CRITICAL}
    elif [[ ${result_value} -le ${WARNING_THRESHOLD} ]] ;then
        echo "WARNING: ${result_msg}"
        exit ${EXIT_WARNING}
    elif [[ ${result_value} -le 100 ]] ;then
        echo "OK: ${result_msg}"
        exit ${EXIT_OK}
    else
        echo "UNKNOWN: ${result_msg}"
        exit ${EXIT_UNKNOWN}
    fi
}

opt_parse(){
    local opt
    opt=$(getopt -o 'h,d:,w:,c:' -l 'help' -- "$@")
    eval set -- "${opt}"

    while true ;do
        case "${1}" in
            -h | --help )
                FLAG_HELP=1
                ;;
            -d )
                if [ -z "$2" ] || [[ "$2" =~ ^-+ ]] ;then
                    raise "$1 : is required 1 argument."
                fi
                FLAG_DEVICE=1
                DEVICE=$2
                shift
                ;;
            -w )
                if [ -z "$2" ] || [[ "$2" =~ ^-+ ]] ;then
                    raise "$1 : is required 1 argument."
                fi
                WARNING_THRESHOLD=$2
                shift
                ;;
            -c )
                if [ -z "$2" ] || [[ "$2" =~ ^-+ ]] ;then
                    raise "$1 : is required 1 argument."
                fi
                CRITICAL_THRESHOLD=$2
                shift
                ;;
            -- )
                shift
                break
                ;;
            * )
                if [[ ! -z "$1" ]] && [[ ! "$1" =~ ^-+ ]] ;then
                    shift
                elif [[ -z "$1" ]] ;then
                    return
                else
                    raise "The option ${1} does not exist."
                fi
                ;;
        esac
        shift
    done
}

get_spare() {
    nvme smart-log -o json ${DEVICE} |
        jq '.avail_spare'
}

main "$@"

