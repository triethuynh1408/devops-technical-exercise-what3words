locals {
  # The chart lives in the repo, not a registry. This path is relative to this
  # module directory: terraform/modules/greeter -> repo root -> deploy/greeter.
  chart_path = "${path.module}/../../../deploy/greeter"
}

resource "helm_release" "greeter" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  chart = local.chart_path

  # Only the per-environment differences are set here. Everything else is the
  # chart's values.yaml, so the shared config is defined exactly once.
  values = [yamlencode({
    replicaCount = var.replica_count
    image = {
      tag = var.image_tag
    }
    config = {
      greetingName = var.greeting_name
    }
    service = {
      nodePort = var.node_port
    }
  })]

  # Block until the release's pods are actually Ready. Combined with the
  # chart's readiness probe this means `terraform apply` only succeeds once the
  # service is genuinely serving. timeout has to clear WARMUP_SECONDS + the
  # rolling-update time for all replicas.
  wait    = true
  timeout = var.wait_timeout

  # A failed upgrade rolls back instead of leaving the release half-applied.
  atomic          = true
  cleanup_on_fail = true
}
