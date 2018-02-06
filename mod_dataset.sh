#!/bin/bash

#TOPDIR=/datasets
TOPDIR=/gpfs/fs0/datasets
TGTOWNER=hchiang2
TGTGROUP=lsst_users
TGTMODE_FILE=0644
TGTMODE_DIR=0755
MMCHATTR='/usr/lpp/mmfs/bin/mmchattr -l'
MMLSATTR='/usr/lpp/mmfs/bin/mmlsattr -l'
PARALLEL=$( which parallel )
DEBUG=0
TGTPATH=


function croak {
    echo "ERROR (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    exit 99
}


function log() {
    if [[ $DEBUG -eq 1 ]] ; then
        echo "INFO (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    else
        echo "INFO $*"
    fi
}


function debug() {
    [[ $DEBUG -ne 1 ]] && return
    echo "DEBUG (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
}


function continue_or_exit() {
    local msg="Continue?"
    [[ -n "$1" ]] && msg="$1"
    echo "$msg"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) return 0;;
            No ) exit 1;;
        esac
    done
}


function assert_root() {
    debug "enter..."
    [[ $EUID -eq 0 ]] || croak 'Must be root'
}


function assert_dependencies() {
    [[ -s "$PARALLEL" ]] || croak "Missing dependency: 'parallel'"
    [[ -x "$PARALLEL" ]] || croak "Not executable: '$PARALLEL'"
    $PARALLEL --version | head -1 | grep -q 'GNU parallel' \
    || croak "Missing dependency: 'gnu parallel'"
}


function set_perms() {
    debug "enter..."
    local action=time
    [[ $DEBUG -eq 1 ]] && { 
        set -x
        action=echo
    }
    log "Setting directory permissions..."
    $action find "$TGTPATH" -type d -exec chmod $TGTMODE_DIR {} \;
    log "Setting file permissions..."
    $action find "$TGTPATH" -type f -exec chmod $TGTMODE_FILE {} \;
    log "Setting group ownership..."
    $action find "$TGTPATH" -exec chgrp "$TGTGROUP" {} \;
    log "Setting owner..."
    $action find "$TGTPATH" -exec chown "$TGTOWNER" {} \;
    log "OK"
}


function count_mode_mismatches() {
    # Count number of objects NOT matching expected mode
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"
    local ftype
    case $1 in
        files)
            ftype=f
            tgtmode=$TGTMODE_FILE
            ;;
        dirs)
            ftype=d
            tgtmode=$TGTMODE_DIR
            ;;
        *) croak "Invalid file type: '$1'"
    esac
    find "$TGTPATH" -type $ftype ! -perm -$tgtmode -printf '\n' \
    | wc -l
}


function count_ownership_mismatches() {
    # Count number of objects NOT matching expected ownership
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    find "$TGTPATH" ! -user $TGTOWNER -printf '\n' -or ! -group $TGTGROUP -printf '\n' \
    | wc -l
}


function count_is_locked() {
    # Report number of objects matching requested parameters
    # Params: 1 = yes | no
    #         2 = dirs | files
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 2 ]] && croak "Expected 2 arguments, got '$#'"
    local ftype yesno
    case $1 in
        yes|no) yesno=$1;;
        *) croak "Invalid input; must be 'yes' or 'no'"
    esac
    case $2 in
        files) ftype=f;;
        dirs)  ftype=d;;
        *) croak "Invalid file type: '$1'"
    esac
    find "$TGTPATH" -type $ftype -print \
    | parallel "$MMLSATTR -d -L {} | grep immutable" \
    | grep $yesno \
    | wc -l
}


function set_immutable() {
    debug "enter..."
    log "Adjust immutable flag, target immutable state: $1"
    local delta
    local action=time
    [[ $DEBUG -eq 1 ]] && { 
        set -x
        action=echo
    }
    case $1 in
        yes|no) delta=$1 ;;
             *) croak "Invalid value, '$delta', for delta" ;;
    esac
    $action find "$TGTPATH" -type d -exec $MMCHATTR -i $1 {} \;
    log "OK"
}


function status_report() {
    debug "enter..."
    echo "Status report for '$TGTPATH'"
    echo "Note: A directory tree is properly marked immutable when all values below are 0"
    echo "File mode mismatches: $( count_mode_mismatches files )"
    echo "Dir mode mismatches:  $( count_mode_mismatches 'dirs' )"
    echo "Ownership mismatches: $( count_ownership_mismatches )"
    echo "Immutable files:      $( count_is_locked yes files )"
    echo "Mutable dirs:         $( count_is_locked no 'dirs' )"
}


function process_cmdline() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"
    local rawpath="$1"
    #Validate input
    log "Input path: '$rawpath'"
    TGTPATH=$( readlink -e $rawpath )
    log "Canonical path: '$TGTPATH'"
    [[ $TGTPATH == $TOPDIR/* ]] || croak "Not part of Datasets: '$TGTPATH'"
    [[ -d $TGTPATH ]] || croak "Not a directory: '$TGTPATH'"
}


# Process options
operation=
while getopts ":lusd" opt; do
    case $opt in
        l)
            operation=LOCK
            ;;
        u)
            operation=UNLOCK
            ;;
        s)
            operation=STATUS
            ;;
        d)
            DEBUG=1
            ;;
        \?)
            croak "Invalid option: -$OPTARG"
            ;;
        :)
            croak "Option -$OPTARG requires an argument."
            ;;
        esac
    done
shift $((OPTIND-1))

assert_root
assert_dependencies
process_cmdline $*
case $operation in
    LOCK)
        set_perms
        set_immutable yes
        echo; echo
        ;;
    UNLOCK)
        set_immutable no
        echo; echo
        ;;
    STATUS)
        true
        ;;
    *)
        echo "No action specified. Setting default action to 'STATUS'. Continue?"
        continue_or_exit
        ;;
esac
status_report
