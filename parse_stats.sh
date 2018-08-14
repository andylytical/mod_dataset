#!/usr/bin/bash

TGTPATH='/lsst/datasets/hsc/repo/rerun/DM-13666'

UID=34076
GID=1363
PERMS_FILE='-r--r--r--'
PERMS_DIR='-r-xr-xr-x'

awk -v "UID=$UID" \
    -v "GID=$GID" \
    -v "FPERM=$PERMS_FILE" \
    -v "DPERM=$PERMS_DIR" \
    -v "PATH=$TGTPATH" \
    -v "fnDIRS=tmp.dirlist" \
    -v "fnFILES=tmp.filelist" \
    -v "fnLINKCOUNT=tmp.num_symlinks" \
    -v "fnLOCKED=tmp.locked" \
    -v "fnUNLOCKED=tmp.unlocked" \
    '
    BEGIN { SEP=" -- "
            SEP_PATH=SEP PATH
            uid=4
            gid=5
            perms=6
            flags=7
            ftype=7
            directory=D
            regularfile=F
            symlink=L
            otherfiletype=O
            immutable=X
            symlinkcount=0
            mismatchcount=0
    }
    $NF !~ SEP_PATH {next}
    $ftype ~ otherfiletype { printf("invalid file type %s\n", $0); exit }
    $ftype ~ symlink { symlinkscount++; next }
    { split( $0, parts, SEP ); fullpath=parts[1] }
    $ftype ~ directory { print(fullpath)>fnDIRS }
    $ftype ~ regularfile { print(fullpath)>fnFILES }
    $flags ~ immutable { print(fullpath)>fnLOCKED }
    $flags !~ immutable { print(fullpath)>fnUNLOCKED }
    $uid != UID { mismatchcount++; next }
    $gid != GID { mismatchcount++; next }
    $ftype ~ directory && $perms != DPERM { mismatchcount++; next }
    $ftype ~ regularfile && $perms != FPERM { mismatchcount++; next }
    END {
        printf("% 20s %d\n", "Num Symlinks", symlinkcount)
        printf("% 20s %d\n", "Num Mismatches", mismatchcount)
    }
'

#1       2         3  4      5     6         7     8   9
#inode   ?         ?  UID    GID   PERMS     FLAGS SEP PATH
#1579008 733120217 0  34076  1363  -rw-r--r--  FAu -- /lsst/datasets/hsc/repo/rerun/DM-13666/UDEEP/jointcal-results/9813/fcr-0023052-085.fits

