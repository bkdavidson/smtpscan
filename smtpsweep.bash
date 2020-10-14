#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

. ${DIR}/common.bash
function usage(){
    echo "Usage: $0 -i <ip> -a [domain suffix] -w [wordlist raw text] -f [fast most multi-thread wordlist] -z [flag for wordlist is compressed targz] -n [name for logging] [-s smptp port - default is 25] [username1 username2  ... usernameN - default is root] [-d debug mode] [-S skip initial connection attempt for dev only]"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com test admin root username1"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com -w /tmp/rockyou.gz -z"
    echo "Example: smtpsweep.bash -i 127.0.0.1 -a @test.com -w /tmp/rockyou.txt"
    exit 1
}
users=root
smtp_port=25
fileopencommand="cat"
interval=240
moreCommands=""
recurse=false
name=main
skipFirstConnect=false
while getopts "i:s:dw:W:fza:I:n:S" o; do
    case "${o}" in
        i)
            ip="${OPTARG}"
            moreCommands+="-i ${ip} "
            ;;
        I)
            interval="${OPTARG}"
            if [[ ${interval//[0-9]} = "" ]] ; then
                if [[ ${interval} -gt 239  ||  ${interval} -lt 1 ]]; then echo "ERROR: -I should be between 1 and 240" && exit 1; fi
            else
                echo "ERROR: -I should contain only digits" && exit 1
            fi
            moreCommands+="-I ${interval} "
            ;;
        s)
            smtp_port="${OPTARG}"
            moreCommands+="-s ${smtp_port} "
            ;;
        a)
            domain="${OPTARG}"
            moreCommands+="-a ${domain} "
            ;;
        d)
            debug=true
            moreCommands+="-d "
            ;;
        n)
            name="${OPTARG}"
            ;;
        w)
            words="${OPTARG}"
            ;;
        f)
            recurse=true
            ;;
        z) 
            fileopencommand="zcat"
            ;;
        S)
            skipFirstConnect=false
            ;;
        *)
            usage
            ;;
    esac
done
debug "${name}: ip=${ip} interval=${interval} smtp_port=${smtp_port} domain=${domain} debug=${debug} name=${name} words=${words} recurse=${recurse} fileopencommand=${fileopencommand}"
debug "${name}: morecommands=${moreCommands}"
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

if $( ${skipFirstConnect}) ; then
    timeout 10 bash -c "</dev/tcp/${ip}/${smtp_port}"
    testConnectionAttempt $? "ERROR: ${ip}:${smtp_port} is not open!"
fi
vrfy_users="$@"
debug "${name}:  vrfy_users ${vrft_users}"
debug "${name}: Opening smptp"

if [ ! -z "${vrfy_users}"  ] ; then
    users=${vrfy_users}
fi

unset fd


eval 'exec {fd}<>/dev/tcp/"${ip}"/"${smtp_port}"'  2>/dev/null
testConnectionAttempt $? "ERROR: cannot open connection"
tmpoutdir=$(mktemp -d)
attempts=0
function cleanup(){
    debug "${name}: Shutting down ${fd}"
    exec {fd}<&-
    exec {fd}>&-
    debug "${name}: Shut down"
    rm -rf "${tmpoutdir}"
    if [[ -n "$(jobs -pr)" ]] ; then
        kill $(jobs -pr)
    fi
    if [[ ! -z ${words} && "${recurse}" = false ]] ; then
        echo "${name}: ${attempts} words attempted in ${SECONDS} seconds - now exiting"
    else
        echo "${name}: exiting after ${SECONDS} seconds"
    fi
    exit
}

#return values used by readFD
messageIn=""
readSuccess=""
function readFD(){
    readSuccess=true
    verb=${1}
    read -t ${interval} -r messageIn <&$fd
    if  [[ $? != 0  || ${messageIn^^} =~ "ERROR" ]]   ; then
        echo "${name}: ${verb} did not work on ${ip} ${smtp_port}"
        readSuccess=false
    fi
    echo "${name}: ${verb} response: ${ip} ${smtp_port} $messageIn"
}

reconnectCounter=0
function sendCommand(){
    command_name=${1}
    smtp_command=${2}
    echo "${name}: ${command_name} command: ${ip} ${smtp_port} ${smtp_command}"
    if ! echo -e "${smtp_command}"  >&$fd; then
        #reconnect
        reconnectCounter=$((reconnectCounter+1)) 
        echo "${name}: ${attempts} words attempted in ${SECONDS} seconds - now reconnecting ${ip} ${port} #${reconnectCounter}"
        eval 'exec {fd}<>/dev/tcp/"${ip}"/"${smtp_port}"'  2>/dev/null
        testConnectionAttempt $? "${name}: ERROR: cannot open connection after disconnect"
        if test -z "$fd" ; then
            logerror "${name} ERROR: Connection did not open"
            exit 1
        else
            echo "${name}: Connection established: ${ip} ${smtp_port}"
        fi
        read  -t ${interval} -r messageIn <&$fd
        testConnectionAttempt $? "ERROR: no incoming data from connection"
        echo "${name} Received: ${ip} ${smtp_port} $messageIn"
        sendCommand "${1}" "${2}"
    fi
}

firstVRFYPass=true
firstEXPNPass=true
VRFY=true
EXPN=true
function try_EXPN_VRFY(){
    userName=${1}
    attempts=$((attempts+1)) 
    if $( ${VRFY}) ; then
        sendCommand "VRFY" "VRFY ${userName}${domain}"
        readFD "VRFY"
        if [[ "${firstVRFYPass}" = true ]]; then 
            VRFY=${readSuccess}
        fi
    fi
    #NOTE: username isn't strictly the right wording for EXPN
    if $( ${EXPN}) ; then
        sendCommand "EXPN" "EXPN ${userName}"
        readFD "EXPN"
        if [[ "${firstEXPNPass}" = true ]]; then 
            EXPN=${readSuccess}
        fi
    fi
    firstVRFYPass=false
    firstEXPNPass=false
    if $(! ${EXPN})  &&  $(! ${VRFY}) ; then
        echo "${name}: EXPN and VRFY do not work"
        exit
    fi
}

debug "${name}: FD is $fd"

if test -z "$fd" ; then
    logerror "ERROR: Connection did not open"
    exit 1
else
    echo "${name} Connection established: ${ip} ${smtp_port}"
    trap "cleanup" HUP INT TERM EXIT QUIT
    read  -t ${interval} -r messageIn <&$fd
    testConnectionAttempt $? "ERROR: no incoming data from connection"
    echo "${name} Received: ${ip} ${smtp_port} $messageIn"
    for userName in ${users} ; do
        try_EXPN_VRFY "${userName}"
    done
    

    if [[ ! -z ${words} && "${recurse}" = false ]] ; then
        if [[ "${fileopencommand}" = cat ]] ; then
            while read -t 5 userName
            do
                try_EXPN_VRFY "${userName}"
            done < ${words}
        else
            for userName in $(${fileopencommand} ${words}) ; do
                try_EXPN_VRFY "${userName}"
            done
        fi
    fi

    if [[ ! -z ${words} && "${recurse}" = true ]] ; then
        wordcount=$(${fileopencommand} ${words} | wc -l)
        if [ ${wordcount} -eq 0 ] ; then 
            logerror "Input file contained zero words"
        fi
        firstPass=true
        bucket=0
        for userName in $(${fileopencommand} ${words}) ; do
            bucket=$((bucket+1)) 
            echo "${userName}" >> ${tmpoutdir}/${bucket}.words

            if $( ${firstPass})  ; then
                debug "${name} ${DIR}/smtpsweep.bash -w ${tmpoutdir}/${bucket}.words ${moreCommands} -n child-${bucket}"
                ${DIR}/smtpsweep.bash -w "${tmpoutdir}"/"${bucket}".words ${moreCommands} -n "child-${bucket}" &
            fi
            if [ ${bucket} -eq 10 ] ; then
                bucket=0
                firstPass=false
            fi;
        done
        debug "${name} Word list buckets done"
        debug "${name} Waiting on child processes to complete."
        wait
    fi
    exit
fi
