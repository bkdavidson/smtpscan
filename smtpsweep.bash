#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

. ${DIR}/common.bash
function usage(){
    echo "Usage: $0 -i <ip> -a [domain suffix] -w [wordlist raw text] -z [flag for wordlist is compressed targz] [-s smptp port - default is 25] [username1 username2  ... usernameN - default is root] [-d debug mode] [-S skip initial connection attempt for dev only]"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com test admin root username1"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com -w /tmp/rockyou.gz -z"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com -w /tmp/rockyou.txt"
    exit 1
}
users=root
smtp_port=25
compressed=false
fileopencommand="cat"
skipInitialTest=false
while getopts "i:s:dw:za:S" o; do
    case "${o}" in
        i)
            ip="${OPTARG}"
            ;;
        s)
            smtp_port="${OPTARG}"
            ;;
        a)
            domain="${OPTARG}"
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
        S)
            #option for dev purposes only
            skipInitialTest=true
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

function testConnectionAttempt(){
    rc=${1}
    message=${2}
    if test ${rc} != 0 ; then
        logerror ${message}
        exit 1
fi
}
#test connection
if $( ${skipInitialTest}) ; then
    timeout 10 bash -c "</dev/tcp/${ip}/${smtp_port}"
    testConnectionAttempt $? "ERROR: ${ip}:${smtp_port} is not open!"
fi
vrfy_users="$@"
debug "vrfy_users ${vrft_users}"
debug "Opening smptp"

if [ ! -z "${vrfy_users}"  ] ; then
    users=${vrfy_users}
fi

unset fd


eval 'exec {fd}<>/dev/tcp/"${ip}"/"${smtp_port}"'  2>/dev/null
testConnectionAttempt $? "ERROR: cannot open connection"


function cleanup(){
debug "Shutting down ${fd}"
exec {fd}<&-
exec {fd}>&-
debug "Shut down"
exit
}

#return values used by readFD
messageIn=""
readSuccess=""
function readFD(){
    verb=${1}
    read -t 240 -r messageIn <&$fd
    if  [[ $? != 0  || ${messageIn^^} =~ "ERROR" ]]   ; then
        echo "${verb} does not work on ${ip} ${smtp_port}"
        readSuccess=false
    fi
    echo "${verb} response: ${ip} ${smtp_port} $messageIn"
}

function sendCommand(){
    command_name=${1}
    smtp_command=${2}
    echo "${command_name} command: ${ip} ${smtp_port} ${smtp_command}"
    echo -e "${smtp_command}"  >&$fd
}
debug "FD is $fd"

if test -z "$fd" ; then
    logerror "ERROR: Connection did not open"
    exit 1
else
    echo "Connection established: ${ip} ${smtp_port}"
    trap "cleanup" HUP INT TERM EXIT QUIT
    read  -t 120 -r messageIn <&$fd
    testConnectionAttempt $? "ERROR: no incoming data from connection"
    echo "Received:: ${ip} ${smtp_port} $messageIn"
    VRFY=true
    EXPN=true
    for userName in ${users} ; do
        sendCommand "VRFY" "VRFY ${userName}${domain}"
        readFD "VRFY"
        VRFY=${readSuccess}

        #NOTE: username isn't strictly the right wording for EXPN
        sendCommand "EXPN" "EXPN ${userName}"
        readFD "EXPN"
        EXPN=${readSuccess}

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
