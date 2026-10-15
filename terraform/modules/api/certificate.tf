# HTTPS without a domain (ADR 0008). Public certificates from ACM need a domain to validate, so until
# the client provides one we generate a self signed certificate for the load balancer's own DNS name
# and import it into ACM. Traffic is fully encrypted; only the "who issued this" check fails, which
# clients pass by trusting this certificate explicitly (curl --cacert) instead of turning checks off.
# When a domain exists: pass certificate_arn (an ACM certificate validated by DNS) and these go away.

locals {
  create_certificate = var.certificate_arn == null
  certificate_arn    = local.create_certificate ? aws_acm_certificate.self_signed[0].arn : var.certificate_arn
}

resource "tls_private_key" "self_signed" {
  count     = local.create_certificate ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count                 = local.create_certificate ? 1 : 0
  private_key_pem       = tls_private_key.self_signed[0].private_key_pem
  validity_period_hours = 24 * 90
  dns_names             = [aws_lb.this.dns_name]
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name  = aws_lb.this.dns_name
    organization = "Kestrel Microfinance Bank (self signed, no domain yet)"
  }
}

resource "aws_acm_certificate" "self_signed" {
  count            = local.create_certificate ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}
