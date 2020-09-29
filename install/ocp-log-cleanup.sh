#!/bin/bash

set -e


WAIT_FOR_OBJECT_DELETION=${WAIT_FOR_OBJECT_CREATION:-60}

#Show connection 
oc project
echo ">>>Will proceed with deletion of objects in openshift-logging and opeshift-operators-redhat namespaces.You have 10 sec to press CTRL+C to cancel"
sleep 10

oc project openshift-logging
# Delete cluster logging object
if `oc get clusterlogging instance -n openshift-logging &> /dev/null`; then
    oc delete clusterlogging instance -n openshift-logging
    oc wait --for=delete clusterlogging instance -n openshift-logging --timeout=60s || true
fi 
# Checking if pods were terminating before deleting pvc 
echo ">>> Deleting PVC once all elastic search pods have been terminate ..."
tempCounter=0
while [[ `oc get pods -l name!=cluster-logging-operator -n openshift-logging --no-headers 2>/dev/null|wc -l` -gt 0 ]] \
&& \
[ ${tempCounter} -lt $((WAIT_FOR_OBJECT_DELETION/5)) ];do
  sleep 5
  echo "Waiting for all elasticsearch pods have been terminated ..." 
  let tempCounter=${tempCounter}+1
done
if [[ ${tempCounter} -eq $((WAIT_FOR_OBJECT_DELETION/5)) ]]; then 
    echo "PVC deletion operation has timed out..."
    exit 1
fi

if `oc get pvc -o name -n openshift-logging|grep elasticsearch &>/dev/null`; then
  oc delete `oc get pvc -o name -n openshift-logging|grep elasticsearch` -n openshift-logging
fi

# Cleanup CSV
echo ">>> Deleting CSV for cluster-logging ..."
if `oc get sub cluster-logging -n openshift-logging &>/dev/null`; then
  CSV_NAME=$(oc get sub cluster-logging -n openshift-logging -o jsonpath='{.status.installedCSV}')
  if `oc get csv ${CSV_NAME} -n openshift-logging &>/dev/null`; then
      oc delete csv ${CSV_NAME} -n openshift-logging 
  fi 
  # Cleanup subscription
  echo ">>> Deleting subscription for cluster-logging ..."
  oc delete sub cluster-logging -n openshift-logging 
fi

# Cleanup operatorgroups if any 
echo ">>> Deleting operatorgroup for cluster-logging ..."
if `oc get operatorgroups openshift-logging -n openshift-logging  &> /dev/null`; then
    oc delete operatorgroups openshift-logging -n openshift-logging
fi 

oc project openshift-operators-redhat 
# Cleanup CSV
echo ">>> Deleting CSV for elasticsearch ..."
if `oc get sub elasticsearch-operator -n openshift-operators-redhat &>/dev/null`; then
  CSV_NAME=$(oc get sub elasticsearch-operator -n openshift-operators-redhat -o jsonpath='{.status.installedCSV}')
  if `oc get csv ${CSV_NAME} -n openshift-operators-redhat &> /dev/null`; then
      oc delete csv ${CSV_NAME} -n openshift-operators-redhat
  fi 

  # Cleanup subscription
  echo ">>> Deleting subscription for elasticsearch ..."
  oc delete sub elasticsearch-operator -n openshift-operators-redhat
fi

echo ">>> Deleting operatorgroup for elasticsearch ..."
if `oc get operatorgroups openshift-operators-redhat -n openshift-operators-redhat  &> /dev/null`; then
    oc delete operatorgroups openshift-operators-redhat -n openshift-operators-redhat
fi 
