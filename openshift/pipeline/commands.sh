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
curl -X GET -H 'Content-Type: application/JSON' http://el-petclinic-build-liberty-pipeline.apps-crc.testing -d '{}'