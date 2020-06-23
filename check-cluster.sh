#!/bin/bash

# vars
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
OUTPUT_DIR=${SCRIPT_PATH}/out_dir

OUTPUT_FILE=${OUTPUT_DIR}/output.txt

usage()
{
    echo -e "Usage: ${SCRIPT_NAME} [--skip-get] [--skip-analyze]\n"
}

ARGS_CHECK_NS=""
while [ "$1" != "" ]; do
    case $1 in
        -sg | --skip-get )      SKIP_GET=1
                                ARGS_CHECK_NS="$ARGS_CHECK_NS --skip-get"
                                ;;
        -sa | --skip-analyze )  SKIP_ANALYZE=1
                                ARGS_CHECK_NS="$ARGS_CHECK_NS --skip-analyze"
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

# Prompt if getting objects and OUTPUT_DIR already exists
if [ "${SKIP_GET}" != "1" ] ; then
	if [ -d "${OUTPUT_DIR}" ] ; then
		echo "${OUTPUT_DIR} already exists, overwrite ? [y/N]"
		printf "> "
		read REP
		if [ "${REP}" != "y" -a "${REP}" != "Y" ] ; then
			echo "Canceled"
			exit 0
		else
			rm -rf ${OUTPUT_DIR}
		fi
	fi
		
else
	echo "Using objects in ${OUTPUT_DIR}"
fi

# Funtion definition

function check_kubectl_exist () {
    if ! [ -x "$(command -v kubectl)" ]
    then
        echo -e "Error: kubectl is not installed.\n"
        exit 1
    fi
}

function get_namespaces () {
    kubectl get ns -o jsonpath='{.items[*].metadata.name}'
}


## main
if [ "$SKIP_GET" = "1" ] ; then
    NAMESPACE_LIST=$(ls -1 ${OUTPUT_DIR} 2>/dev/null | grep -v output.txt 2>/dev/null)
    if [ -z "${NAMESPACE_LIST}" ] ; then
      echo "Cannot get list of namespaces"
      exit 1
    fi
else
    # check kubectl binary exists
    check_kubectl_exist

    NAMESPACE_LIST=$(get_namespaces) 
    if [ -z "${NAMESPACE_LIST}" ] ; then
      echo "Cannot get list of namespaces"
      exit 1
    fi
    # Adding virtual "global" namespace for objects not namespaced
    NAMESPACE_LIST="global $NAMESPACE_LIST"
fi


start=$(date +%s)
for NAMESPACE in $NAMESPACE_LIST ; do
    printf "Analyzing namespace ${NAMESPACE} ... "
    start_ns=$(date +%s)
    ./check-ns.sh -n $NAMESPACE $ARGS_CHECK_NS > /dev/null 2>&1
    end_ns=$(date +%s)
    COUNT_FAIL=$(egrep -c "FAIL" ${OUTPUT_DIR}/${NAMESPACE}/output.txt 2>/dev/null)
    COUNT_UNKNOWN=$(egrep -c "UNKNOWN" ${OUTPUT_DIR}/${NAMESPACE}/output.txt 2>/dev/null)
    [[ "${COUNT_FAIL}" = "" ]] && COUNT_FAIL=0
    [[ "${COUNT_UNKNOWN}" = "" ]] && COUNT_UNKNOWN=0
    echo " $COUNT_FAIL FAIL, $COUNT_UNKNOWN UNKNOWN (took $(($end_ns - $start_ns))s)"
done
end=$(date +%s)

echo -e "\nThe following failures have been found :\n"
> ${OUTPUT_DIR}/output.txt
for NAMESPACE in $NAMESPACE_LIST ; do
    egrep "FAIL|UNKNOWN" ${OUTPUT_DIR}/${NAMESPACE}/output.txt 2>/dev/null | sed "s/^/${NAMESPACE} # /g" >> ${OUTPUT_DIR}/output.txt
done

cat ${OUTPUT_DIR}/output.txt | column -s '#' -t
COUNT_FAIL=$(grep FAIL ${OUTPUT_DIR}/output.txt 2>/dev/null | wc -l)
COUNT_UNKNOWN=$(grep UNKNOWN ${OUTPUT_DIR}/output.txt 2>/dev/null | wc -l)
echo -e "\nResults :"
echo "$(ls -1 ${OUTPUT_DIR} | grep -v output.txt | wc -l) namespaces analyzed - $(cat ${OUTPUT_DIR}/output.txt | grep FAIL | awk ' { print $1 } ' | sort | uniq -c | wc -l) namespaces with at least 1 FAIL"
echo "$COUNT_FAIL FAIL, $COUNT_UNKNOWN UNKNOWN (took $(($end - $start))s)"
echo "Top 10 namespaces with FAIL :"
cat ${OUTPUT_DIR}/output.txt | grep FAIL | awk ' { print $1 } ' | sort | uniq -c | sort | tail -10

exit 0

# TODO
# Créer un repo avec les policies et un Dockerfile qui build l'image avec les policies
# Créer un repo avec un pipeline qui applique les policies
