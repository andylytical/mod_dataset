# mod_dataset

# Purpose:
Some directory trees in LSST datasets need to be marked immutable to prevent any
accidental additions, deletions or modifications to a specific set of data.

# Goals:
Given a directory, perform any of the following, user configurable tasks:
1. lock the directory and subtree below it
   1. Set user and group ownership
   1. Set directory permissions
   1. Set file permissions
   1. Set all files and directories immutable
   1. Print Status
1. unlock the directory and subtree below it
   1. Remove immutable flag from all files and directories in the subtree
   1. Print Status
1. Print Status
   1. Report number of files and directories:
      1. not matching expected User, Group or Permisions
      1. that are locked (immutable)
      1. that are unlocked (not immutable)

# Usage:
```
Usage: mod_dataset.sh [options] <path/to/directory>

Options:
    -h   Print this help message
    -d   Run in debug mode (lots of output)

Controlling operation:
    -l   Lock    Add "immutable" flag on the specified directory and all sub-directories
    -u   UnLock  Remove "immutable" flag from the specified directory and all sub-directories
    -s   Status  Report mutability status of the specified directory
                 Also checks permissions and ownership

Note: Status is computed from the file '/lsst/admin/stats.lsst_datasets', which is updated by cron only
      a few times daily.  It is INVALID to compare Status (-s) immediately
      after a Lock (-l) or Unlock (-u) operation as the results will not be accurate.
      Wait until '/lsst/admin/stats.lsst_datasets' has been refreshed before running a Status report again.
```

# Future work:
Adjust script to be able to test on a non-gpfs filesystem (ie: be able to
run the proper command and options to set a directory immutable for whatever the 
local filesystem's equivalent is).
