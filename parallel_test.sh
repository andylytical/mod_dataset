#!/bin/bash

DIR=~/working
dirlist=~/tmp_dirlist
filelist=~/tmp_filelist
declare -a VALID_OWNERS=( aloftus root )
declare -a VALID_GROUPS=( aloftus )
#perms and modes are octal (see man -S2 stat)
#declare -a VALID_FILEPERMS=( 0644 )
declare -a VALID_FILEPERMS=( 0400 0444 0664 0755 0775 0777 )
declare -a VALID_DIRPERMS=( 0755 )
declare -a VALID_FILETYPES=( 0120000 0100000 )
declare -a VALID_DIRTYPES=( 0040000 )




scan_filesystem() {
    # Save a list of files and another of dirs
    find "$DIR" -type d \
    | tee $dirlist \
    | parallel 'find {} -mindepth 1 -maxdepth 1 ! -type d' >$filelist
}


_find_type_mode_mismatches() {
    # find files not matching mode (type or perms) or user
    local -a types=("${!1}")
#    echo TYPES "${types[@]}"
    local -a perms=("${!2}")
#    echo PERMS "${perms[@]}"
    local infile="${!3}"
#    echo INFILE "$infile"

    local -a valid_patterns
    for typ in "${types[@]}"; do
        for perm in "${perms[@]}"; do
            #create mode in hex (as returned by stat)
            mode=$( printf '%x' $(( 0$typ + 0$perm )) )
            for user in "${VALID_OWNERS[@]}"; do
                for group in "${VALID_GROUPS[@]}"; do
                    valid_patterns+=( '-e' "$mode $user $group" )
                done
            done
        done
    done

    # check items in filelist
    set -x
    <$infile parallel "stat -c '%f %U %G %n' {}" \
    | grep -v -F "${valid_patterns[@]}" 
    #| wc -l
}


find_file_mismatches() {
    _find_type_mode_mismatches VALID_FILETYPES[@] VALID_FILEPERMS[@] filelist
}


find_dir_mismatches() {
    VALID_DIRTYPES[@] VALID_DIRPERMS[@] dirlist
}

#scan_filesystem

find_file_mismatches
