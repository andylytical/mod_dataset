#!/bin/bash

DIR=~/working
dirlist=~/tmp_dirlist
filelist=~/tmp_filelist

find "$DIR" -type d \
| tee >(parallel "stat -c '%f %U %G %n' {}" >$dirlist) \
| parallel 'find {} -mindepth 1 -maxdepth 1 ! -type d' \
| parallel "stat -c '%f %U %G %n' {}" > $filelist
