# Decisions

Why the solution looks the way it does. Written as I went, tidied at the end.
The commits cover *what* changed.

The per-task sections below were written straight after each task. The
cross-cutting sections (ambiguities, least sure about, production, left out)
come after Task 4.

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

---

## Task 3 — Packaging

Helm, hand-written. Chart in `deploy/greeter/`. Five templates plus a ~20-line
helpers file — Deployment, Service, ConfigMap, ServiceAccount, PDB. Chose Helm
over Kustomize mainly for Task 4: the Terraform `helm` provider is a single
`helm_release` per environment, whereas driving Kustomize from Terraform means
`kubectl_manifest` per object or a shell-out.

### Probes — the actual numbers

The app's contract (from `main.go` / `server.go`): `/healthz` is 200 from the
moment the listener binds; `/readyz` is 503 for `WARMUP_SECONDS` (30), then 200,
then 503 again the instant `SIGTERM` arrives; after `SIGTERM` it keeps serving
for `SHUTDOWN_DELAY_SECONDS` (10), then drains in-flight for up to
`DRAIN_TIMEOUT_SECONDS` (20), then exits 0.

- **readiness `/readyz`**: `period 2`, `failureThreshold 2` → a pod is pulled
  from the Service within ~5s of `SIGTERM`, well inside the 10s window the app
  gives you before it stops accepting connections. `initialDelaySeconds 3` — no
  need to wait out the warm-up, a failing readiness check just keeps the pod out
  of rotation, which is the correct state during warm-up anyway.
- **liveness `/healthz`**: `initialDelay 10`, `period 10`, `failureThreshold 3`
  → only restarts after ~30s of solid failure. Because `/healthz` is up
  independent of the warm-up, this can't false-fire during those 30s.
- **no `startupProbe`**: it would be inert here — `/healthz` passes ~1s in
  regardless of `WARMUP_SECONDS`, so liveness already can't trip during startup.
- **no `preStop` hook**: the app already does "fail readiness, then sleep" as its
  first shutdown step. A preStop sleep would stack on top and double the delay.

### `terminationGracePeriodSeconds: 45`

`SHUTDOWN_DELAY (10) + DRAIN_TIMEOUT (20) = 30`, + 15s headroom for kubelet and
the container runtime. If someone raises those three env values they must raise
this too — there's a loud comment in `values.yaml` saying so. I considered
computing it in the template (`add shutdownDelay drainTimeout 15`) and decided
an explicit number with a comment is easier to eyeball and justify.

### Staying up across a node loss

`topologySpreadConstraints`, `maxSkew: 1` on `kubernetes.io/hostname`,
`whenUnsatisfiable: ScheduleAnyway` (soft). Plus a PDB `minAvailable: 1` and a
rollout strategy of `maxUnavailable: 0 / maxSurge: 1`.

Rejected a hard `requiredDuringScheduling` podAntiAffinity: on a 2-worker
cluster it strands prod's third replica as `Pending` forever, and it can stall a
rollout because the surge pod has nowhere to land. Soft spread gives 1-1 for dev
and 2-1 for prod and never blocks scheduling. The cost is that a pod *can*
occasionally double up on a node (e.g. right after a drain); the next rollout
rebalances it. For a real cluster with three or more nodes I'd keep the soft
spread but could afford a hard anti-affinity too.

The PDB's `minAvailable: 1` is a floor, not "keep N-1". Draining a node with 2 of
prod's 3 pods on it will evict both and briefly leave prod at 1. That satisfies
"survive a single node" but for real prod I'd set `minAvailable` to a percentage
or `replicaCount - 1`.

### Config without rebuilding

Every setting is in a ConfigMap consumed via `envFrom`. `helm upgrade --set
config.greetingName=...` changes it, and a `checksum/config` annotation on the
pod template rolls the pods so they pick it up — without that, env-from-ConfigMap
changes leave running pods on stale values.

### Security context

The image is already non-root; the chart adds `runAsNonRoot`, `runAsUser 65532`,
`readOnlyRootFilesystem: true`, `cap drop ALL`, `allowPrivilegeEscalation:
false`, `seccompProfile: RuntimeDefault`. The app writes only to stdout, so a
read-only root filesystem needs no `emptyDir` for `/tmp` (verified — pods run
clean).

### Resources — the opinionated bit

Memory gets a request and a limit. CPU gets a request only, **no limit**. A CPU
limit on a small latency-sensitive HTTP service mostly buys you throttling under
burst for no real isolation benefit on a cluster that isn't oversubscribed. This
goes against the common "always set both" rule and I'd expect to defend it — in a
noisy multi-tenant cluster with hostile neighbours I'd add the limit back.

### Considered and rejected

- **Kustomize** — fine choice, base + `dev`/`prod` overlays. Lost to Helm on the
  Terraform integration story (above) and on `--set`/`checksum` ergonomics.
- **Ingress** — a controller to install, configure and document for one HTTP
  service on a local cluster. NodePort + a kind port-mapping is two lines and
  genuinely "outside the cluster". Would revisit for anything real (TLS, vhosts).
- **`kubectl port-forward`** as the access story — it's a tunnel into the
  cluster, not external reachability, and it dies with the terminal.
- **HPA** — no load-based scaling requirement, and it fights a Terraform-managed
  `replicaCount`. Out of scope.
- **ServiceMonitor / PrometheusRule in the chart** — belongs with Extension B,
  and shipping CRD-dependent templates that no-op without the operator installed
  is a trap. Plain `prometheus.io/scrape` annotations instead.

### Verified on the kind cluster

- `helm install` dev + prod side by side; dev on `localhost:8080`, prod on
  `localhost:8081`; all endpoints correct; pods land one-per-worker.
- `0/1` Ready for ~30s then Ready — readiness tracks the warm-up; **0 restarts**,
  so liveness never false-fired.
- **Rolling update under load** (`helm upgrade --set config.greetingName`):
  400/400 requests returned 200, greeting changed mid-stream, ConfigMap
  propagated.
- **`kubectl drain` of a worker under load** on `/work?ms=800` (in-flight
  requests): 168/168 returned 200; the evicted pod rescheduled onto the other
  worker; PDB allowed the drain without going to zero.

---

## Task 4 — Terraform

`hashicorp/helm` provider (matches the Task 3 choice), one `helm_release` per
environment. Structure: a shared `modules/greeter` plus thin
`environments/dev` and `environments/prod` root directories.

### Module + directories, not workspaces

The module is the shared configuration. Each environment directory is a provider
block, a module call, and a `terraform.tfvars` with the four values that differ
(`greeting_name`, `replica_count`, `image_tag`, `node_port`). The chart's
`values.yaml` still owns everything that doesn't vary, so nothing is defined
twice.

Rejected `terraform workspace`: all workspaces share one backend and one
provider config, the selected workspace is stateful CLI context that's easy to
forget, and you end up with `terraform.workspace` conditionals through the code.
Separate directories give each environment an isolated state file and make it
impossible to `apply` dev's config to prod by accident. The cost is that the two
`main.tf` files are near-identical boilerplate (~15 lines) — I'd rather repeat
that than the alternative.

### Things worth noting

- **`wait = true` + `atomic = true`.** `apply` blocks until the release's pods
  are Ready, so a green apply means the service is actually serving; a failed
  upgrade rolls back instead of leaving a half-applied release. `timeout` is 300s
  to clear the 30s warm-up plus the serial rollout of all replicas.
- **`replica_count` has a validation** rejecting anything below 2 — the
  single-node-loss guarantee depends on it, so it shouldn't be settable to 1.
- **Chart from a local path**, not a packaged/registry chart. Fine for this
  exercise; a real setup would `helm package` to a registry (OCI or ChartMuseum)
  and pin a chart version so infra state doesn't depend on the working tree.
- **Local state, git-ignored.** `.terraform.lock.hcl` is committed to pin the
  provider. Real: remote backend (S3+DynamoDB / GCS / TFC) with locking and
  per-env state isolation.
- **Image build/load is out of scope for Terraform.** `scripts/build-and-load.sh`
  is the prerequisite. Terraform deploys, it doesn't build images.

### Considered and rejected

- **`kubernetes` provider instead of `helm`** — would mean re-expressing every
  chart resource as a TF resource or using `kubernetes_manifest` (which needs the
  API reachable at plan time and handles CRDs badly). The chart already exists
  and is the Task 3 deliverable; wrapping it in one `helm_release` is far less
  code.
- **A single root module with a `for_each` over environments** — one `apply`
  touches both environments, which is exactly what you don't want for a
  dev/prod split. Blast radius should stop at one environment.
- **Terragrunt** — solves the boilerplate-duplication problem well, but it's
  another tool to install and learn for a reviewer, and the duplication here is
  ~15 lines. Not worth it at this size.

### Verified

- `terraform apply` in each directory creates the release and blocks ~32s until
  Ready; `curl localhost:8080` → "dev team", `localhost:8081` → "what3words".
- Re-plan is clean (`No changes`).
- Editing a tfvar (`greeting_name`, `replica_count`) produces an in-place update
  plan, not a replacement.

---

## Ambiguities in the brief, and what I assumed

- **"Reachable from outside the cluster."** On a kind cluster there is no real
  external load balancer. I read this as "reachable from the host by a
  documented, reproducible mechanism" and used a NodePort published to
  `localhost` via a kind port-mapping. If they meant a cloud LB / ingress with
  DNS, that's an ingress-controller task and out of scope for a local exercise.
- **"Without duplicating the whole configuration" (Task 4).** "The whole
  configuration" is fuzzy. I took it to mean the *app* configuration — probe
  timings, resources, chart structure — which is defined once in the chart. The
  ~15 lines of provider + module wiring repeated per environment directory is
  boilerplate, not configuration, and I accepted that over workspaces.
- **"GREETING_NAME (and other env vars) configurable per environment."** I made
  all six env vars values-driven through the ConfigMap, not just the greeting.
- **Image tag vs `VERSION`.** The app has a separate `VERSION` env var. I chose
  to set it equal to the image tag so `/version` and `greeter_build_info` never
  lie about what's running. Not stated; seemed obviously right.
- **`.gitignore`.** "Don't modify Go code under `app/`" — `.gitignore` isn't
  code, so I extended it for Terraform artefacts.
- **Commit granularity.** One commit per task. I've folded each task's
  `DECISIONS.md` section into that task's commit (the brief says write it as you
  go), and this consolidation pass is its own commit.
- **"At least two worker nodes."** Took "at least" literally and used exactly
  two. A third would make the anti-affinity story easier (see below) but isn't
  required.

## Least sure about

- **CPU limit omitted (Task 3).** Deliberate — a CPU limit mostly buys
  throttling on a cluster that isn't oversubscribed. What would change my mind:
  a shared/multi-tenant cluster with untrusted neighbours, or evidence of this
  service starving others. Then the limit goes back.
- **Soft topology spread (Task 3).** It can transiently put both dev replicas on
  one node (e.g. straight after a drain), which is a single point of failure
  until the next rollout. A hard `podAntiAffinity` fixes that but strands prod's
  third replica `Pending` on a 2-node cluster. What would change my mind: a
  cluster with ≥3 schedulable nodes — then hard anti-affinity is affordable.
- **PDB `minAvailable: 1`.** It's a floor, not "keep N−1", so draining a node
  holding 2 of prod's 3 pods drops prod to 1 briefly. Acceptable for "survive
  one node"; for real prod I'd use a percentage or `replicaCount - 1`.
- **NodePort couples `cluster/kind-config.yaml` to a chart value.** The nodePort
  numbers have to agree in two files. An ingress removes the coupling at the
  cost of a controller to run and document. Fine for a local hand-off; I'd
  reconsider for anything real.
- **Distroless base pinned by tag, not digest (Task 1); single-arch build.**
  Fine locally; a registry image should be digest-pinned and multi-arch.
- **`terminationGracePeriodSeconds` hard-coded at 45.** Safe for the default
  timings; if an operator raises `WARMUP`/`SHUTDOWN_DELAY`/`DRAIN_TIMEOUT` they
  must raise this too. Considered computing it in the template and chose an
  explicit, eyeball-able number with a comment instead.

## For a genuinely production-facing deployment

- **Image:** digest-pin base and builder, build multi-arch, sign with cosign,
  generate and publish an SBOM, gate the pipeline on a vulnerability scan, push
  to a real registry. Move `go test` out of the Dockerfile into a dedicated CI
  stage with its own cache.
- **Cluster:** a managed control plane (EKS/GKE/AKS), ≥3 nodes spread across
  availability zones, real ingress with TLS (cert-manager) and DNS
  (external-dns). Topology spread across zones, not just hostname.
- **Chart:** hard anti-affinity (affordable with ≥3 nodes), PDB as a percentage,
  a NetworkPolicy (kind's default CNI doesn't enforce them, so there's no point
  here), resource limits revisited per tenancy model, HPA if load actually
  varies, a ServiceMonitor once the Prometheus operator is a given.
- **Terraform:** remote backend (S3+DynamoDB / GCS / TFC) with locking and
  per-env state isolation; consume the chart from a versioned registry, not a
  path, so infra state doesn't depend on the working tree; plan/apply in CI
  behind a manual approval; a real secret store if any secret config appears.
- **Delivery:** GitOps (Argo CD / Flux) as the only way changes reach the
  cluster — no local `terraform apply` against prod. Drift detection and alerts.
- **Observability:** Prometheus operator + Grafana dashboards, alert routing to
  an on-call tool, SLO-based alerting rather than a raw error-rate threshold.

## Deliberately left out

- **Ingress / TLS / DNS** — NodePort + kind port-mapping is enough to be
  genuinely reachable from the host, with nothing extra to install.
- **HPA** — no load-based scaling requirement, and it fights a
  Terraform-managed `replicaCount`.
- **NetworkPolicy** — kind's default CNI (kindnet) doesn't enforce them, so
  adding one would be security theatre.
- **Secrets management** — this service has no secret config (`GREETING_NAME`
  isn't sensitive). A ConfigMap is the honest representation.
- **Multi-arch images** — no registry in the loop, and the host is single-arch.
- **Remote Terraform backend** — local state is fine for a single operator on a
  local cluster.
- **`helm test` hooks** — the rolling-update and node-drain tests I ran by hand
  exercise far more than a smoke test would.
- **Log aggregation / structured-logging config** — the app already logs
  structured lines to stdout; there's no log stack on a kind cluster to ship to.

---

## Extensions — order and why

Order: **D → A → B → C**.

- **D (prove it survives) first.** It's the cheapest — the node-drain and
  rolling-update scenarios were already most of the way there from Task 3
  testing — and it's the highest-confidence thing to nail down, because it
  directly validates the core deliverable. If the packaging were wrong, this is
  where it shows. Low cost, de-risks everything above it.
- **A (CI) second.** Table-stakes for the role and it protects every future
  change: `go test`, image build, `helm lint`, `terraform fmt`/`validate`,
  a config-render check. Medium cost, permanent value.
- **B (observability) third.** The brief's intro asks for "operable", and this
  is the half that isn't covered by probes and a PDB. Costs more (stand up a
  Prometheus, write and demo an alert) so it comes after the two cheaper wins.
- **C (GitOps) last.** Highest plumbing cost (install a controller, wire repo
  access) and the brief explicitly says document-and-move-on is acceptable if
  auth eats time — so it's the right one to run out of runway on.

### Done

- **D — done.** `scripts/soak.sh` + `scripts/prove-node-drain.sh` +
  `scripts/prove-rolling-update.sh`, evidence in `evidence/`. Node drain:
  140/140 requests (in-flight `/work?ms=500`) returned 200. Rolling update:
  140/140 returned 200. Both transcripts committed.

## What's missing / next

- **Extensions A, B, C not done** (time-box). A is next: a GitHub Actions
  workflow running `go test`, image build, `helm lint`, `terraform fmt -check`
  and `validate`, and a `helm template | kubeconform`-style render check.
- **B:** a minimal Prometheus scraping `/metrics` via the pod annotations the
  chart already sets, one alert rule (high 5xx rate over a short window), shown
  firing with `/boom`.
- **C:** Argo CD or Flux pointed at `deploy/greeter`. If repo auth is slow,
  document the intended `Application` / `Kustomization` and stop.
- The soft-spread "two replicas on one node" behaviour would get a proper fix
  on a ≥3-node cluster (hard anti-affinity) — noted under "least sure about".
