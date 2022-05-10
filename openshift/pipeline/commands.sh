#!/bin/bash
oc new-project liberty-pipeline
podman login quay.io
oc create secret generic quay.io-push --from-file=.dockerconfigjson=${XDG_RUNTIME_DIR}/containers/auth.json --type=kubernetes.io/dockerconfigjson
oc patch serviceaccount pipeline -p '{"secrets": [{"name": "quay.io-push"}]}'
oc get serviceaccount pipeline -oyaml
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
{
  "level": "error",
  "ts": "2022-05-10T09:26:38.903Z",
  "logger": "eventlistener",
  "caller": "sink/sink.go:405",
  "msg": "failed to ApplyEventValuesToParams: failed to replace JSONPath value for param git-repo-url: $(body.repository.url): repository is not found",
  "commit": "8b4da3f",
  "eventlistener": "petclinic-build",
  "namespace": "liberty-pipeline",
  "/triggers-eventid": "d7a75449-702a-46a6-aecb-7faa154525c6",
  "eventlistenerUID": "1bbb812b-2525-4fb8-a746-85561e577bf7",
  "/trigger": "petclinic-build",
  "stacktrace": "github.com/tektoncd/triggers/pkg/sink.Sink.processTrigger\n\t/opt/app-root/src/go/src/github.com/tektoncd/triggers/pkg/sink/sink.go:405\ngithub.com/tektoncd/triggers/pkg/sink.Sink.HandleEvent.func1\n\t/opt/app-root/src/go/src/github.com/tektoncd/triggers/pkg/sink/sink.go:196"
}

curl -sX POST -H 'Content-Type: application/json' "${EVENT_LISTENER_URL}" -d@webhook.json | jq -r

EVENT_LISTENER_URL=$(oc get route el-petclinic-build --template='{{printf "http://%s" .spec.host}}')