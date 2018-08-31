#!/bin/bash

TOPDIR=/lsst/datasets
STATFN=/lsst/admin/stats.lsst_datasets
STATFN_TRIGGER=/lsst/admin/stats.rerun
OWNER=34076
GROUP=1363
FILE_PERMS_STRING='-r--r--r--'
FILE_PERMS_NUMERIC='0444'
DIR_PERMS_STRING='dr-xr-sr-x'
DIR_PERMS_NUMERIC='2555'
MMCHATTR='/usr/lpp/mmfs/bin/mmchattr -l'
PARALLEL=$( which parallel )
PYTHON=$( which python3 )
TGTPATH=
declare -A TIME

TMPDIR='/tmp/mod_dataset_tmp'
mkdir -p "$TMPDIR"
fnLASTUPDATE="$TMPDIR/.last_update"
# These are the files output from parse_gpfs_stats
fnDIRS="$TMPDIR/dirs"
fnFILES="$TMPDIR/files"
fnDIRPERMS="$TMPDIR/dirperms"
fnFILEPERMS="$TMPDIR/fileperms"
fnLOCKED="$TMPDIR/locked"
fnUNLOCKED="$TMPDIR/unlocked"
fnSYMLINKS="$TMPDIR/symlinks"
fnOWNERSHIP="$TMPDIR/ownership"

# parallel joblog basename
fnJOBLOG="$TMPDIR/joblog"

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


clean_joblogs() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local dn=$( dirname "$fnJOBLOG" )
    local fnbase=$( basename "$fnJOBLOG" )
    find $TMPDIR -mindepth 1 -name "${fnbase}*" -delete
}


clean_tmp() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    find $TMPDIR -mindepth 1 -delete
}


parse_filesystem_stats() {
    ### Parse latest filesystem stats from STATFN
    #   Save data to text files
    #   Upon success, write a "last_update" file with timestamp of last update.
    #   Next run, if "last_update" is newer than STATFN, no need to re-run.
    #             if "last_update" is older than STATFN, clean old files and re-run.
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Parsing filesystem stats ..."
    # check for last update, skip status recompute only if all of the following:
    # 1. cached stats exist
    # 2. tgtpath is same as old path
    # 3. statfn hasn't been updated since last run
    if [[ -f "$fnLASTUPDATE" ]] ; then
        local old_path=$( head -1 "$fnLASTUPDATE" )
        if [[ "$old_path" == "$TGTPATH" ]] ; then
            if [[ "$fnLASTUPDATE" -nt "$STATFN" ]] ; then
                TIME[PARSE_STATS]=0
                log "Done (nothing to do, stats file is unchanged since last run)"
                return
            fi
        fi
    fi
    echo "$TGTPATH" >"$fnLASTUPDATE"
    local start=$SECONDS
    grep -F "$TGTPATH" $STATFN \
    | $PYTHON $PARSE_GPFS_STATS \
        -u "$OWNER" \
        -g "$GROUP" \
        -f " $FILE_PERMS_STRING" \
        -d "$DIR_PERMS_STRING" \
        -t "$TMPDIR"
    local end=$SECONDS
    TIME[PARSE_STATS]=$(bc <<< "$end - $start")
    log "Parse filesystem stats completed in ${TIME[PARSE_STATS]} seconds"
}


check_joblog_errors() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ $# -ne 1 ]] && croak "Expected 1 argument, got '$#'"
    local joblog="$1"
    [[ -r "$joblog" ]] || croak "Cant read joblog file '$joblog'"
    local errcount=$( tail -n +2 "$joblog" \
        | cut -f 1-8 \
        | awk -F '\t' '$7 !~ /0/ {printf "\n"}' \
        | wc -l
    )
    if [[ $errcount -gt 0 ]] ; then
        croak "Errors detected in joblog: '$joblog'"
    fi
}


set_perms() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    local joblog="${fnJOBLOG}.set_dir_perms"
    # Dir perms
    log "Setting directory permissions ..."
    $PARALLEL \
        --xargs \
        --joblog "$joblog" \
        -a $fnDIRPERMS \
        "chmod $DIR_PERMS_NUMERIC"
    check_joblog_errors "$joblog"
    log "Done"
    # File perms
    joblog="${fnJOBLOG}.set_file_perms"
    log "Setting file permissions ..."
    $PARALLEL \
        --xargs \
        -a $fnFILEPERMS \
        --joblog "$joblog" \
        "chmod $FILE_PERMS_NUMERIC"
    check_joblog_errors "$joblog"
    log "Done"
    local end=$SECONDS
    TIME[SET_PERMS]=$(bc <<< "$end - $start")
    log "Set permissions completed in ${TIME[SET_PERMS]} seconds"
}


set_ownership() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    local start=$SECONDS
    local joblog="${fnJOBLOG}.set_ownership"
    log "Setting ownership ..."
    $PARALLEL \
        --xargs \
        --joblog "$joblog" \
        -a $fnOWNERSHIP \
        "chown ${OWNER}:${GROUP}"
    check_joblog_errors "$joblog"
    local end=$SECONDS
    TIME[SET_OWNERSHIP]=$(bc <<< "$end - $start")
    log "Set ownership completed in ${TIME[SET_OWNERSHIP]} seconds"
}


lock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Locking files..."
    local start=$SECONDS
    local joblog="${fnJOBLOG}.lock"
    $PARALLEL \
        --xargs \
        --joblog "$joblog" \
        -a $fnUNLOCKED \
        "$MMCHATTR -i yes"
    check_joblog_errors "$joblog"
    local end=$SECONDS
    TIME[LOCK]=$(bc <<< "$end - $start")
    log "Locking files completed in ${TIME[LOCK]} seconds"
}


unlock() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    log "Unlocking files..."
    local start=$SECONDS
    local joblog="${fnJOBLOG}.unlock"
    $PARALLEL \
        --xargs \
        --joblog "$joblog" \
        -a $fnLOCKED \
        "$MMCHATTR -i no"
    check_joblog_errors "$joblog"
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
    local stats_mtime=$( date -d @$(stat -c '%Y' $STATFN) +'%F %T' )

    # Status Details
    echo
    echo "Status report for '$TGTPATH'"
    echo "(based on statfile '$STATFN')"
    echo "(generated at $stats_mtime)"
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

    # Check joblogs for errors
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

Usage: $prg [options] PATH

Options:
    -h   Print this help message
    -d   Run in debug mode (lots of output)
    -f   Don't use cached data (from a previous Status operation).

Controlling operation:
    -l   Lock    Add "immutable" flag on the specified directory 
                 and all sub-directories. Also sets the proper permissions
                 and ownership.
    -u   UnLock  Remove "immutable" flag from the specified directory 
                 and all sub-directories
    -s   Status  Report mutability status of the specified directory
                 Also checks permissions and ownership
    -n   NewPolicyRun
                 Trigger a new policy run to gather file stats.
     
Note:
      Status is computed from the file '/lsst/admin/stats.lsst_datasets',
      which is updated by cron a few times daily.  It is valid to run a
      status, lock, or unlock operation without any preparatory action (because
      the stats file will be accurate the first time).
      However, it is INVALID to compare Status (-s) immediately
      after a Lock (-l) or Unlock (-u) operation without first triggering an
      update to the stats file.  The stats file update will happen in the
      background. Compare timestamp on the stats file to know if/when the
      background job has completed (takes about 20 minutes).

Sample Sequence:
  1. mod_dataset.sh -s PATH
  2. mod_dataset.sh -l PATH
  3. mod_dataset.sh -n
  4. stat -c '%y' /lsst/admin/stats.lsst_datasets
  5. watch -n 60 "stat -c '%y' /lsst/admin/stats.lsst_datasets"
     (wait for timestamp update on stats file)
  6. mod_dataset.sh -s PATH
     (If no warnings, then all is good)

ENDHERE
}


mk_new_stats() {
    debug "enter..."
    [[ $DEBUG -eq 1 ]] && set -x
    [[ -f "$STATFN_TRIGGER" ]] && return 0
    local safety=$TMPDIR/.mk_new_stats
    local now=$( date +%s )
    local last safe
    if [[ -f "$safety" ]] ; then
        last=$( stat -c '%Y' "$safety" )
        safe=$( bc <<< "($now - $last) > 3600" )
        [[ $safe -eq 1 ]] || croak 'Last trigger less than 1 hr old, refusing to trigger new stats run'
    fi
    if [[ -f "$STATFN" ]] ; then
        last=$( stat -c '%Y' "$STATFN" )
        safe=$( bc <<< "($now - $last) > 3600" )
        [[ $safe -eq 1 ]] || croak 'Stats file is less than 1 hr old, refusing to trigger new stats run'
    fi
    touch "$STATFN_TRIGGER"
    touch "$safety"
}


# Process options
operation=''
DEBUG=0
VERBOSE=1
while getopts ":dfhlnsuv" opt; do
    case $opt in
        d)  DEBUG=1
            ;;
        f)  clean_tmp
            ;;
        h)  usage
            cleanexit
            ;;
        l)  operation='LOCK'
            ;;
        n)  operation='NEWSTATS'
            ;;
        s)  operation='STATUS'
            ;;
        u)  operation='UNLOCK'
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
[[ ${#operation} -ge 1 ]] || croak 'No operation specified'

assert_root
case "$operation" in
    LOCK)
        assert_dependencies
        assert_valid_path "$1"
        parse_filesystem_stats
        clean_joblogs
        set_perms
        set_ownership
        lock
        time_report
        ;;
    UNLOCK)
        assert_dependencies
        assert_valid_path "$1"
        parse_filesystem_stats
        clean_joblogs
        unlock
        time_report
        ;;
    STATUS)
        assert_dependencies
        assert_valid_path "$1"
        parse_filesystem_stats
        status_report
        time_report
        ;;
    NEWSTATS)
        mk_new_stats
        ;;
    *)
        echo "Unknown action specified."
        ;;
esac
