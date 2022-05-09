#!/bin/bash
oc new-project liberty-pipeline
podman login quay.io
oc create secret generic quay.io-push --from-file=.dockerconfigjson=${XDG_RUNTIME_DIR}/containers/auth.json --type=kubernetes.io/dockerconfigjson
oc patch serviceaccount pipeline -p '{"secrets": [{"name": "quay.io-push"}]}'
cd openshift/pipeline
oc create -f pipeline.yml
oc create -f pipeline-run.yml
tkn pipelinerun logs -f
oc create -f trigger-template.yml -f trigger-binding.yml -f trigger.yml -f event-listener.yml
EVENT_LISTENER_URL=$(oc get route el-petclinic-build --template='{{printf "http://%s" .spec.host}}')
# echo $EVENT_LISTENER_URL
# http://el-petclinic-build-liberty-pipeline.apps-crc.testing
curl -sX GET -H 'Content-Type: application/json' "${EVENT_LISTENER_URL}" -d '{}' | jq -r
{
  "eventListener": "petclinic-build",
  "namespace": "liberty-pipeline",
  "eventListenerUID": "1bbb812b-2525-4fb8-a746-85561e577bf7",
  "eventID": "3af3315f-4de7-4de5-a778-93512f1b6dac"
}
oc logs deploy/el-petclinic-build -f | jq
curl -sX POST -H 'Content-Type: application/JSON' "${EVENT_LISTENER_URL}" -d@github_webhook.json | jq -r-