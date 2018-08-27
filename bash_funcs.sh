#!/bin/bash


cleanexit() {
    cleanup
    exit 0
}


croak() {
    echo "ERROR (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*" 1>&2
    cleanup
    exit 99
}


warn() {
    if [[ $DEBUG -eq 1 ]] ; then
        echo "WARN (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*" 1>&2
    else
        echo "WARN $*" 1>&2
    fi
}


log() {
    if [[ $DEBUG -eq 1 ]] ; then
        echo "INFO (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
    elif [[ $VERBOSE -eq 1 ]] ; then
        echo "INFO $*"
    fi
}


debug() {
    [[ $DEBUG -ne 1 ]] && return
    echo "DEBUG (${BASH_SOURCE[1]} [${BASH_LINENO[0]}] ${FUNCNAME[1]}) $*"
}


continue_or_exit() {
    local msg="Continue?"
    [[ -n "$1" ]] && msg="$1"
    echo "$msg"
    select yn in "Yes" "No"; do
        case $yn in
            Yes) return 0;;
            No ) cleanexit;;
        esac
    done
}


assert_root() {
    debug "enter..."
    [[ $EUID -eq 0 ]] || croak 'Must be root'
}
