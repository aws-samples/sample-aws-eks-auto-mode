---
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: odcr-gpu-nodeclass
spec:
  role: ${node_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${cluster_name}
  securityGroupSelectorTerms:
    - tags:
        aws:eks:cluster-name: ${cluster_name}
  capacityReservationSelectorTerms:
    - tags:
        purpose: ml-training
  tags:
    ${indent(4, yamlencode(tags))}
%{ if kms_key_id != "" ~}
  ephemeralStorage:
    kmsKeyID: ${kms_key_id}
%{ endif ~}
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: odcr-gpu-nodepool
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: odcr-gpu-nodeclass
      requirements:
        - key: "eks.amazonaws.com/instance-family"
          operator: In
          values: ["g6e", "p5"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
      taints:
        - key: "nvidia.com/gpu"
          value: "true"
          effect: NoSchedule
  limits:
    cpu: 500
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
    budgets:
      - nodes: "10%"
