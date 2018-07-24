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

Note: It is valid (and advantageous) to provide '-s' in conjuction with one of the
      other operations, which will automatically run a "status report" after the
      initial operation is complete.
      The advantage comes from avoiding a second scan of the filesystem.
```

# Future work:
Adjust script to be able to test on a non-gpfs filesystem (ie: be able to
run the proper command and options to set a directory immutable for whatever the 
local filesystem's equivalent is).
