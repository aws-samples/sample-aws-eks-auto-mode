# --------------------------------------------------------------------------
# Five-layer tag propagation for EKS Auto Mode.
#
# Layer 1: provider default_tags (main.tf) — all TF-created resources
# Layer 2: EKS cluster_tags (eks.tf) — EKS primary security group
# Layer 3: NodeClass spec.tags (nodepool-templates/) — EC2/EBS/ENI from Auto Mode
# Layer 4: StorageClass tagSpecification (below) — PVC-created EBS volumes
# Layer 5: IngressClassParams (ingressclass.tf) — ALB/TG/Listener
#
# The IAM policy enabling custom tags on Auto Mode resources (required for
# Layers 3-5) is managed by the EKS module via enable_auto_mode_custom_tags
# (default true since module v20.31). No manual IAM policy needed.
#
# See claude-md/TAGGING.md for the full pattern explanation.
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# Layer 4: StorageClass for tagged EBS volumes
#
# PVCs without storageClassName land on the default StorageClass. We make
# that default a custom "ebs" class with tagSpecification_N parameters, so
# the EBS-CSI driver tags volumes at create time. The legacy in-tree gp2
# StorageClass is removed so "ebs" is the sole default. PVCs that explicitly
# request the EKS-Auto-managed gp3 class bypass this and produce untagged
# volumes (managed StorageClass cannot be mutated).
# --------------------------------------------------------------------------
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


# Layer 5 (ALB tagging) is handled per-example: each Ingress YAML in examples/
# is templated and rendered with var.tags injected into its IngressClassParams.
# This keeps the example self-documenting (the user sees IngressClassParams in
# the YAML they apply) and avoids the cluster-default-class footgun where an
# Ingress with an explicit ingressClassName bypasses a global default.
# See terraform/setup.tf and examples/{graviton,spot}/2048-ingress.yaml.tpl.
