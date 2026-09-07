# Decisions

Why the solution looks the way it does. Written as I went, tidied at the end.
The commits cover *what* changed.

Status: in progress.

---

## Task 1 — Container image

Two-stage `Dockerfile`. Build stage on `golang:1.22.12-bookworm` runs `go vet` and
`go test ./...` before the build, so a broken test suite can't produce a tagged image —
worth doing while there's no CI yet. Then `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w"`
for a static, stripped binary.

Runtime stage is `gcr.io/distroless/static-debian12:nonroot`: the binary on top of CA
certs and `/etc/passwd`, nothing else. No shell, no package manager, no libc. Runs as
uid 65532, `ENTRYPOINT` in exec form so the binary is PID 1 and gets `SIGTERM` directly —
the app's drain sequence depends on that. ~13 MB.

`CGO_ENABLED=0` is what makes the static base possible in the first place; it also happens
to dodge the macOS dyld quirk the README mentions.

I looked at `scratch` (no certs, no `/etc/passwd`, no `/tmp` — you end up rebuilding what
distroless already gives you) and `alpine` (ships busybox and apk, bigger attack surface
for no benefit here). `chainguard/static` would have been a fine choice too; I went with
distroless on familiarity.

`GREETING_NAME` is not baked in. It's required and per-environment, and the app is designed
to fail fast without it — baking a default would just hide misconfiguration.

**Least sure about:** I pinned the builder to a patch tag but left the base on `:nonroot`
rather than a digest. For anything production-facing I'd pin both by digest and let
Renovate bump them. Also, I only build for the host arch (arm64) since the local kind
nodes are arm64 and there's no registry here; a real image would be a multi-arch manifest.

Verified locally: build and tests pass, container runs non-root as PID 1, `/healthz` stays
200 through warm-up while `/readyz` is 503 then flips to 200, and `SIGTERM` drains an
in-flight `/work` request before the process exits 0.

---

## Task 2 — Local Kubernetes cluster

`kind`, 1 control-plane + 2 workers, defined in `cluster/kind-config.yaml` with
`cluster/create-cluster.sh` (idempotent) and `delete-cluster.sh`.

Chose kind over k3d and minikube: multi-node in one Docker daemon with no VM,
sub-minute create/destroy, and `kind load docker-image` means no registry. k3d
would have been an equally reasonable pick. minikube's multi-node mode is
heavier and I've found it less reliable to reproduce.

Two things in the config are deliberate:

- **Node image pinned by digest**, not a tag. It's the multi-arch index for
  `kindest/node:v1.37.0` (kind 0.33.0's default), so the reviewer gets the exact
  same Kubernetes version on amd64 or arm64.
- **App scheduled onto workers only** — the control-plane keeps its `NoSchedule`
  taint. Otherwise "lose a node, stay up" in Task 3 isn't actually exercised
  because a 2-of-3 spread could include the control-plane.

For outside access I map host `8080` to node `30080` via `extraPortMappings` and
make the chart's Service a `NodePort` pinned to `30080`. This couples the cluster
config to one value in the chart, which I dislike, but the alternatives are
worse for a hand-off: an ingress controller is a lot of moving parts to install
and document, and `kubectl port-forward` isn't "reachable from outside the
cluster" so much as tunnelled into it. Reasoning repeated in Task 3.

Verified: `create-cluster.sh` brings up 3 Ready nodes from a clean state in
~30s; control-plane carries the taint; `localhost:8080` on the host maps to
`30080` on the control-plane container.

## Task 3 — Packaging

_TODO_

## Task 4 — Terraform

_TODO_

## Extensions — order and why

_TODO_

## What's missing / next

_TODO_
