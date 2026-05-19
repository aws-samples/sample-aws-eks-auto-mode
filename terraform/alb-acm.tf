# --------------------------------------------------------------------------
# Public exposure (opt-in via var.base_domain)
#
# When var.base_domain is empty (default), this entire file is inert and
# example workloads expose internal-scheme load balancers reachable only via
# kubectl port-forward.
#
# When set, we:
#   1. Look up the existing public Route53 hosted zone (must already exist).
#   2. Mint an ACM wildcard cert (*.<full_domain>) with apex SAN, DNS-validated.
#   3. Install external-dns (Helm) with a Pod-Identity-bound IAM role scoped
#      to ONLY this hosted zone (not Route53FullAccess).
#
# The ALB controller (bundled in Auto Mode) discovers the wildcard cert by
# matching each Ingress's host: against ACM cert SANs, so we never set
# certificateArn explicitly. external-dns owns the A/CNAME records.
# --------------------------------------------------------------------------

data "aws_route53_zone" "selected" {
  count        = local.enable_domain ? 1 : 0
  name         = var.base_domain
  private_zone = false
}

resource "aws_acm_certificate" "wildcard" {
  count                     = local.enable_domain ? 1 : 0
  domain_name               = "*.${local.full_domain}"
  validation_method         = "DNS"
  subject_alternative_names = [local.full_domain]

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "validation" {
  for_each = local.enable_domain ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected[0].zone_id
}

resource "aws_acm_certificate_validation" "wildcard" {
  count                   = local.enable_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

# --------------------------------------------------------------------------
# external-dns IAM role (Pod Identity), scoped to the SPECIFIC hosted zone.
# route53:ListHostedZones / route53:ListResourceRecordSets do not accept
# resource-level scoping per AWS docs, so they remain on "*".
# --------------------------------------------------------------------------
resource "aws_iam_role" "external_dns" {
  count = local.enable_domain ? 1 : 0
  name  = "${module.eks.cluster_name}-${var.region}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "external_dns" {
  count = local.enable_domain ? 1 : 0
  name  = "external-dns-zone-scoped"
  role  = aws_iam_role.external_dns[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = data.aws_route53_zone.selected[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count           = local.enable_domain ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}

# --------------------------------------------------------------------------
# external-dns Helm release. Uses Pod Identity association above (no IRSA
# annotation needed). Filters to the configured zone so unrelated records
# in the account are untouched.
# --------------------------------------------------------------------------
resource "helm_release" "external_dns" {
  count = local.enable_domain ? 1 : 0

  name             = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.15.0"

  values = [yamlencode({
    provider      = "aws"
    sources       = ["service", "ingress"]
    policy        = "sync"
    registry      = "txt"
    txtOwnerId    = "${module.eks.cluster_name}-${var.region}"
    domainFilters = [local.full_domain]
    extraArgs     = ["--aws-zone-type=public", "--exclude-record-types=AAAA"]
    env           = [{ name = "AWS_REGION", value = var.region }]
    serviceAccount = {
      create = true
      name   = "external-dns"
    }
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { memory = "64Mi" }
    }
  })]

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.external_dns,
  ]
}
