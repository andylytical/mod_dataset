#!/bin/bash

TOPDIR=/lsst/datasets
STATFN=/lsst/admin/stats.lsst_datasets
OWNER=34076
GROUP=1363
FILE_PERMS_STRING='-r--r--r--'
FILE_PERMS_NUMERIC='0444'
DIR_PERMS_STRING='-r-xr-xr-x'
DIR_PERMS_NUMERIC='0555'
MMCHATTR='/usr/lpp/mmfs/bin/mmchattr -l'
MMLSATTR='/usr/lpp/mmfs/bin/mmlsattr -l'
PARALLEL=$( which parallel )
PYTHON=$( which python3 )
TGTPATH=
declare -A TIME

#TMPDIR=/tmp/$$
TMPDIR='tmp'
mkdir -p "$TMPDIR"
# These are the files output from parse_gpfs_stats
fnDIRS="$TMPDIR/dirs"
fnFILES="$TMPDIR/files"
fnDIRPERMS="$TMPDIR/dirperms"
fnFILEPERMS="$TMPDIR/fileperms"
fnLOCKED="$TMPDIR/locked"
fnUNLOCKED="$TMPDIR/unlocked"
fnSYMLINKS="$TMPDIR/symlinks"
fnOWNERSHIP="$TMPDIR/ownership"

# attempt to load common files
PGMSRC=$( readlink -e "${BASH_SOURCE[0]}" )
PGMDIR=$( dirname "$PGMSRC" )
FUNCS="$PGMDIR/bash_funcs.sh"
[[ -f "$FUNCS" ]] || {
    echo "File not found: '$FUNCS'" 1>&2
    exit 1
}
source "$FUNCS"
PARSE_GPFS_STATS="$PGMDIR/parse_gpfs_stats.py"


cleanup() {
    [[ $DEBUG -eq 1 ]] && set -x
    local action='delete'
    if [[ $DEBUG -eq 1 ]] ; then
        echo "TMPFILES:"
        action='print'
    fi
    find "$TMPDIR" -$action
}

assert_dependencies() {
    [[ -s "$PARALLEL" ]] || croak "Missing dependency: 'parallel'"
    [[ -x "$PARALLEL" ]] || croak "Not executable: '$PARALLEL'"
    $PARALLEL --version | head -1 | grep -q 'GNU parallel' \
    || croak "Missing dependency: 'gnu parallel'"
    [[ -s "$PYTHON" ]] || croak "Missing dependency: 'python3'"
    [[ -x "$PYTHON" ]] || croak "Not executable: '$PYTHON'"
    pyver=$( $PYTHON -c 'import sys; print( sys.version_info[0] )' )
    [[ $pyver -ge 3 ]] || croak "Found python version '$pyver'; required >=3"
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
    [[ -n $TGTPATH ]] || croak "Unable to find canonical path"
    [[ $TGTPATH == $TOPDIR/* ]] || croak "Not part of Datasets: '$TGTPATH'"
    [[ -d $TGTPATH ]] || croak "Not a directory: '$TGTPATH'"
}


parse_filesystem_stats() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    grep -F "$TGTPATH" $STATFN \
    | $PYTHON $PARSE_GPFS_STATS -t "$TMPDIR" 
    local end=$SECONDS
    TIME[PARSE_STATS]=$(bc <<< "$end - $start")
    log "Parse filesystem stats completed in ${TIME[PARSE_STATS]} seconds"
}


set_perms() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    log "Setting directory permissions ..."
    $PARALLEL --xargs -a $fnDIRPERMS "chmod $DIR_PERMS_NUMERIC"
    log "Done"
    log "Setting file permissions ..."
    $PARALLEL --xargs -a $fnFILEPERMS "chmod $FILE_PERMS_NUMERIC"
    log "Done"
    local end=$SECONDS
    TIME[SET_PERMS]=$(bc <<< "$end - $start")
    log "Set permissions completed in ${TIME[SET_PERMS]} seconds"
}


set_ownership() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    log "Setting ownership ..."
    $PARALLEL --xargs -a $fnOWNERSHIP "chown ${OWNER}:${GROUP}"
    local end=$SECONDS
    TIME[SET_PERMS]=$(bc <<< "$end - $start")
    log "Set ownership completed in ${TIME[SET_PERMS]} seconds"
}


lock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Locking files..."
    local start=$SECONDS
    $PARALLEL --xargs -a $fnUNLOCKED "$MMCHATTR -i yes"
    local end=$SECONDS
    TIME[LOCK]=$(bc <<< "$end - $start")
    log "Locking files completed in ${TIME[LOCK]} seconds"
}


unlock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Unlocking files..."
    local start=$SECONDS
    $PARALLEL --xargs -a $fnLOCKED "$MMCHATTR -i no"
    local end=$SECONDS
    TIME[UNLOCK]=$(bc <<< "$end - $start")
    log "Unlocking files completed in ${TIME[UNLOCK]} seconds"
}


status_report() {
    debug "enter..."
    local num_files=$( wc -l $fnFILES | cut -d' ' -f1 )
    local num_dirs=$( wc -l $fnDIRS | cut -d' ' -f1 )
    local num_symlinks=$( wc -l $fnSYMLINKS | cut -d' ' -f1 )
    local num_locked=$( wc -l $fnLOCKED | cut -d' ' -f1 )
    local num_unlocked=$( wc -l $fnUNLOCKED | cut -d' ' -f1 )
    local total_files_dirs=$( bc <<< "$num_files + $num_dirs" )
    local total_locked_unlocked=$( bc <<< "$num_locked + $num_unlocked" )
    local num_dirperms=$( wc -l $fnDIRPERMS | cut -d' ' -f1 )
    local num_fileperms=$( wc -l $fnFILEPERMS | cut -d' ' -f1 )
    local num_ownership=$( wc -l $fnOWNERSHIP | cut -d' ' -f1 )
    local stats_mtime=$( stat -c %y $STATFN )

    # Status Details
    echo
    echo "Status report for '$TGTPATH'"
    echo "(based on stats generated at $stats_mtime)"
    echo
    printf "% 8d Symlinks (excluded from totals)\n" $num_symlnks
    printf "\n"
    printf "% 8d Dirs\n" $num_dirs
    printf "% 8d Files\n" $num_files
    printf "% 8d Total (dirs + files)\n" $total_files_dirs
    printf "\n"
    printf "% 8d Locked\n" $num_locked
    printf "% 8d Unlocked\n" $num_unlocked
    printf "% 8d Total (locked + unlocked)\n" $total_locked_unlocked
    printf "\n"

    # Error checking
    if [[ $num_unlocked -gt 0 ]] ; then
        warn "$num_unlocked files or dirs unlocked."
    fi
    if [[ $num_locked -ne $total_files_dirs ]] ; then
        warn "Mismatch between Locked ($num_locked) and Dirs+Files ($total_files_dirs)"
    fi
    if [[ $num_dirperms -gt 0 ]] ; then
        warn "$num_dirperms directories with bad permissions"
    fi
    if [[ $num_fileperms -gt 0 ]] ; then
        warn "$num_fileperms files with bad permissions"
    fi
    if [[ $num_ownership -gt 0 ]] ; then
        warn "$num_ownership inodes with bad ownership"
    fi
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

Note: Status is computed from the file '$STATFN', which is updated by cron only
      a few times daily.  It is INVALID to compare Status (-s) immediately
      after a Lock (-l) or Unlock (-u) operation as the results will not be accurate.
      Wait until '$STATFN' has been refreshed before running a Status report again.
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

# Check for input
[[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"

assert_root
assert_dependencies
assert_valid_path "$1"
parse_filesystem_stats
for op in "${operations[@]}"; do
    case $op in
        LOCK)
            set_perms
            lock
            ;;
        UNLOCK)
            unlock
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
