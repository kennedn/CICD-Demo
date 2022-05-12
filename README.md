# Tekton pipeline

What is Tekton? The official documentation is here. There is a tutorial on using it in Openshift here

One option for building container images is to use a Tekton pipeline running within the Openshift cluster itself.

Pros:

Will always use the correct CPU architecture for the cluster
Does not require additional machines e.g. podman servers
Can integrate unit testing

Cons:

Puts extra workload on the cluster whilst running
Pipelines run multiple containers which must adhere to the resource quota
The cons can be mitigated by using a dedicated namespace for the pipeline and its test deployment.

# PetClinic Pipeline
I chose PetClinic as a test application for creating a mock CICD pipeline. There are 4 major tasks in the pipeline:

|Task | Description|
|-----|------------|
|fetch-repository|  Performs a git clone on a provided repository|
|build-java-test Runs| maven automated tests on the repository|
|build-java | Builds and packages a JAR file from source|
|build-image| Builds an open-liberty container with the compiled JAR|


Each individual task spins up a bespoke pod for the duration of the action with a shared workspace (mount point). This allows multiple actions to be performed against the same file-set as is seen in this pipeline. Pipelines are supposed to be generic enough that they could feasibly be reused within different projects, this pipeline should work with any maven source project.

## Pipeline

A pipeline can be broken down into 3 distinct sections; workspaces, params and tasks:

<details>
  <summary>pipeline.yml</summary>

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: maven-pipeline
spec:
  workspaces:
  - name: shared-workspace
  - name: maven-settings
  params:
  - name: GITHUB_REPO_URL
    description: >-
      The GitHub Repo of the Java Application
  - name: GITHUB_REPO_REVISION
    description: >-
      The GitHub revision to use
    default: master
  - name: MAVEN_CONTEXT
    description: >-
      The directory within the repository on which we want to execute maven goals
  - name: BUILDAH_REPO_URL
    description: >-
      The fully qualified image name e.g example.com/tekton-tutorial/greeter
  - name: BUILDAH_CONTEXT
    description: >-
      The base directory in which to run buildah commands
  tasks:
  - name: fetch-repository
    taskRef:
      name: git-clone
      kind: ClusterTask
    workspaces:
    - name: output
      workspace: shared-workspace
    params:
    - name: url
      value: $(params.GITHUB_REPO_URL)
    - name: subdirectory
      value: ""
    - name: deleteExisting
      value: "true"
    - name: revision
      value: $(params.GITHUB_REPO_REVISION)
  - name: build-java-test
    taskRef:
      name: maven
      kind: ClusterTask
    params:
    - name: GOALS
      value:
        - '-B'
        - 'test'
      name: CONTEXT_DIR
      value: $(params.MAVEN_CONTEXT)
    workspaces:
    - name: maven-settings
      workspace: maven-settings
    - name: source
      workspace: shared-workspace
    runAfter:
    - fetch-repository 
  - name: build-java
    taskRef:
      name: maven
      kind: ClusterTask
    params:
    - name: GOALS
      value:
        - '-B'
        - '-DskipTests'
        - 'package'
      name: CONTEXT_DIR
      value: $(params.MAVEN_CONTEXT)
    workspaces:
    - name: maven-settings
      workspace: maven-settings
    - name: source
      workspace: shared-workspace
    runAfter:
    - build-java-test
  - name: build-image
    taskRef:
      name: buildah
      kind: ClusterTask
    params:
    - name: IMAGE
      value: $(params.BUILDAH_REPO_URL)
    - name: CONTEXT
      value: $(params.BUILDAH_CONTEXT)
    workspaces:
    - name: source
      workspace: shared-workspace
    runAfter:
    - build-java
```

</details>

### Workspaces
Workspaces define a list of persistent volumes that are available to the individual tasks to consume. A given task may have a requirement for one or more workspaces to function, and define their own mappings of the 'global' pipeline workspaces. Workspaces provide what is essentially a volume mount where files can be downloaded and manipulated. This allows changes performed inside a task to persist after the task concludes.

### Params
Params are parameters that are required by the pipeline. As with the workspaces, individual tasks have mappings for each 'global' pipeline param that they wish to consume. For this pipeline example, params include details about the source git repository, destination quay repository and base directory for maven steps. An example of this is the fetch-repository step. It requires a github url and repository revision to be able to effectively clone a repository.

### Tasks
Tasks are repeatable stepping stones within a pipeline. Tekton comes with a large number of pre-bundled tasks, but bespoke tasks can be created where required. All the tasks used within this pipeline are pre-bundled tekton tasks. They are very similar to pipelines in that they require certain workspaces and params to function.

## Pipeline Run

A pipeline run is used to trigger a given pipeline, it defines and provided the required workspaces and parameters to trigger a given pipeline. The pipeline run for the maven pipeline defined above is as follows:

<details>
  <summary>pipeline-run.yml</summary>

```yaml
apiVersion: tekton.dev/v1beta1 
kind: PipelineRun 
metadata:
  generateName: maven-taskrun-
spec:
  podTemplate:
    securityContext:
      runAsNonRoot: false
      runAsUser: 0
  pipelineRef:
    name: maven-pipeline
  params: 
  - name: GITHUB_REPO_URL
    value: https://github.com/kennedn/CICD-Demo
  - name: GITHUB_REPO_REVISION
    value: spring
  - name: MAVEN_CONTEXT
    value: src/spring-petclinic
  - name: BUILDAH_REPO_URL
    value: quay.io/kennedn/cicd-demo
  - name: BUILDAH_CONTEXT
    value: src
  workspaces: 
  - name: maven-settings
    emptyDir: {}
  - name: shared-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
```

</details>

### Notable features:

- generatedName is used under .metadata, this appends random characters to the end of the provided name allowing for multiple pipeline runs without incurring a naming conflict.
- Parameters for the CICD-Demo project are supplied (this contains the petclinic source files)
- A volumeClaimTemplate is used near the end of the file to create an ad-hoc Persistent volume for use in the pipeline


# Commands

## Pipeline / Pipeline Run

Create a new project for the pipeline

```bash
oc new-project liberty-pipeline
```

Login to quay.io so that we store credentials locally, then create a .dockerconfigjson secret from the stored credentials so that the pipeline can write to our quay repo

```bash
podman login quay.io
oc create secret generic quay.io-push --from-file=.dockerconfigjson=${XDG_RUNTIME_DIR}/containers/auth.json --type=kubernetes.io/dockerconfigjson
```

The openshift-pipelines operator (which installs tekton), comes with a pre-defined service account used for pipeline work. We must patch our secret into this service account so that it inherits the secrets permissions

```bash
oc patch serviceaccount pipeline -p '{"secrets": [{"name": "quay.io-push"}]}'
```

Change directory to the subfolder that contains our .yml files and create the pipeline

```bash
cd openshift/pipeline
oc create -f pipeline.yml
```

Trigger a pipeline run to ensure the pipeline is functional. Triggering the pipeline is as simple as creating the pipeline-run.yaml object, as noted above, a random name is generated for this object so that multiple creations can happen without naming conflict

```bash
oc create -f pipeline-run.yml
```

### View from GUI:

<img src=media/Pipelinerun.gif width=600/>


The pipeline run can also be monitored via the tekton CLI took (tkn), this automatically switches to tailing the logs of the currently processing task

```bash
tkn pipelinerun logs -f
```
<img src=media/tkn-logs.gif width=600/>

</br>
</br>

# Webhooks
Webhooks are a mechanism that give web connected applications the ability to inform other systems about events that have occurred within the app. In the context of git repositories, most major online providers of git repositories implement webhooks as a way of informing other systems that things like pushes to the repo have occurred. With a configured repository, when a push action occurs the online repository will sent off a HTTP request to a configured endpoint to inform them of the push.

Tekton implement a suite of objects that allow it to listen for webhook HTTP calls and trigger things like pipeline runs on the back of said calls:

## Trigger-template
The trigger template is essentially a superset of the pipeline-run.yml. It defines parameters that will be accepted and then maps these into what is essentially our pipeline-run file from before.

<details>
  <summary>trigger-template.yml</summary>

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: petclinic-build
spec:
  params:
  - name: git-repo-url
    description: The git repository url
  - name: git-revision
    description: The git revision
  - name: git-repo-name
    description: The name of the deployment to be created / patched
  resourceTemplates:
  - apiVersion: tekton.dev/v1beta1 
    kind: PipelineRun 
    metadata:
      generateName: maven-image-build-
    spec:
      serviceAccountName: pipeline
      podTemplate:
        securityContext:
          runAsNonRoot: false
          runAsUser: 0
      pipelineRef:
        name: maven-pipeline
      params: 
      - name: GITHUB_REPO_URL
        value: $(tt.params.git-repo-url)
      - name: GITHUB_REPO_REVISION
        value: $(tt.params.git-revision)
      - name: MAVEN_CONTEXT
        value: src/spring-petclinic
      - name: BUILDAH_REPO_URL
        value: quay.io/kennedn/cicd-demo
      - name: BUILDAH_CONTEXT
        value: src
      workspaces: 
      - name: maven-settings
        emptyDir: {}
      - name: shared-workspace
        volumeClaimTemplate:
          spec:
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 1Gi
```
</details>

## Trigger-binding

The trigger binding is a mapping file that maps parameters passed in the JSON body of the webhook HTTP call

<details>
  <summary>trigger-binding.yml</summary>

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: petclinic-build
spec:
  params:
  - name: git-repo-url
    value: $(body.repository.url)
  - name: git-revision
    value: $(body.head_commit.id)
```
</details>

## Trigger

A trigger object connects a trigger binding to a trigger template, and also allows for the specification of a service account that controls permissions of the contained tasks. Something not covered in this trigger but worth considering is the concept of an interceptor, an interceptor can validate a given webhook to make sure it came from the correct origin before processing it further.

<details>
  <summary>trigger.yml</summary>

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: Trigger
metadata:
  name: petclinic-build
spec:
  serviceAccountName: pipeline
  bindings:
    - ref: petclinic-build
  template:
    ref: petclinic-build
```
</details>

## Event-listener
An event listener is a tekton object that listens for webhooks. It accepts a trigger as a parameter and will essentially create a pod and service that passes the information from any received HTTP events to the trigger.

<details>
  <summary>event-listener.yml</summary>

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: petclinic-build
spec:
  serviceAccountName: pipeline
  triggers:
    - triggerRef: petclinic-build
```
</details>

Create the webhook objects

```bash
oc create -f trigger-template.yml -f trigger-binding.yml -f trigger.yml -f event-listener.yml
```
The event listener that we just created now has a pod and a service but needs to be exposed so that it has connectivity outwith the cluster

```bash
oc expose svc el-petclinic-build
```

We can then get the URL for use in our webhook call, go-templates are quite powerful, here we use an in-line template to concatenate 'http://' with the route's URL

```bash
EVENT_LISTENER_URL=$(oc get route el-petclinic-build --template='{{printf "http://%s" .spec.host}}')
echo ${EVENT_LISTENER_URL}
> http://el-petclinic-build-liberty-pipeline.apps-crc.testing
```

We can then test the the event-listener is working as intended by sending a dummy curl call to it

```bash
# -s            = silent
# -X GET        = Sent a GET request
# -H 'Con...'   = Inform the server we are sending a JSON object in our data field
# -d '{}'       = Send an empty JSON object
# jq -r         = Pretty print the JSON response
curl -sX GET -H 'Content-Type: application/json' "${EVENT_LISTENER_URL}" -d '{}' | jq -r
> {
>   "eventListener": "petclinic-build",
>   "namespace": "liberty-pipeline",
>   "eventListenerUID": "1bbb812b-2525-4fb8-a746-85561e577bf7",
>   "eventID": "3af3315f-4de7-4de5-a778-93512f1b6dac"
> }
```

You can go one step further and monitor the logs from the event listener to see how it interprets the call it just received, looking at the msg field you can see that the call fails because we did not provide the required parameters in the JSON body in our call above

```bash
oc logs deploy/el-petclinic-build -f | jq
> {
>   "level": "error",
>   "ts": "2022-05-10T09:26:38.903Z",
>   "logger": "eventlistener",
>   "caller": "sink/sink.go:405",
>   "msg": "failed to ApplyEventValuesToParams: failed to replace JSONPath value for param git-repo-url: $(body.repository.url): repository is not found",
>   "commit": "8b4da3f",
>   "eventlistener": "petclinic-build",
>   "namespace": "liberty-pipeline",
>   "/triggers-eventid": "d7a75449-702a-46a6-aecb-7faa154525c6",
>   "eventlistenerUID": "1bbb812b-2525-4fb8-a746-85561e577bf7",
>   "/trigger": "petclinic-build",
>   "stacktrace": "github.com/tektoncd/triggers/pkg/sink.Sink.processTrigger\n\t/opt/app-root/src/go/src/github.com/tektoncd/triggers/pkg/sink/sink.go:405\ngithub.com/tektoncd/triggers/pkg/sink.Sink.HandleEvent.func1\n\t/opt/app-root/src/go/src/github.com/tektoncd/triggers/pkg/sink/sink.go:196"
> }
```


Due to this demo being ran on a local CRC cluster, I was not able to expose the route to the wider internet, which means I cannot directly trigger a webhook from the github repository for this demo, I instead created a minimalist JSON object locally using the properties of the local git repository and triggered a dummy webhook using curl.

Create the minimalist JSON webhook object

```bash
echo '{"repository": {"url": "'"$(git config --get remote.origin.url)"'"}, "head_commit": {"id": "'"$(git rev-parse HEAD)"'"}}' > webhook.json
jq -r <webhook.json
> {
>   "repository": {
>     "url": "https://github.com/kennedn/CICD-Demo"
>   },
>   "head_commit": {
>     "id": "53d8fb28ae5d04cd944e02db27e414ee8dc20718"
>   }
> }
```
Then send the webhook JSON on to the event listener

```bash
curl -sX POST -H 'Content-Type: application/JSON' "${EVENT_LISTENER_URL}" -d@webhook.json
```
All going well, this then triggers a pipeline run of the maven build pipeline within openshift:

<img src=media/webhook.gif width=800/>



 
