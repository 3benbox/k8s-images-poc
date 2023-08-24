# Kaniko build job

Proof of concept for providing docker images for kubernetes deployments from images built inside the cluster.

## Goals
- Self containement (no external dependencies)
- No Docker daemon requirement (security issues with running docker inside docker)
- Shorten build times by using a cache (preferably repository based)
- Simple self service (no need to setup a CI/CD pipeline)

## Upstream projects
[Kaniko](https://github.com/GoogleContainerTools/kaniko) is a tool to build container images from a Dockerfile, inside a container or Kubernetes cluster. Kaniko doesn't depend on a Docker daemon and executes each command within a Dockerfile completely and it doesn't require a privileged container.

[Registry](https://hub.docker.com/_/registry) is a Docker image registry, which is used to store the built images.

## How it works

With Kaniko and Registry we can build images from git repositories inside the cluster and push them to the registry. The build process is triggered by a Kubernetes job, which runs a container with Kaniko executor. The executor reads the Dockerfile and builds the image. The image is then pushed to the registry. The cache is stored in the registry, so it can be reused by other builds.

## Usage

The registry should be installed **once** in the cluster. The registry is used to store the built images. The registry is exposed as a service, so it can be accessed from any namespace in the cluster.

The provided kustomization file expects a namespace named `shared-servcies`, change the file if you want to use a different namespace.

```bash
kubectl create namespace shared-services
kubectl apply -k .
```

The build job can be triggered by creating a new job in any namespace in the cluster.

Edit the [./config.yaml](./config.yaml) file to specify the git source parameters and the image repositry parameters.


- DOCKER_FILE - path to the Dockerfile from the git repository root
- DOCKER_TARGET - target stage in the Dockerfile
- REPO_NAME - name of the image repository
- GIT_REVISION - git revision to checkout (branch, tag, commit hash) **not normalized atm**
- GIT_URL - git repository url

Below those settings is the script used to checkout the git repository in the case you need something different.

Start the build job by running:

```bash
kubectl create -f config.yaml
kubectl create -f kaniko-build-job.yaml
```

The build job will run in the background and will take some time to complete. You can check the status of the job by running:

```bash
kubectl get pods
kubectl logs <pod-name>
```

The last line of the pod logs is the image name, which was pushed to the registry.

Use that image name for a quick test.

```bash
kubectl run test \
  --image=registry.shared-services:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70
```

:dizzy_face:

```
  Warning  Failed     5m54s (x4 over 7m38s)   kubelet            Failed to pull image "registry.shared-services:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": rpc error: code = Unknown desc = failed to pull and unpack image "registry.shared-services:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": failed to resolve reference "registry.shared-services:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": failed to do request: Head "https://registry.shared-services:5000/v2/keramik-runner/manifests/sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": dial tcp: lookup registry.shared-services: no such host
```

So, the image is not accessible from the cluster. We need to expose the registry service to the cluster.

```bash
kubectl expose service registry \
  --type=LoadBalancer \
  --name=registry-lb \
  --namespace=shared-services
```

With the LoadBalancer address we can now run the test.

```
kubectl run test \
  --image=167.99.22.59:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70
```

:dizzy_face:

```
  Warning  Failed     7s    kubelet            Failed to pull image "167.99.22.59:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": rpc error: code = Unknown desc = failed to pull and unpack image "167.99.22.59:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": failed to resolve reference "167.99.22.59:5000/keramik-runner@sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": failed to do request: Head "https://167.99.22.59:5000/v2/keramik-runner/manifests/sha256:479bde8109befd03a336b3b88e313da34338aabe6e32d2dabccf92e515995a70": http: server gave HTTP response to HTTPS client
```

The image is not accessible via HTTP, HTTPS only.

The only way to make it work insecurely is to add the registry to the insecure registries list on the nodes.

:dead:

