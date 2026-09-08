# Terraform

Deploys the `greeter` Helm chart to the kind cluster, one release per
environment, via the `hashicorp/helm` provider.

```
terraform/
  modules/greeter/        the shared config: one helm_release, all knobs
  environments/dev/        provider + module call + terraform.tfvars
  environments/prod/       same, different tfvars
```

## Layout: module + per-env directories (not workspaces)

The module holds everything shared. Each environment directory is ~15 lines:
a provider block, a `module "greeter"` call, and a `terraform.tfvars` with the
four values that differ:

| | dev | prod |
|---|---|---|
| `greeting_name` | `dev team` | `what3words` |
| `replica_count` | 2 | 3 |
| `image_tag` | `dev` | `1.0.0` |
| `node_port` | 30080 → `localhost:8080` | 30081 → `localhost:8081` |

Everything else — probe timings, grace period, resources, security context — is
in the chart's `values.yaml` and defined exactly once.

Workspaces were the alternative and I didn't use them: they share one backend
and one provider config, the active workspace is CLI state you can forget, and
`terraform.workspace` conditionals spread through the code. Separate directories
give each environment its own state file and make "which environment am I
touching" impossible to get wrong. Reasoning in `DECISIONS.md`.

## Prerequisites

1. Cluster up: `./cluster/create-cluster.sh`
2. Images built and side-loaded: `./scripts/build-and-load.sh`

## Use

```sh
cd terraform/environments/dev     # or prod
terraform init
terraform apply
```

`apply` blocks (`wait = true`) until the release's pods are actually Ready, so a
green apply means the service is serving. Check:

```sh
curl http://localhost:8080/       # dev
curl http://localhost:8081/       # prod
```

Change something:

```sh
# edit terraform.tfvars, then
terraform apply
```

Tear down:

```sh
terraform destroy
```

## State

Local (`terraform.tfstate` per directory), git-ignored. `.terraform.lock.hcl` is
committed to pin the provider version. A real deployment would use a remote
backend with locking — see `DECISIONS.md`.
