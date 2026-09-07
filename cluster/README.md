# Local cluster

A 3-node [kind](https://kind.sigs.k8s.io/) cluster: 1 control-plane + 2 workers.

## Why kind

- Multi-node in a single Docker daemon — no VMs, no extra hypervisor. Docker
  Desktop is the only prerequisite.
- Nodes are containers, so create/destroy is ~30s and cheap to redo.
- `kind load docker-image` side-loads a locally built image straight into the
  nodes, so this exercise needs no registry.

`k3d` would also have been fine. `minikube` multi-node is heavier and, in my
experience, less reliable to reproduce.

## Prerequisites

| Tool | Tested with |
|---|---|
| Docker Desktop | 29.x |
| kind | 0.33.0 |
| kubectl | 1.34+ |

`brew install kind kubectl`

## Create / destroy

```sh
./cluster/create-cluster.sh     # idempotent
./cluster/delete-cluster.sh
```

`create-cluster.sh` creates the cluster from `kind-config.yaml` (if it isn't
already up) and waits for every node to report `Ready`. kubectl context is set
to `kind-w3w-exercise`.

## Config notes (`kind-config.yaml`)

- **Node image is pinned by digest** (`kindest/node:v1.37.0@sha256:a1ed56…`), a
  multi-arch index, so the Kubernetes version is byte-identical on any machine
  and on either CPU arch.
- **The app runs only on the two workers.** The control-plane keeps its default
  `NoSchedule` taint. That's what makes "drain a worker, service stays up"
  (Task 3 anti-affinity, Extension D) a real test.
- **`extraPortMappings`: host `8080` → node `30080`.** The Helm chart's Service
  is `NodePort` pinned to `30080`; this mapping publishes it on the host. Reach
  the service at `http://localhost:8080/`. kube-proxy forwards a NodePort from
  any node, so mapping it on the control-plane still hits pods on the workers.
