# Everything the deployment of one environment needs. The shared, non-varying
# configuration (probe timings, grace period, resources, security context) is
# NOT here — it lives once in the chart's values.yaml.

variable "release_name" {
  description = "Helm release name."
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy into. Created if absent."
  type        = string
}

variable "greeting_name" {
  description = "GREETING_NAME for the service. Differs per environment."
  type        = string
}

variable "replica_count" {
  description = "Number of pod replicas. Differs per environment."
  type        = number

  validation {
    condition     = var.replica_count >= 2
    error_message = "replica_count must be at least 2 so the service survives one node loss."
  }
}

variable "image_tag" {
  description = "Image tag to run. Also becomes the app's VERSION string."
  type        = string
}

variable "node_port" {
  description = "NodePort for the Service, matched to a host port mapping in cluster/kind-config.yaml."
  type        = number
}

variable "wait_timeout" {
  description = "Seconds to wait for the release to become Ready. Must exceed WARMUP_SECONDS plus rollout time."
  type        = number
  default     = 300
}
