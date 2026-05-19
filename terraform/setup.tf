resource "null_resource" "create_nodepools_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../nodepools"
  }
}

resource "local_file" "setup_graviton" {
  content = templatefile("${path.module}/../nodepool-templates/graviton-nodepool.yaml.tpl", {
    node_iam_role_name = module.eks.node_iam_role_name
    cluster_name       = module.eks.cluster_name
    tags               = local.tags
  })
  filename = "${path.module}/../nodepools/graviton-nodepool.yaml"
}

resource "local_file" "setup_spot" {
  content = templatefile("${path.module}/../nodepool-templates/spot-nodepool.yaml.tpl", {
    node_iam_role_name = module.eks.node_iam_role_name
    cluster_name       = module.eks.cluster_name
    tags               = local.tags
  })
  filename = "${path.module}/../nodepools/spot-nodepool.yaml"
}

resource "local_file" "setup_gpu" {
  content = templatefile("${path.module}/../nodepool-templates/gpu-nodepool.yaml.tpl", {
    node_iam_role_name = module.eks.node_iam_role_name
    cluster_name       = module.eks.cluster_name
    tags               = local.tags
  })
  filename = "${path.module}/../nodepools/gpu-nodepool.yaml"
}

resource "local_file" "setup_neuron" {
  content = templatefile("${path.module}/../nodepool-templates/neuron-nodepool.yaml.tpl", {
    node_iam_role_name = module.eks.node_iam_role_name
    cluster_name       = module.eks.cluster_name
    tags               = local.tags
  })
  filename = "${path.module}/../nodepools/neuron-nodepool.yaml"
}

# Example workload templates: render LoadBalancer Service + Ingress YAMLs with
# var.tags injected so NLBs (via additional-resource-tags annotation) and ALBs
# (via per-example IngressClassParams.spec.tags) carry the cluster tags.
# Output paths intentionally match the original locations so README instructions
# ("kubectl apply -f examples/gpu") keep working.
locals {
  tags_csv  = join(",", [for k, v in local.tags : "${k}=${v}"])
  tags_yaml = "    ${indent(4, yamlencode([for k, v in local.tags : { key = k, value = v }]))}"
}

resource "local_file" "setup_gpu_lb_service" {
  content = templatefile("${path.module}/../examples/gpu/lb-service.yaml.tpl", {
    tags_csv      = local.tags_csv
    enable_domain = local.enable_domain
    domain        = local.full_domain
  })
  filename = "${path.module}/../examples/gpu/lb-service.yaml"
}

resource "local_file" "setup_neuron_whisper_gradio_ui" {
  content = templatefile("${path.module}/../examples/neuron/whisper-gradio-ui.yaml.tpl", {
    tags_csv      = local.tags_csv
    enable_domain = local.enable_domain
    domain        = local.full_domain
  })
  filename = "${path.module}/../examples/neuron/whisper-gradio-ui.yaml"
}

resource "local_file" "setup_graviton_2048_ingress" {
  content = templatefile("${path.module}/../examples/graviton/2048-ingress.yaml.tpl", {
    enable_domain = local.enable_domain
    domain        = local.full_domain
  })
  filename = "${path.module}/../examples/graviton/2048-ingress.yaml"
}

resource "local_file" "setup_spot_2048_ingress" {
  content = templatefile("${path.module}/../examples/spot/2048-ingress.yaml.tpl", {
    enable_domain = local.enable_domain
    domain        = local.full_domain
  })
  filename = "${path.module}/../examples/spot/2048-ingress.yaml"
}
