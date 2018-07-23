#!/bin/bash

TOPDIR=/gpfs/fs0/datasets
TGTOWNER=hchiang2
TGTGROUP=lsst_users
#perms and types are octal (see "man -S2 stat")
TGTPERMS_FILE=0644
TGTPERMS_DIR=0755
VALID_FILETYPES=( 0120000 0100000 )
VALID_DIRTYPES=( 0040000 )

DIRLIST=$(mktemp)
FILELIST=$(mktemp)
MMCHATTR='/usr/lpp/mmfs/bin/mmchattr -l'
MMLSATTR='/usr/lpp/mmfs/bin/mmlsattr -l'
PARALLEL=$( which parallel )
DEBUG=0
TGTPATH=


cleanup() {
    rm -f $DIRLIST $FILELIST
}


cleanexit() {
    cleanup
    exit 0
}


croak() {
    echo "ERROR (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    cleanup
    exit 99
}


warn() {
    if [[ $DEBUG -eq 1 ]] ; then
        echo "WARN (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    else
        echo "WARN $*"
    fi
}


log() {
    if [[ $DEBUG -eq 1 ]] ; then
        echo "INFO (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    else
        echo "INFO $*"
    fi
}


debug() {
    [[ $DEBUG -ne 1 ]] && return
    echo "DEBUG (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
}


continue_or_exit() {
    local msg="Continue?"
    [[ -n "$1" ]] && msg="$1"
    echo "$msg"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) return 0;;
            No ) cleanexit;;
        esac
    done
}


assert_root() {
    debug "enter..."
    [[ $EUID -eq 0 ]] || croak 'Must be root'
}


assert_dependencies() {
    [[ -s "$PARALLEL" ]] || croak "Missing dependency: 'parallel'"
    [[ -x "$PARALLEL" ]] || croak "Not executable: '$PARALLEL'"
    $PARALLEL --version | head -1 | grep -q 'GNU parallel' \
    || croak "Missing dependency: 'gnu parallel'"
}


scan_filesystem() {
    # Save a list of files and another of dirs
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    find "$TGTPATH" -type d -print0 \
    | tee $DIRLIST \
    | $PARALLEL -0 'find {} -mindepth 1 -maxdepth 1 ! -type d' >$FILELIST
}


_find_type_mode_mismatches() {
    # find files not matching mode (type or perms) or user
    # All paramters passed by reference
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 3 arguments, got '$#'"
    local -a types=("${!1}")
    local perms="${!2}"
    local infile="${!3}"

    local -a valid_patterns
    for typ in "${types[@]}"; do
        #create mode in hex (as returned by stat)
        mode=$( printf '%x' $(( 0"$typ" + 0"$perms" )) )
        valid_patterns+=( '-e' "$mode $TGTOWNER $TGTGROUP" )
    done

    # check items in filelist
    <$infile $PARALLEL -0 "stat -c '%f %U %G %n' {}" \
    | grep -v -F "${valid_patterns[@]}" 
}


_find_lock_mismatches() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"
}


count_file_mismatches() {
    _find_type_mode_mismatches VALID_FILETYPES[@] TGTPERMS_FILE FILELIST \
    | wc -l
}


count_dir_mismatches() {
    _find_type_mode_mismatches VALID_DIRTYPES[@] TGTPERMS_DIR DIRLIST \
    | wc -l
}








#set_perms() {
#    debug "enter..."
#    local action=time
#    [[ $DEBUG -eq 1 ]] && { 
#        set -x
#        action=echo
#    }
#    log "Setting directory permissions..."
#    $action find "$TGTPATH" -type d -exec chmod $TGTPERMS_DIR {} \;
#    log "Setting file permissions..."
#    $action find "$TGTPATH" -type f -exec chmod $TGTPERMS_FILE {} \;
#    log "Setting group ownership..."
#    $action find "$TGTPATH" -exec chgrp "$TGTGROUP" {} \;
#    log "Setting owner..."
#    $action find "$TGTPATH" -exec chown "$TGTOWNER" {} \;
#    log "OK"
#}


#count_mode_mismatches() {
#    # Count number of objects NOT matching expected mode
#    debug "enter..."
#    [[ $DEBUG -eq 1 ]] && set -x
#    [[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"
#    local ftype
#    case $1 in
#        files)
#            ftype=f
#            tgtmode=$TGTPERMS_FILE
#            ;;
#        dirs)
#            ftype=d
#            tgtmode=$TGTPERMS_DIR
#            ;;
#        *) croak "Invalid file type: '$1'"
#    esac
#    find "$TGTPATH" -type $ftype ! -perm -$tgtmode -printf '\n' \
#    | wc -l
#}


#count_ownership_mismatches() {
#    # Count number of objects NOT matching expected ownership
#    debug "enter..."
#    [[ $DEBUG -eq 1 ]] && set -x
#    find "$TGTPATH" ! -user $TGTOWNER -printf '\n' -or ! -group $TGTGROUP -printf '\n' \
#    | wc -l
#}


count_is_locked() {
    # Report number of objects matching requested parameters
    # Params: 1 = yes | no
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 1 arguments, got '$#'"
    local yesno
    case "$1" in
        yes|no) yesno="$1";;
        *) croak "Invalid input; must be 'yes' or 'no'"
    esac
    $PARALLEL -0 -a $DIRLIST -a $FILELIST \
        "$MMLSATTR -d -L {} | grep immutable" \
    | grep $yesno \
    | wc -l
}


#set_immutable() {
#    debug "enter..."
#    log "Adjust immutable flag, target immutable state: $1"
#    local delta
#    local action=time
#    [[ $DEBUG -eq 1 ]] && { 
#        set -x
#        action=echo
#    }
#    case $1 in
#        yes|no) delta=$1 ;;
#             *) croak "Invalid value, '$delta', for delta" ;;
#    esac
#    $action find "$TGTPATH" -type d -exec $MMCHATTR -i $1 {} \;
#    log "OK"
#}


status_report() {
    debug "enter..."
    echo "Status report for '$TGTPATH'"
    echo "Note: A directory tree is properly marked immutable when all values below are 0"
    echo "File mismatches: $( count_file_mismatches )"
    echo "Dir mismatches:  $( count_dir_mismatches )"
    echo "Mutable Inodes:  $( count_is_locked no )"
}


process_cmdline() {
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


usage() {
    local prg=$(basename $0)
    cat <<ENDHERE

Usage: $prg [options] <path/to/directory>

Options:
    -h   Print this help message
    -d   Run in debug mode (lots of output)

Controlling operation:
    -l   Lock    Add "immutable" flag on the specified directory and all sub-directories
    -u   UnLock  Remove "immutable" flag from the specified directory and all sub-directories
    -s   Status  Report mutability status of the specified directory
                 Also checks permissions and ownership

Note: It is valid to provide '-s' in conjuction with one of the other operations,
      which will automatically run a "status report" after the initial operation
      is complete.

ENDHERE
}


# Process options
operations=()
while getopts ":hlusd" opt; do
    case $opt in
        h)
            usage; cleanexit
            ;;
        l)
            operations+=( LOCK )
            ;;
        u)
            operations+=( UNLOCK )
            ;;
        s)
            operations+=( STATUS )
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
for op in "${operations[@]}"; do
    case $op in
        LOCK)
            set_perms
            set_immutable yes
            ;;
        UNLOCK)
            set_immutable no
            ;;
        STATUS)
            status_report
            ;;
        *)
            echo "No action specified."
            ;;
    esac
    echo; echo
done

cleanup
