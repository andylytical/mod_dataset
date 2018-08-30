#!/usr/bin/env python

import argparse
import collections
import fileinput
import os
import sys
import time


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

def process_cmdline():
    # Make parser object
    p = argparse.ArgumentParser( description=
        """
        Find dirs marked immutable.
        """,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
        )
    p.add_argument( 'infile',
                    help='Stats file (output from GPFS policy run)' )
    p.add_argument( '-t', '--tmpdir',
                    help='Directory for output files. Directory will be created if necessary.' )
    # Require action to take
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument( '--filter-dirs', dest='filter_dirs', action='store_true',
                        help='Filter immutable dirs from raw stats file' )
    group.add_argument( '--prune-subdirs', dest='prune_subdirs', action='store_true',
                        help='Prune subdirs from dirlist (dirlist is output from --filter-dirs operation' )
    # defaults
    defaults = {
        'tmpdir':    '/tmp/find_immutable_dirs',
    }
    p.set_defaults( **defaults )

    args = p.parse_args()

    # Check or create tmpdir
    os.makedirs( args.tmpdir, exist_ok=True )

    return( args )


def find_immutable_dirs( args ):
    outfiles = [ 'dirs' ]
    # Open output files
    handles = {}
    for name in outfiles:
        fn = '{}/{}'.format( args.tmpdir, name )
        handles[name] = open( fn, 'w' )

    # Process lines from stdin
    i=0
    start_time = time.time()
    for line in fileinput.input( args.infile ):
        i += 1
        parts = line.split( sep=None, maxsplit=8 )
        if len( parts ) != 9:
            num = len( parts )
            msg = 'line ({}) split into {} parts, expected 9\n{}'.format( i, num, line )
            raise UserWarning( msg )
        f = FileStat( *parts )

        # Keep only directories marked immutable
        if 'D' in f.flags and 'X' in f.flags:
            handles['dirs'].write( f.filename )

        if i % 10000000 == 0:
            elapsed_time = time.time() - start_time
            print( 'processed {} lines in {} seconds'.format( 
                i, 
                int( elapsed_time )
            ) )

    # Close output files
    for h in handles.values():
        h.close()


def find_unique( args ):
    unique_paths={}

    # Process lines from stdin
    i=0
    start_time = time.time()
    with open( args.infile ) as fh:
        for line in fh:
            path = line.rstrip()
            i += 1
            save_path = False
            match_found = False
            for key in list(unique_paths.keys()):
                if key.startswith( path ):
                    # path is a parent of existing key, remove existing key
                    save_path = True
                    unique_paths.pop( key )
                    # don't break, path may be a parent of more than one key
                if path.startswith( key ):
                    # existing key is parent of path, no action needed
                    match_found = True
                    break
            if save_path or not match_found:
                # no relationship between key and path, path is unique
                unique_paths[path] = True

            # Report progress
            if i % 50000 == 0:
                elapsed_time = time.time() - start_time
                print( 'processed {} lines in {} seconds; found {} unique_paths so far'.format( 
                    i, 
                    elapsed_time, 
                    len( unique_paths )
                ) )
#            if i > 1000:
#                break

    # Print all unique paths
    [ print(p) for p in sorted(unique_paths.keys()) ]
    print( 'Found {} unique paths'.format( len( unique_paths ) ) )

if __name__ == '__main__':
    args = process_cmdline()
    if args.filter_dirs:
        find_immutable_dirs( args )
    elif args.prune_subdirs:
        find_unique( args )
