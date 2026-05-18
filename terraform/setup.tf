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

# LoadBalancer Service templates: render the additional-resource-tags annotation
# from local.tags so NLBs created by the EKS Auto Mode networking controller
# carry var.tags. Output paths intentionally match the original locations so
# README instructions ("kubectl apply -f examples/gpu") keep working.
locals {
  tags_csv = join(",", [for k, v in local.tags : "${k}=${v}"])
}

resource "local_file" "setup_gpu_lb_service" {
  content = templatefile("${path.module}/../examples/gpu/lb-service.yaml.tpl", {
    tags_csv = local.tags_csv
  })
  filename = "${path.module}/../examples/gpu/lb-service.yaml"
}

resource "local_file" "setup_neuron_whisper_gradio_ui" {
  content = templatefile("${path.module}/../examples/neuron/whisper-gradio-ui.yaml.tpl", {
    tags_csv = local.tags_csv
  })
  filename = "${path.module}/../examples/neuron/whisper-gradio-ui.yaml"
}
