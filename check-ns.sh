#!/bin/bash

# vars
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
OUTPUT_DIR=${SCRIPT_PATH}/out_dir
OBJECTS_NAMESPACED_LIST="statefulset,deployment,daemonset"
OBJECTS_GLOBAL_LIST="podsecuritypolicy"

OBJECTS_NAME_EXCLUDE_LIST="deployment.extensions/default-http-backend|deployment.extensions/nginx-ingress-controller"

# conftest image
CONFTEST_IMAGE=dockerpac/conftest:audit-k8s-apis

usage()
{
    echo -e "Usage: ${SCRIPT_NAME} -n [<NAMESPACE>|global] [--skip-get] [--skip-analyze]\n"
}

while [ "$1" != "" ]; do
    case $1 in
        -n | --namespace )      shift
                                NAMESPACE=$1
                                ;;
        -sg | --skip-get )      SKIP_GET=1
                                ;;
        -sa | --skip-analyze )  SKIP_ANALYZE=1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

if [ "$NAMESPACE" = "" ] ; then
    usage
    exit 1
fi

OUTPUT_FILE=${OUTPUT_DIR}/${NAMESPACE}/output.txt


# Funtion definition

function check_kubectl_exist () {
    if ! [ -x "$(command -v kubectl)" ]
    then
        echo -e "Error: kubectl is not installed.\n"
        exit 1
    fi
}

function check_namespace_exist () {
    if ! kubectl get ns $NAMESPACE > /dev/null 2>&1 
    then
        echo -e "Error: the namespace $NAMESPACE does not exist in the cluster...\n"
        exit 3
    fi
}


function get_k8s_objects () {
    if [ "${NAMESPACE}" = "global" ] ; then
        kubectl get -o=name $OBJECTS_LIST
    else
        kubectl -n $NAMESPACE get -o=name $OBJECTS_LIST | egrep -v "$OBJECTS_NAME_EXCLUDE_LIST"
    fi
}


function get_yaml_from_objects () {
    mkdir -p $OUTPUT_DIR 2> /dev/null
    for OBJECT in $K8S_OBJECTS
    do 
        mkdir -p $(dirname ${OUTPUT_DIR}/${NAMESPACE}/${OBJECT})
        OBJECT_NAME=$(echo $OBJECT | cut -d "/" -f1)
        FILE_NAME=$(echo $OBJECT | cut -d "/" -f2)
        if [ "${NAMESPACE}" = "global" ] ; then
            NS_KUBECTL=""
        else
            NS_KUBECTL="-n $NAMESPACE"
        fi
        (
            kubectl $NS_KUBECTL apply view-last-applied $OBJECT > ${OUTPUT_DIR}/${NAMESPACE}/$OBJECT_NAME/${FILE_NAME}.yaml
        )&
        sleep 0.2
    done
    wait
}

function test_yaml_against_policy () {
    if [ ! -d ${OUTPUT_DIR}/${NAMESPACE} ] ; then
	return 0
    fi
    for YAML in $(find ${OUTPUT_DIR}/${NAMESPACE}/* -type f -name "*.yaml" 2>/dev/null) ; do
      echo "Analyzing $YAML ..." >&2
      echo "$YAML ..."
      if [ ! -s ${YAML} ] ; then
          echo -e "\033[1;33mUNKNOWN\033[0m - ${YAML} could not be verified." 
      else
          cat $YAML | docker run -i --rm ${CONFTEST_IMAGE} test -
      fi
    done > $OUTPUT_FILE
}

## main

# check kubectl binary exists
check_kubectl_exist

if [ "${NAMESPACE}" = "global" ] ; then
    OBJECTS_LIST=$OBJECTS_GLOBAL_LIST
else 
    OBJECTS_LIST=$OBJECTS_NAMESPACED_LIST
    if [ "$SKIP_GET" != 1 ] ; then
        check_namespace_exist
    fi
fi

mkdir -p $(dirname ${OUTPUT_DIR}/${NAMESPACE})

# collect cluster yamls
echo -e "Getting objects - $NAMESPACE ... "
if [ "$SKIP_GET" = 1 ] ; then
    echo "skipped"
else
    echo -e "\nExcluding $OBJECTS_NAME_EXCLUDE_LIST"
    K8S_OBJECTS=$(get_k8s_objects)
    echo
    for OBJECT in $K8S_OBJECTS ; do
        echo -e "\t" $OBJECT
    done
    echo

    echo "Getting yaml for each object - $NAMESPACE ... "
    get_yaml_from_objects
    echo "done"
fi

# check yamls with policy
echo -e "\nAnalyzing objects - $NAMESPACE ... "
if [ "$SKIP_ANALYZE" = 1 ] ; then
    echo "skipped"
else
    test_yaml_against_policy

    if [ ! -f $OUTPUT_FILE ] ; then
      echo -e "\nNo eligible object found for $NAMESPACE"
    else

	    if $(egrep -q "FAIL|UNKNOWN" $OUTPUT_FILE)
	    then
	      echo -e "\nThe following failures have been found for $NAMESPACE (full output available in ${OUTPUT_FILE}):\n"
	      egrep "UNKNOWN|FAIL" $OUTPUT_FILE
	    else
	      echo -e "\nNo issues were found for $NAMESPACE, full result available in file $OUTPUT_FILE"
	    fi
    fi
fi

exit 0
