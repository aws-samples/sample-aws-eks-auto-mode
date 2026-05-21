---
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: gpu-nodeclass
spec:
  role: ${node_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${cluster_name}
  securityGroupSelectorTerms:
    - tags:
        aws:eks:cluster-name: ${cluster_name}
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
  name: gpu-nodepool
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: gpu-nodeclass
      requirements:
        - key: "eks.amazonaws.com/instance-family"
          operator: In
          values: ["g5", "g6", "g6e", "p5", "p5e"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
      taints:
        - key: "nvidia.com/gpu"
          value: "true"
          effect: NoSchedule
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
    budgets:
      - nodes: "10%"
