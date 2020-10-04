#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

. ${DIR}/common.bash
function usage(){
    echo "Usage: $0 -i <ip> -w [wordlist raw text] -z [flag for wordlist is compressed targz] [-s smptp port - default is 25] [username1 username2  ... usernameN - default is root] [-d debug mode]"
    exit 1
}
users=root
smtp_port=25
compressed=false
fileopencommand="cat"
while getopts "i:s:dw:z" o; do
    case "${o}" in
        i)
            ip="${OPTARG}"
            ;;
        s)
            smtp_port="${OPTARG}"
            ;;
        d)
            debug=true
            ;;
        w)
            words="${OPTARG}"
            ;;
        z) 
            fileopencommand="zcat"
            ;;
        *)
            usage
            ;;
    esac
done

if [ ! -f ${words} ] ; then
    logerror "File ${words} does not exist"
    usage
fi

if [ ! "${ip}" ] ; then
    usage
fi
shift $((OPTIND-1))

if [ $(nmap -p ${smtp_port} ${ip} -sS -oG /dev/stdout | grep Host.*open | awk '{print $2}' | wc -l) -eq 1 ] ; then
    debug "nmap detected ${ip}:${smtp_port} as open"
else
    logerror "ERROR: ${ip}:${smtp_port} is not open"
    exit 1
fi

vrfy_users="$@"
debug "vrfy_users ${vrft_users}"
debug "Opening smptp"

if [ ! -z "${vrfy_users}"  ] ; then
    users=${vrfy_users}
fi

unset fd

eval 'exec {fd}<>/dev/tcp/"${ip}"/"${smtp_port}"'  2>/dev/null

if test $? != 0 ; then
    logerror "ERROR: cannot open connection"
   exit 1
fi


function cleanup(){
debug "Shutting down ${fd}"
exec {fd}<&-
exec {fd}>&-
debug "Shut down"
exit
}

debug "FD is $fd"

if test -z "$fd" ; then
    logerror "ERROR: Connection did not open"
    exit 1
else
    echo "Connection established: ${ip} ${smtp_port}"
    trap "cleanup" HUP INT TERM EXIT QUIT
    read  -t 120 -r messageIn <&$fd
    if test $? != 0 ; then
       logerror "ERROR: cannot open connection"
       exit 1
    fi
    echo "Received:: ${ip} ${smtp_port} $messageIn"
    VRFY=true
    EXPN=true
    for userName in ${users} ; do
        echo "VRFY command: ${ip} ${smtp_port} VRFY ${userName}"
        echo -e "VRFY ${userName}"  >&$fd
        read -t 240 -r messageIn <&$fd
        if test $? != 0 ; then
           echo "VRFY does not work on ${ip} ${smtp_port}"
           VRFY=false
        fi
        echo "VRFY response: ${ip} ${smtp_port} $messageIn"

        echo -e "EXPN ${userName}"  >&$fd
        read -t 240 -r messageIn <&$fd
        if test $? != 0 ; then
           echo "EXPN does not work on ${ip} ${smtp_port}"
           EXPN=false
        fi
        echo "EXPN response: ${ip} ${smtp_port} $messageIn"
        if $(! ${EXPN})  &&  $(! ${VRFY}) ; then
            echo "EXPN and VRFY do not work"
            exit
        fi
    done
    
    if [ ! -z ${words}  ] ; then
        wordcount=$(${fileopencommand} ${words} | wc -l)
        if [ ${wordcount} -eq 0 ] ; then 
            logerror "Input file contained zero words"
        fi
        wordsCounted=0
        arraySize=$((  wordcount / 100 ))
        declare -a nextWordList
        for userName in $(${fileopencommand} ${words}) ; do
            nextWordList[${wordsCounted}]=${userName}
            wordsCounted=$((wordsCounted+1)) 
            if [ ${wordsCounted} -eq 10 ] ; then
                wordsCounted=0
                debug "${DIR}/smtpsweep.bash -i ${ip} -s ${smtp_port} `for i in $( seq 0 ${#nextWordList[@]} ); do echo -n " ${nextWordList[i]}"; done`"
                ${DIR}/smtpsweep.bash -i ${ip} -s ${smtp_port} `for i in $( seq 0 ${#nextWordList[@]} ); do echo -n " ${nextWordList[i]}"; done` &
                unset nextWordList
                declare -a nextWordList
            fi;
        done
    fi
    exit
fi
