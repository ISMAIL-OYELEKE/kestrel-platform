# ADR 0008: HTTPS without a domain: a self signed certificate for now, ACM when the domain arrives

Status: Accepted, 15 October 2026

## Context

The brief requires HTTPS only (item 6.3). The client has not provided a domain yet. AWS Certificate Manager only issues public certificates for domains we can prove we control, and the load balancer's own name (`*.elb.amazonaws.com`) belongs to AWS. The brief asks what exactly would change when the client provides a domain.

## Options considered

1. **HTTP only until there is a domain.** Fails the brief, and BVNs would cross the internet unencrypted.
2. **CloudFront in front, using its default `*.cloudfront.net` certificate.** Trusted by browsers, but the WAF for CloudFront must live in us-east-1, which breaks the eu-west-1 only rule.
3. **Self signed certificate imported into ACM and attached to the load balancer (chosen).**

## Decision

Terraform generates a private key and a certificate for the load balancer's DNS name, and imports both into ACM. The load balancer listens on 443 with TLS 1.2 and 1.3 only (`ELBSecurityPolicy-TLS13-1-2-Res-2021-06`; changed on 16 Oct from `ELBSecurityPolicy-TLS13-1-2-2021-06` to meet Security Hub control ELB.17, see docs/security-findings.md). Port 80 only returns a permanent redirect to HTTPS.

The certificate is a Terraform output. Clients save it and call the API with `curl --cacert kestrel-dev.pem https://...`. The connection is then encrypted **and** fully verified against that certificate. We never tell anyone to use `curl -k`, which turns verification off.

## What changes when the client provides a domain (for example `api.kestrelmfb.com`)

1. Request an ACM certificate for `api.kestrelmfb.com` in eu-west-1 with DNS validation, and add the CNAME record ACM gives to the client's DNS.
2. Set `certificate_arn` in `envs/prod/terraform.tfvars` to that certificate and apply. The self signed key and certificate are removed automatically, and nothing else in the stack changes.
3. Add a DNS record pointing `api.kestrelmfb.com` at the load balancer (an alias record if the domain is in Route 53).
4. Clients drop `--cacert`, because the certificate is now trusted by every browser and phone. ACM renews it automatically.

## Consequences

- The private key of the self signed certificate is stored in Terraform state. The state bucket is encrypted, versioned, blocked from public access and HTTPS only (ADR 0002). With a real domain, ACM keeps the key and it never appears in state.
- Browsers show a warning until the client provides a domain. The mobile and web front ends are not part of this assessment.
