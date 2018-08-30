#!/usr/bin/bash

# find source directory
PGMSRC=$( readlink -e "${BASH_SOURCE[0]}" )
PGMDIR=$( dirname "$PGMSRC" )

# Program variables
STATFN=/lsst/admin/stats.lsst_datasets
fnPYFINDIMMUTABLE="$PGMDIR/find_immutable_dirs.py"
PYTHON=$(which python3)
TMPDIR=/tmp/find_immutable_dirs

# Ensure python 3
[[ -s "$PYTHON" ]] || croak "Missing dependency: 'python3'"
[[ -x "$PYTHON" ]] || croak "Not executable: '$PYTHON'"
pyver=$( $PYTHON -c 'import sys; print( sys.version_info[0] )' )
[[ $pyver -ge 3 ]] || croak "Found python version '$pyver'; required >=3"


# Get all dirs marked immutable
set -x
time python3 "$fnPYFINDIMMUTABLE" \
    -t "$TMPDIR" \
    --filter-dirs \
    "$STATFN"

time python3 "$fnPYFINDIMMUTABLE" \
    -t "$TMPDIR" \
    --prune-subdirs \
    "$TMPDIR/dirs"
