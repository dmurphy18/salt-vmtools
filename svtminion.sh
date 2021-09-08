#!/usr/bin/bash

## Salt VTtools Integration script
##  integration with Component Manager and GuestStore Helper

## Currently this script leverages the Salt Tiamat based SingleBinary Linux salt-minion
## TBD to leverage the Salt Tiamat based OneDir Linux salt-minion, once it is available

## set -u
## set -xT
set -o functrace
set -o pipefail
## set -o errexit

# using bash for now
# run this script as root, as needed to run salt

SCRIPT_VERSION='2021.09.07.01'

# definitions

## TBD these definitions will parse repo.json for 'latest' and download that when available
## these value in use for poc

## Repository locations and naming
readonly salt_name="salt"
readonly salt_pkg_name="salt-3003-3-linux-amd64.tar.gz"
readonly base_url="https://repo.saltproject.io/salt/singlebin"
readonly salt_url="${base_url}/3003/${salt_pkg_name}"
readonly salt_url_chksum="${base_url}/3003/salt-3003_SHA3_512"

# Salt file and directory locations
readonly base_salt_location="/opt/saltstack"
readonly salt_dir="${base_salt_location}/salt"
readonly test_exists_file="${salt_dir}/${salt_name}"
readonly salt_conf_dir="/etc/salt"
readonly salt_minion_conf_name="minion"
readonly salt_minion_conf_file="${salt_conf_dir}/${salt_minion_conf_name}"

readonly list_file_dirs_to_remove="${base_salt_location}
/etc/salt
/var/run/salt
/var/cache/salt
/var/log/salt
/etc/init.d/salt*
/usr/lib/systemd/system/salt*.service
"

## VMware file and directory locations
readonly vmtools_base_dir_etc="/etc/vmware-tools"
readonly vmtools_conf_file="tools.conf"
readonly vmtools_salt_minion_section_name="salt_minion"


## File manipulation File Descriptors
read_fd=3


## Component Manager Installer/Script return codes
# return Status codes
#  0 => installed
#  1 => installing
#  2 => notInstalled
#  3 => installFailed
#  4 => removing
#  5 => removeFailed
readonly STATUS_CODES=(installed installing notInstalled installFailed removing removeFailed)
scam=${#STATUS_CODES[@]}
for ((i=0; i<${scam}; i++)); do
    name=${STATUS_CODES[i]}
    declare -r ${name}=$i
done

STATUS_CHK=0
DEBUG_FLAG=0
DEPS_CHK=0
USAGE_HELP=0
LOG_MODE='debug'
INSTALL_FLAG=0
UNINSTALL_FLAG=0
VERBOSE_FLAG=0

# helper functions

_timestamp() {
    date "+%Y-%m-%d %H:%M:%S:"
}

_log() {
    echo "$1" | sed "s/^/$(_timestamp) /" >>"${LOGGING}"
}

# Both echo and log
_display() {
    if [[ ${VERBOSE_FLAG} -eq 1 ]]; then echo "$1"; fi
    _log "$1"
}

_ddebug() {
    if [[ ${DEBUG_FLAG} -eq 1 ]]; then
        echo "$1"
        _log "$1"
    fi
}

_error() {
    msg="ERROR: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
    echo "One or more errors found. See ${LOGGING} for details." 1>&2
    exit 1
}

_warning() {
    msg="WARNING: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
}

_yesno() {
read -p "Continue (y/n)?" choice
case "$choice" in
  y|Y ) echo "yes";;
  n|N ) echo "no";;
  * ) echo "invalid";;
esac
}


#
# _usage
#
#   Prints out help text
#
 _usage() {
     echo ""
     echo "usage: ${0}  [-c|--status] [-d|--debug] [-e|--depends]"
     echo "             [-h|--help] [-i|--install] [-r|--remove] [-v|--verbose]"
     echo ""
     echo "  -c, --status    return status for this script"
     echo "  -d, --debug     enable debugging logging"
     echo "  -e, --depend    check dependencies required to run this script exist"
     echo "  -h, --help      this message"
     echo "  -i, --install   install and activate the salt-minion"
     echo "  -r, --remove    deactivate and remove the salt-minion"
     echo "  -v, --verbose   enable verbose logging and messages"
     echo ""
     echo "  salt-minion vmtools integration script"
     echo "      example: $0 --status"
}


#
# _cleanup
#
#   Cleanups any running process and areas on exit or control-C
#
# Side Effects:
#   CURRENT_STATUS updated
#

_cleanup() {
    # clean up any items if die and burn
    # don't know the worth of setting the current status, since script died
    if [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${installing}]} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installFailed}]}
    elif [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${removing}]} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${removeFailed}]}
        sleep 5
        svpid=$(_find_salt_pid)
        if [[ -z ${svpid} ]]; then
            if [[ ! -d ${base_salt_location} ]]; then
                CURRENT_STATUS=${STATUS_CODES[$notInstalled]}
            fi
        fi
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
    fi
}


## trap _cleanup INT TERM EXIT
trap _cleanup INT EXIT

## cheap trim relying on echo to convert tabs to spaces and all multiple spaces to a single space
## also gets rid of \ ' "
_trim() {
    echo "$1"
}

# work functions
#
# _fetch_vmtools_salt_minion_conf
#
#   Retrieve the configuration for salt-minion from vmtools configuration file
#
# Results:
#   Exits with new vmtools configuration file if none found
#   or salt-minion configuration file updated with configuration read from vmtools
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf() {
    # fetch the current configuration for section salt_minion
    # from vmtoolsd configuration file
    local retn=0
    if [[ ! -f "${vmtools_base_dir_etc}/${vmtools_conf_file}" ]]; then
        # conf file doesn't exist, create it
        echo "[${vmtools_salt_minion_section_name}]" > "${vmtools_base_dir_etc}/${vmtools_conf_file}"
        _warning "Creating empty configuration file ${vmtools_base_dir_etc}/${vmtools_conf_file}"
    else
        # need to extract configuration for salt-minion
        # find section name ${vmtools_salt_minion_section_name}
        # read configuration till next section, and output to salt-minion conf file

        local salt_config_flag=0
        while IFS= read -r line
        do
            line_value=$(_trim "${line}")
            if [[ -n ${line_value} ]]; then
                if [[ $(echo ${line_value} | grep '^\[')  ]]; then
                    if [[ ${salt_config_flag} -eq 1 ]]; then
                        # if new section after doing salt config, we are done
                        break;
                    fi
                    if [[ ${line_value} = "[${vmtools_salt_minion_section_name}]" ]]; then
                        # have section, get configuration values, set flag and
                        #  start fresh salt-minion configuration file
                        salt_config_flag=1
                        mkdir -p "${salt_conf_dir}"
                        echo "# Minion configuration file - created by vmtools salt script" > "${salt_minion_conf_file}"
                        echo "enable_fqdns_grains: False" >> "${salt_minion_conf_file}"
                    fi
                elif [[ ${salt_config_flag} -eq 1 ]]; then
                    # read config here ahead of section check , better logic flow
                    cfg_key=$(echo ${line} | cut -d '=' -f 1)
                    cfg_value=$(echo ${line} | cut -d '=' -f 2)
                    # appending to salt-minion configuration file since it
                    # should be new and no configuration set
                    echo "${cfg_key}: ${cfg_value}" >> "${salt_minion_conf_file}"
                else
                    echo "skipping line '${line}'"
                fi
            fi
        done < "${vmtools_base_dir_etc}/${vmtools_conf_file}"
    fi
    return ${retn}
}

#
# _fetch_salt_minion
#
#   Retrieve the salt-minion from Salt repository
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#

_fetch_salt_minion() {
    # fetch the current salt-minion into specified location
    # could check if alreasdy there but by always getting it
    # ensure we are not using stale versions
    local retn=0
    CURRENT_STATUS=${STATUS_CODES[${installing}]}
    mkdir -p ${salt_dir}
    cd ${salt_dir}
    curl -o "${salt_pkg_name}" -fsSL "${salt_url}"
    tar -xvzf ${salt_pkg_name}
    if [[ ! -f ${salt_name} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installFailed}]}
        retn=1
    fi
    CURRENT_STATUS=${STATUS_CODES[${installed}]}
    return ${retn}
}


#
# _find_salt_pid
#
#   finds the pid for the salt process
#
# Results:
#   Echos ${salt_pid} which could be empty '' if salt process not found
#

_find_salt_pid() {
    # find the pid for salt if active
    local salt_pid=$(ps -ef | grep -v 'grep' | grep salt | head -n 1 | awk -F " " '{print $2}')
    echo ${salt_pid}
}

## Note: main command functions use return , not echo

#
# _status_fn
#
#   discover and return the current status
#
#       0 => installed
#       1 => installing
#       2 => notInstalled
#       3 => installFailed
#       4 => removing
#       5 => removeFailed
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${CURRENT_STATUS}
#

_status_fn() {
    # return status
    if [[ ${CURRENT_STATUS} -eq  ${STATUS_CODES[${installing}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${installFailed}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${removing}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${removeFailed}]} ]]; then
        return ${CURRENT_STATUS}
    fi
    if [[ -f "${test_exists_file}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
    fi
    return ${CURRENT_STATUS}
}


#
# _deps_chk_fn
#
#   Check dependencies for using salt-minion
#
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#
_deps_chk_fn() {
    # return dependency check
    local retn==0
    if [[ -f "${test_exists_file}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
        retn=0
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
        retn=1
    fi
   return ${retn}
}


#
#  _install_fn
#
#   Executes scripts to install Salt from Salt repository
#   and start the salt-minion
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#

_install_fn () {
    # execute install of Salt minion
    _fetch_salt_minion
    local retn=$?

    # get configuration for salt-minion from tools.conf
    _fetch_vmtools_salt_minion_conf
    retn=$((${retn}|$?))
    if [[ ${retn} -eq 0 && -f "${test_exists_file}" ]]; then
        ## echo "_install_fn starting ${test_exists_file} minion in bg"
        ## $(nohup ${salt_dir}/${salt_name} "minion" &)
        retn=0
    fi
    return ${retn}
}


#
# _remove_installed_files_dirs
#
#   Removes all Salt files and directories that may be used
#

 _remove_installed_files_dirs() {
    for idx in "${list_file_dirs_to_remove}"; do
        rm -fR "${idx}"
    done
}


#
#  _uninstall_fn
#
#   Executes scripts to uninstall Salt from system
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#

_uninstall_fn () {
    # remove Salt minion
    local retn=0
    if [[ -f "${test_exists_file}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
        retn=1
    fi
    CURRENT_STATUS=${STATUS_CODES[${removing}]}
    svpid=$(_find_salt_pid)
    if [[ -n ${svpid} ]]; then
        kill ${svpid}
        ## given it a little time
        sleep 5
    fi
    svpid=$(_find_salt_pid)
    if [[ -n ${svpid} ]]; then
        CURRENT_STATUS=${STATUS_CODES[$removeFailed]}
        retn=1
    else
        _remove_installed_files_dirs
        CURRENT_STATUS=${STATUS_CODES[$notInstalled]}
    fi
    return ${retn}
}



################################### MAIN ####################################

# static definitions

CURRDIR=$(pwd)

# default status is notInstalled
CURRENT_STATUS=${STATUS_CODES[$notInstalled]}

## build designation tag used for auto builds is YearMontDayHourMinuteSecondMicrosecond aka jid
date_long=$(date +%Y%m%d%H%M%S%N)
curr_date="${date_long::-2}"

# set logging infomation
## want verbose while developing
LOGGING="/dev/null"
SCRIPTNAME=$(basename "$0")
log_file="/var/log/salt/$SCRIPTNAME-${curr_date}.log"

if [[ ${VERBOSE_FLAG} -ne 0 ]];then
    LOGGING="${log_file}"
else
    LOGGING="/dev/null"
fi


## need support at a minimum for the following:
## depends
## deploy
## remove
## check
##
## Optionals:
##   predeploy
##   postdeploy
##   preremove
##   postremove
##
## ##    -l | --log )  LOG_MODE="$2"; shift 2 ;;

while true; do
  case "$1" in
    -c | --status ) STATUS_CHK=1; shift ;;
    -d | --debug )  DEBUG_FLAG=1; shift ;;
    -e | --depends ) DEPS_CHK=1; shift ;;
    -h | --help ) USAGE_HELP=1; shift ;;
    -i | --install ) INSTALL_FLAG=1; shift ;;
    -r | --remove ) UNINSTALL_FLAG=1; shift ;;
    -v | --verbose ) VERBOSE_FLAG=1; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

## check if want help, display usage and exit
if [[ ${USAGE_HELP} -eq 1 ]]; then
  _usage
  exit 0
fi


##  MAIN BODY OF SCRIPT

_display "$SCRIPTNAME: autobuild started"

# check if salt-minion is installed
if [[ -f "${test_exists_file}" ]]; then CURRENT_STATUS=${STATUS_CODES[$notInstalled]}; fi
_ddebug "$SCRIPTNAME: CURRENT_STATUS on startup is ${CURRENT_STATUS}"

retn=0

if [[ ${STATUS_CHK} -eq 1 ]]; then
    _status_fn
    retn=$?
##    exit ${retn}
elif [[ ${DEPS_CHK} -eq 1 ]]; then
    _deps_chk_fn
    retn=$?
##    exit ${retn}
elif [[ ${INSTALL_FLAG} -eq 1 ]]; then
    _install_fn
    retn=$?
##    exit ${retn}
elif [[ ${UNINSTALL_FLAG} -eq 1 ]]; then
    _uninstall_fn
    retn=$?
##    exit ${retn}
else
    _usage
fi

# doing this until onedir and daemonization is available
# exit is by Cntl-C
echo "before loop CURRENT_STATUS on startup is ${CURRENT_STATUS}"

if [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${installed}]} ]]; then
    echo "main loop starting ${salt_dir}/${salt_name} minion in bg"
    $(nohup ${salt_dir}/${salt_name} "minion" &)
fi
while [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${installed}]} ]];
do
    echo "loop CURRENT_STATUS is '${CURRENT_STATUS}', code '${STATUS_CODES[${installed}]}'"
    sleep 5
    ## check
    svpid=$(_find_salt_pid)
    if [[ -z ${svpid} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${removeFailed}]}
        if [[ ! -d ${base_salt_location} ]]; then
            CURRENT_STATUS=${STATUS_CODES[$notInstalled]}
        fi
    fi
done

exit ${retn}
