# mod_dataset

# Purpose:
Some directory trees in LSST datasets need to be marked immutable to prevent any
accidental additions, deletions or modifications to a specific set of data.

# Goals:
Given a directory, perform any of the following, user configurable tasks:
1. lock the directory and subtree below it
   1. Set user and group ownership
   1. Set directory mode
   1. Set file mode
   1. Set all directories immutable
   1. Print Status
1. unlock the directory and subtree below it
   1. Remove immutable flag from all directories in the subtree
   1. Print Status
1. Print Status
   1. Report files not matching expected Mode
   1. Report directories not matching expected Mode
   1. Report files and directories not matching expected ownership
   1. Report files marked immutable
   1. Report directories missing immutable flag

## Notes
1. In GPFS, an immutable directory prevents additions, changes, deletions to all
   file contents inside that directory. This means that:
  1. Only directories need to be set immutable (ie: files should not have the immutable
     flag set.
  1. All directories in the subtree need to also be set immutable.
1. To help verify consistency across all datasets, the "status" mode of the tool
checks for files that have the immutable flag set and reports this as an error.


# Future work:
Adjust script to be able to test on a non-gpfs filesystem (ie: be able to
run the proper command and options to set a directory immutable for whatever the 
local filesystem's equivalent is).
