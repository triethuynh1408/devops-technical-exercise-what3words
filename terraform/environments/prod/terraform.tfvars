# The prod environment. Only what differs from the chart defaults.
greeting_name = "what3words"
replica_count = 3
image_tag     = "1.0.0"
node_port     = 30081 # host localhost:8081 (cluster/kind-config.yaml)
