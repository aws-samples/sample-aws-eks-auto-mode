resource "null_resource" "create_nodepools_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../nodepools"
  }
}

resource "local_file" "setup_graviton" {
  content = templatefile("${path.module}/../nodepool-templates/graviton-nodepool.yaml.tpl", {
    node_iam_role_name  = module.eks.node_iam_role_name
  })
  filename = "${path.module}/../nodepools/graviton-nodepool.yaml"
}

resource "local_file" "setup_gpu" {
  content = templatefile("${path.module}/../nodepool-templates/gpu-nodepool.yaml.tpl", {
    node_iam_role_name  = module.eks.node_iam_role_name
  })
  filename = "${path.module}/../nodepools/gpu-nodepool.yaml"
}
