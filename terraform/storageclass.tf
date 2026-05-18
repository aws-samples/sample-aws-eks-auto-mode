# EBS StorageClass for EKS Auto Mode. Replaces the legacy in-tree gp2
# StorageClass that ships with new clusters. Tags from var.tags are propagated
# to the underlying EBS volumes via the tagSpecification_N parameters (the EBS
# CSI driver / EKS Auto Mode CSI surfaces this as 1-indexed key-value pairs).
resource "kubectl_manifest" "storageclass_ebs" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "ebs"
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true"
      }
    }
    provisioner       = "ebs.csi.eks.amazonaws.com"
    volumeBindingMode = "WaitForFirstConsumer"
    parameters = merge(
      { type = "gp3" },
      { for i, k in keys(local.tags) : "tagSpecification_${i + 1}" => "${k}=${local.tags[k]}" },
    )
  })

  depends_on = [module.eks]
}

# The legacy gp2 StorageClass is created automatically by upstream Kubernetes /
# EKS and is marked default on fresh clusters. Delete it so the new ebs class
# above is the sole default and PVCs without an explicit className land on gp3.
resource "null_resource" "delete_gp2_storageclass" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} && \
      kubectl delete storageclass gp2 --ignore-not-found
    EOT
  }

  depends_on = [
    module.eks,
    kubectl_manifest.storageclass_ebs,
  ]
}
