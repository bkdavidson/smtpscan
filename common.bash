#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function debug(){
    if [ ${debug} == "true"  ]; then echo "DEBUG: ${1}" ; fi
}

function logerror(){
   echo "$@" 1>&2;
}

