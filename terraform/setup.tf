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
