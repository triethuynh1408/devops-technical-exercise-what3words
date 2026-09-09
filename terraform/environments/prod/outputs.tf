output "release" {
  value = {
    name        = module.greeter.release_name
    namespace   = module.greeter.namespace
    app_version = module.greeter.app_version
    url         = "http://localhost:8081/"
  }
}
