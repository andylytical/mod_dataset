#!/usr/bin/env python

import argparse
import collections
import fileinput
import os
import sys


# Require python 3
if sys.version_info[0] < 3:
    print("This script requires Python version 3")
    sys.exit(1)

# Structure to hold stat info
FileStat = collections.namedtuple( 'FileStat', [ 'inode',
                                                 'na1',
                                                 'na2',
                                                 'uid',
                                                 'gid',
                                                 'perms',
                                                 'flags',
                                                 'sep',
                                                 'filename' ] )

# Output filenames
listnames = [ 'dirperms',
              'dirs',
              'fileperms',
              'files',
              'locked',
              'ownership',
              'symlinks',
              'unlocked',
            ]

def process_cmdline():
    # Make parser object
    p = argparse.ArgumentParser( description=
        """
        Perform analysis of gpfs stat information.
        Output files saved in TMPDIR.
        """,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
        )
    p.add_argument( '-u', '--uid', help='track inodes not matching this uid' )
    p.add_argument( '-g', '--gid', help='track inodes not matching this gid' )
    p.add_argument( '-f', '--fileperms',
                    help='track files not matching these permissions' )
    p.add_argument( '-d', '--dirperms',
                    help='track dirs not matching these permissions' )
    p.add_argument( '-t', '--tmpdir',
                    help='Directory for output files. Directory will be created if necessary.' )
    defaults = {
        'uid':       '34076',
        'gid':       '1363',
        'fileperms': '-r--r--r--',
        'dirperms':  '-r-xr-xr-x',
        'tmpdir':    '/tmp',
    }
    p.set_defaults( **defaults )

    args = p.parse_args()

    # Check or create tmpdir
    os.makedirs( args.tmpdir, exist_ok=True )

    return( args )


def process_input( args ):
    # Open output files
    handles = {}
    for name in listnames:
        fn = '{}/{}'.format( args.tmpdir, name )
        handles[name] = open( fn, 'w' )

    # Process lines from stdin
    for line in fileinput.input( '-' ):
        f = FileStat( *( line.split( sep=None, maxsplit=9 ) ) )

        # regular file
        if 'F' in f.flags:
            handles['files'].write( '{}\n'.format( f.filename ) )
            if f.perms != args.fileperms:
                handles['fileperms'].write( '{}\n'.format( f.filename ) )
        # directory
        elif 'D' in f.flags:
            handles['dirs'].write( '{}\n'.format( f.filename ) )
            if f.perms != args.dirperms:
                handles['dirperms'].write( '{}\n'.format( f.filename ) )
        #symlink
        elif 'L' in f.flags:
            handles['symlinks'].write( '\n' ) #only count number using wc -l
            continue
        #other file type
        elif 'O' in f.flags:
            raise SystemExit( "Invalid file type '{}'".format( line ) )

        # locked
        if 'X' in f.flags:
            handles['locked'].write( '{}\n'.format( f.filename ) )
        # unlocked
        else:
            handles['unlocked'].write( '{}\n'.format( f.filename ) )

        # user mismatches
        if f.uid != args.uid:
            handles['ownership'].write( '{}\n'.format( f.filename ) )
        # group mismatches
        elif f.gid != args.gid:
            handles['ownership'].write( '{}\n'.format( f.filename ) )

    # Close output files
    for h in handles.values():
        h.close()


if __name__ == '__main__':
    args = process_cmdline()
    process_input( args )

#### GPFS STATS FORMAT
#1       2         3  4      5     6         7     8   9
#inode   ?         ?  UID    GID   PERMS     FLAGS SEP PATH
#1579008 733120217 0  34076  1363  -rw-r--r--  FAu -- /lsst/datasets/hsc/repo/rerun/DM-13666/UDEEP/jointcal-results/9813/fcr-0023052-085.fits
