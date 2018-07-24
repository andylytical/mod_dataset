#!/bin/bash

#TOPDIR=/lsst/datasets
TOPDIR=/lsst
#TGTOWNER=hchiang2
#TGTGROUP=lsst_users
TGTOWNER=aloftus
TGTGROUP=grp_202
#perms are octal, suitable for chmod and stat (see "man -S2 stat")
TGTPERMS_FILE=0644
TGTPERMS_DIR=0755

MMCHATTR='/usr/lpp/mmfs/bin/mmchattr -l'
MMLSATTR='/usr/lpp/mmfs/bin/mmlsattr -l'
PARALLEL=$( which parallel )
TGTPATH=

declare -A TMPFILES=
declare -A TIME

tmpfn() {
    # Get or create tempfile matching keyword
    [[ $# -eq 1 ]] || croak "Expected 1 paramter, got $#"
    [[ ${TMPFILES[$1]+_} ]] || TMPFILES[$1]=$(mktemp tmp."$1".XXXXXXXX)
    echo ${TMPFILES[$1]}
}

cleanup() {
    if [[ $DEBUG -eq 1 ]] ; then
        set +x
        echo "TMPFILES:"
        for k in "${!TMPFILES[@]}"; do echo "$k ... ${TMPFILES[$k]}"; done
    else
        rm -f "${TMPFILES[@]}"
    fi
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
    elif [[ $VERBOSE -eq 1 ]] ; then
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


assert_valid_path() {
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


scan_filesystem() {
    # Save a list of dirs, a list of files, a list of symlinks and a list of other
    # Lists of dirs and of files will be used for immutability set/check
    # Lists of symlinks are ignored (can't be set immutable nor changed once dir
    # is immutable)
    # Lists of other file types is an error if non-empty
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Scanning filesystem at $TGTPATH ..."
    #initialize tmp files
    tmpfn DIRS &>/dev/null
    tmpfn FILES &>/dev/null
    tmpfn OTHERS &>/dev/null
    local start=$SECONDS
    find "$TGTPATH" \
           -type d -fprint0 $(tmpfn DIRS) \
        -o -type f -fprint0 $(tmpfn FILES) \
        -o -type l -fprint0 /dev/null \
        -o         -fprint  $(tmpfn OTHERS)
    local end=$SECONDS
    TIME[SCAN_FILESYSTEM]=$(bc <<< "$end - $start")
    debug "check for errors"
    if [[ -s $(tmpfn OTHERS) ]] ; then
        local tmp=$(mktemp)
        mv $(tmpfn OTHERS) $tmp
        warn "Only regular and symbolic link filetypes are allowed."
        croak "Invalid filetypes found: list in '$tmp'"
    fi
    log "Filesystem scan completed in ${TIME[SCAN_FILESYSTEM]} seconds"
}


count_mode_mismatches() {
    # find files not matching mode (type + perms) + user + group
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Count mode mismatches..."
    #initialize new tmp files
    tmpfn mode_mismatches &>/dev/null
    local filemode=$( printf '%x' $(( 0100000 + 0$TGTPERMS_FILE )) )
    local dirmode=$( printf '%x' $(( 0040000 + 0$TGTPERMS_DIR )) )
    local -a valid_patterns
    for mode in "$filemode" "$dirmode"; do
        valid_patterns+=( '-e' "$mode $TGTOWNER $TGTGROUP" )
    done
    # check all items in filelist
    local start=$SECONDS
    cat $(tmpfn FILES) $(tmpfn DIRS) \
    | $PARALLEL -0 "stat -c '%f %U %G %n' {}" \
    | grep -v -F "${valid_patterns[@]}" >$(tmpfn mode_mismatches)
    local end=$SECONDS
    TIME[COUNT_MODE_MISMATCHES]=$(bc <<< "$end - $start")
    log "Count mode mismatches completed in ${TIME[COUNT_MODE_MISMATCHES]} seconds"
}


count_locked_unlocked() {
    # Report number of objects matching requested parameters
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Count (un)locked files..."
    tmpfn locked &>/dev/null
    tmpfn unlocked &>/dev/null
    local start=$SECONDS
    cat $(tmpfn FILES) $(tmpfn DIRS) \
    | $PARALLEL -0 "$MMLSATTR -d -L {} | grep immutable" \
    | tee >(grep -F 'yes' >$(tmpfn locked)) \
    | grep -F 'no' >$(tmpfn unlocked)
    local end=$SECONDS
    TIME[COUNT_LOCKED_UNLOCKED]=$(bc <<< "$end - $start")
    log "Count (un)locked files completed in ${TIME[COUNT_LOCKED_UNLOCKED]} seconds"
}


set_perms() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    log "Setting permissions, owner, group ..."
    $PARALLEL -0 -a $(tmpfn DIRS) "chmod $TGTPERMS_DIR {}; chown ${TGTOWNER}:${TGTGROUP} {}"
    $PARALLEL -0 -a $(tmpfn FILES) "chmod $TGTPERMS_FILE {}; chown ${TGTOWNER}:${TGTGROUP} {}"
    local end=$SECONDS
    TIME[SET_PERMS]=$(bc <<< "$end - $start")
    log "Set permissions, owner, group completed in ${TIME[SET_PERMS]} seconds"
}


_set_immutable() {
    debug "enter..."
    local delta
    [[ $DEBUG -eq 1 ]] && set -x
    case $1 in
        yes|no) delta=$1 ;;
             *) croak "Invalid value, '$delta', for delta" ;;
    esac
    cat $(tmpfn DIRS) $(tmpfn FILES) \
    | $PARALLEL -0 "$MMCHATTR -i $1"
}


lock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Locking files..."
    local start=$SECONDS
    _set_immutable yes
    local end=$SECONDS
    TIME[LOCK]=$(bc <<< "$end - $start")
    log "Locking files completed in ${TIME[LOCK]} seconds"
}


unlock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Unlocking files..."
    local start=$SECONDS
    _set_immutable no
    local end=$SECONDS
    TIME[UNLOCK]=$(bc <<< "$end - $start")
    log "Unlocking files completed in ${TIME[UNLOCK]} seconds"
}


status_report() {
    debug "enter..."
    count_mode_mismatches
    count_locked_unlocked
    local mmcount=$( wc -l $(tmpfn mode_mismatches) | cut -d' ' -f1 )
    local lcount=$( wc -l $(tmpfn locked) | cut -d' ' -f1 )
    local uncount=$( wc -l $(tmpfn unlocked) | cut -d' ' -f1 )
    echo
    echo "Status report for '$TGTPATH'"
    echo "Note: mode mismatches are dirs/files without expected user, group or permissions."
    printf "% 8d Mode mismatches\n" $mmcount
    printf "% 8d Locked inodes\n"   $lcount
    printf "% 8d Unlocked inodes\n" $uncount
}


time_report() {
    debug "enter..."
    set +x
    local total=0
    echo "Elapsed Time Report:"
    for key in "${!TIME[@]}"; do 
        val=${TIME[$key]}
        printf "% 8d %s\n" $val $key
        let "total=$total + $val"
    done
    printf "% 8d %s\n" $total "seconds total"
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

Note: It is valid (and advantageous) to provide '-s' in conjuction with one of the 
      other operations, which will automatically run a "status report" after the 
      initial operation is complete.
      The advantage comes from avoiding a second scan of the filesystem.

ENDHERE
}


# Process options
operations=()
DEBUG=0
VERBOSE=1
while getopts ":hlusd" opt; do
    case $opt in
        d)  DEBUG=1
            ;;
        h)  usage
            cleanexit
            ;;
        l)  operations+=( LOCK )
            ;;
        s)  operations+=( STATUS )
            ;;
        u)  operations+=( UNLOCK )
            ;;
        v)  VERBOSE=1
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
[[ ${#operations[*]} -ge 1 ]] || croak 'No operations specified'

assert_root
assert_dependencies
assert_valid_path "$1"
scan_filesystem
for op in "${operations[@]}"; do
    case $op in
        LOCK)
            set_perms
            lock
            ;;
        UNLOCK)
            unlock
            set_perms
            ;;
        STATUS)
            status_report
            ;;
        *)
            echo "Unknown action specified."
            ;;
    esac
done
echo; time_report
cleanup
