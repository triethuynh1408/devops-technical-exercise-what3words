# Helm chart: `greeter`

Hand-written, not `helm create`. Every resource is here because something in the
brief needs it; nothing is scaffold.

## Resources

| File | Why it exists |
|---|---|
| `deployment.yaml` | The workload. Probes, grace period, spread and security context are all tuned to the app's documented startup/shutdown behaviour — see comments in the file and DECISIONS.md. |
| `service.yaml` | `NodePort`, so the service is reachable from outside the cluster with no ingress controller. nodePort is pinned to pair with `cluster/kind-config.yaml`. |
| `configmap.yaml` | All app config as env vars, out of the image. Changing it rolls the pods (checksum annotation on the Deployment). |
| `serviceaccount.yaml` | Dedicated identity, token not mounted — the app never calls the API server. |
| `pdb.yaml` | `minAvailable: 1` — keeps a node drain (Extension D) from taking the service to zero. |
| `_helpers.tpl` | ~20 lines: names + labels. |
| `NOTES.txt` | Post-install: how to reach it, how to watch a rollout. |

No Ingress, HPA, NetworkPolicy or ServiceMonitor — see "deliberately left out" in DECISIONS.md.

## Deploy

```sh
# 1. cluster (once)
./cluster/create-cluster.sh

# 2. build + side-load the images
./scripts/build-and-load.sh

# 3a. dev  -> http://localhost:8080
helm install greeter-dev  deploy/greeter -f deploy/greeter/values-dev.yaml  -n greeter-dev  --create-namespace

# 3b. prod -> http://localhost:8081
helm install greeter-prod deploy/greeter -f deploy/greeter/values-prod.yaml -n greeter-prod --create-namespace
```

Task 4 does steps 3a/3b through Terraform instead; the chart is identical.

## Values that differ per environment

| | `values-dev.yaml` | `values-prod.yaml` |
|---|---|---|
| `config.greetingName` | `dev team` | `what3words` |
| `replicaCount` | 2 | 3 |
| `image.tag` | `dev` | `1.0.0` |
| `service.nodePort` | 30080 (host 8080) | 30081 (host 8081) |

Everything else comes from `values.yaml`.
