variable "kubeconfig" {
  description = "Path to kubeconfig."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to deploy against."
  type        = string
  default     = "kind-w3w-exercise"
}

variable "greeting_name" {
  type = string
}

variable "replica_count" {
  type = number
}

variable "image_tag" {
  type = string
}

variable "node_port" {
  type = number
}
