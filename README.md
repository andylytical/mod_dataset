# mod_dataset

# Purpose:
Some directory trees in LSST datasets need to be marked immutable to prevent any
accidental additions, deletions or modifications to a specific set of data.

# Goals:
Given a directory, perform any of the following, user configurable tasks:
1. Lock the directory and subtree below it
   1. Set user and group ownership
   1. Set directory and file permissions
   1. Set all files and directories immutable
1. Unlock the directory and subtree below it
   1. Remove immutable flag from all files and directories in the subtree
1. Print Status
   1. Report number of files and directories:
      1. not matching expected User, Group or Permisions
      1. that are locked (immutable)
      1. that are unlocked (not immutable)
1. Trigger a new GPFS policy run that will refresh the master list of stats.
This stats file is used for the "Print Status" action and the stats file
must be updated after a lock/unlock operation for accurate "Print Status" 
output.


# Usage:
```
Usage: mod_dataset.sh [options] <path/to/directory>

Options:
    -h   Print this help message
    -d   Run in debug mode (lots of output)
    -f   Force a new parse filesystem stats (ignore cached information)
         Needed if running multiple status operations against different paths.

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
      background, Compare timestamp on the stats file to know if/when the
      background job has completed (takes about 20 minutes).

Note: It is valid to run multiple Status operations without updating the stats
      file, since Status is a read-only operation and thus the stats file will
      remain up-to-date. When the first Status operation is run, the stats file
      will be parsed based on the PATH given. This takes about 60 seconds.
      The output from the Status run will be cached so that future runs will be
      faster. However, if a future run is for a different PATH, use the -f
      option to ignore the cache and re-parse the stats file.
```

# Future work:
Adjust script to be able to test on a non-gpfs filesystem (ie: be able to
run the proper command and options to set a directory immutable for whatever the 
local filesystem's equivalent is).
