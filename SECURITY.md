# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.4.x   | :white_check_mark: |
| < 0.4   | :x:                |

These versions refer to the deployment artifacts in this repository (the Helm
chart `version`/`appVersion`), currently 0.4.0. No container image or chart has
been published yet: `core-source.env` pins no Streamline core commit, so the
single publisher has pushed nothing, and every deployment default here requires
an image you build and push yourself.

## Reporting a Vulnerability

Please report security vulnerabilities to **security@streamlinelabs.dev**.

**Do NOT open public issues for security vulnerabilities.**

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 5 business days
- **Fix Timeline**: Communicated after assessment

We follow responsible disclosure practices and will credit reporters (with permission) in our release notes.

## Security Best Practices

For production deployments, please review the [Streamline Security Documentation](https://github.com/streamlinelabs/streamline-docs).

### Chart security posture

- TLS and SASL authentication are **off by default**. SASL cannot be switched on
  against an image that does not advertise support for it: the chart fails the
  render instead of deploying an unauthenticated broker. A `custom` image must
  declare its capabilities explicitly; the chart never infers them. See
  `image.edition` in `helm/streamline/values.yaml`.
- The chart's TLS settings encrypt the **Kafka protocol listener (9092) only**.
  The HTTP API on 9094 (health, metrics, management) serves plaintext HTTP and
  is reached that way by the chart's own probes, so terminate HTTPS for it at an
  ingress, reverse proxy or service mesh. `tls.clientAuth` is mutual TLS for
  Kafka clients; nothing asks an HTTP client for a certificate.
- Listener ports are fixed (Kafka 9092, HTTP 9094). Values that appear to move a
  listener are rejected before rendering rather than producing a Service and
  NetworkPolicy that disagree with the running process.
- Official images are built only from the Streamline core commit pinned in
  `core-source.env`, by the single publisher workflow
  `.github/workflows/docker-publish.yml`. That workflow pushes a staging
  reference first and validates the resulting **digest** — strict smoke test,
  Trivy scan (CRITICAL/HIGH, failing), SBOM, cosign signature and SBOM/provenance
  attestations — before promoting that exact digest to the public tags and
  verifying each tag resolves back to it. A build that fails any check never
  becomes a release tag.
- `scripts/install.sh` is intentionally unavailable until a controlled endpoint
  and verified release archive set exist. Its entry point fails before any
  download or filesystem mutation. The retained future-release implementation
  has no checksum bypass and treats `--libc gnu|musl` as a requirement rather
  than silently installing the opposite flavour.
