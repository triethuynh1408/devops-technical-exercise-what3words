output "release_name" {
  description = "Deployed Helm release name."
  value       = helm_release.greeter.name
}

output "namespace" {
  description = "Namespace the release is in."
  value       = helm_release.greeter.namespace
}

output "app_version" {
  description = "Image tag / VERSION the release is running."
  value       = var.image_tag
}
