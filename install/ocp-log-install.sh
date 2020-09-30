#!/bin/bash

#set -ex


# Optional file to set environment variable to non-default values instead of defining them on shell session level. File myenv.sh should be located in 
# current directory 
#if [[ -f ./myenv.sh ]]; then 
#  echo ">>> myenv.sh file is present, setting some of the variables to non-default values"
#  . ./myenv.sh
#fi

# WAIT_FOR_OBJECT_CREATION - Time in seconds for script to wait for some of the required objects to be created in Kubernetes. Time out will cause script to exit
WAIT_FOR_OBJECT_CREATION=${WAIT_FOR_OBJECT_CREATION:-60}


function wait_for_csv_creation {
  OPERATOR_NAME=$1
  TARGET_NAMESPACE=$2
  TIMEOUT=$3

  # Unfortunately CSV object doesn't set status.conditions correctly for kubectl or oc wait command to work correctly. Replaced with while 
  echo ">>> Creating all required objects for subscription ${OPERATOR_NAME} in ${TARGET_NAMESPACE}..."
  tempCounter=0
  while [[ `oc get csv $(oc get subscription ${OPERATOR_NAME} -n ${TARGET_NAMESPACE} -o jsonpath='{.status.installedCSV}') -n ${TARGET_NAMESPACE} -o jsonpath='{.status.phase}'` != "Succeeded" ]] \
  && \
  [ ${tempCounter} -lt $((TIMEOUT/5)) ];do
    sleep 5
    echo "Waiting for all objects defined by subscription to be created ..." 
    let tempCounter=${tempCounter}+1
  done
  if [[ ${tempCounter} -eq $((TIMEOUT/5)) ]]; then 
      echo "OperatorSource creation has timed out..."
      exit 1
  fi
  echo ">>> **** Operator ${OPERATOR_NAME} has been installed ****"
}

oc project
echo ">>>Will proceed with creation of objects in openshift-logging and opeshift-operators-redhat namespaces.You have 5 sec to press CTRL+C to cancel"
sleep 5

# 1. Create namespace openshift-operators-redhat if doesn't exist
echo ">>> Create target namespace openshift-operators-redhat"
if ! `oc get project openshift-operators-redhat &>/dev/null`;then
    oc apply -f incluster/01_namespace_es.yaml
fi

# 2. Create namespace openshift-logging if doesn't exist
echo ">>> Create target namespace openshift-logging"
if ! `oc get project openshift-logging &>/dev/null`;then
    oc apply -f incluster/01_namespace_log.yaml
fi

# 3. Create OperatorGroup openshift-operators-redhat for elasticsearch
echo ">>> Creating operatorgroup openshift-operators-redhat"
if ! `oc get operatorgroup openshift-operators-redhat -n openshift-operators-redhat &>/dev/null` ; then
    oc apply -f incluster/02_elastic_og.yaml
fi


# 4. Adding subscription for elasticsearch operator with manual install plan 
echo ">>> Creating Subscription elasticsearch-operator ..."
if `oc get sub elasticsearch-operator -n openshift-operators-redhat &>/dev/null`; then
  echo "Subscrition elasticsearch-operator already exist, skipping creation..."
else
  oc apply -f incluster/03_elastic_sub.yaml
  oc wait subscription elasticsearch-operator -n openshift-operators-redhat --for=condition=InstallPlanPending --timeout="${WAIT_FOR_OBJECT_CREATION}s"
fi 
#exit 1

# 6. Approve install plan for subscription 
echo ">>> Approving installPlan for subscription elasticsearch-operator"
if [[ `oc get subscription elasticsearch-operator -n openshift-operators-redhat -o jsonpath='{.spec.installPlanApproval}'` == "Manual" ]]; then 
    oc patch installplan `oc get subscription elasticsearch-operator -n openshift-operators-redhat -o jsonpath='{.status.installplan.name}'` -n openshift-operators-redhat --type=json -p='[{"op":"replace", "path":"/spec/approved","value":true}]'
fi

(wait_for_csv_creation "elasticsearch-operator" "openshift-operators-redhat" ${WAIT_FOR_OBJECT_CREATION}) || exit $?


# 7. Create OperatorGroup openshift-logging for logging
echo ">>> Creating operatorgroup openshift-logging"
if ! `oc get operatorgroup openshift-logging -n openshift-logging &>/dev/null` ; then
    oc apply -f incluster/02_logging_og.yaml
fi

# 8. Adding subscription for cluster-logging operator with manual install plan 
echo ">>> Creating Subscription cluster-logging ..."
if `oc get sub cluster-logging -n openshift-logging &>/dev/null`; then
  echo "Subscrition cluster-logging already exist, skipping creation..."
else
  oc apply -f incluster/03_logging_sub.yaml
  oc wait subscription cluster-logging -n openshift-logging --for=condition=InstallPlanPending --timeout="${WAIT_FOR_OBJECT_CREATION}s"
fi 


# 9. Approve install plan for subscription 
echo ">>> Approving installPlan for subscription cluster-logging...."
if [[ `oc get subscription cluster-logging -n openshift-logging -o jsonpath='{.spec.installPlanApproval}'` == "Manual" ]]; then 
    oc patch installplan `oc get subscription cluster-logging -n openshift-logging -o jsonpath='{.status.installplan.name}'` -n openshift-logging --type=json -p='[{"op":"replace", "path":"/spec/approved","value":true}]'
fi

(wait_for_csv_creation "cluster-logging" "openshift-logging" ${WAIT_FOR_OBJECT_CREATION}) || exit $?

exit 0