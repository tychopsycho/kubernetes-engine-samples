#!/bin/bash
while :
do
  kubectl create -f ${1}
  sleep ${2:-10}
done
