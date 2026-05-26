---
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: spot-nodeclass
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
  name: spot-nodepool
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: spot-nodeclass
      requirements:
        - key: "eks.amazonaws.com/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["arm64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot"]
      taints:
        - key: "spot"
          value: "true"
          effect: "NoSchedule"
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
    budgets:
      - nodes: "10%"
