# mod_dataset.sh
Some directory trees in LSST datasets need to be marked immutable to prevent any
accidental additions, deletions or modifications to a specific set of data.

### Goals:
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

### Usage:
```
mod_dataset.sh -h
```

# find_immutable_topdirs.sh
Get an updated list of all *unique* datasets in the filesystem.

### Usage:
```
find_immutable_topdirs.sh
```
