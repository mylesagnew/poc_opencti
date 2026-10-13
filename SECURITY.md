# Security Policy

## Supported versions

Only the latest commit on `main` receives fixes. The pinned OpenCTI stack
(5.12.15) is for lab and proof-of-concept use only.

## Reporting a vulnerability

Please **do not** open a public issue for security problems in these scripts.

Report privately through GitHub's
[private vulnerability reporting](https://github.com/mylesagnew/poc_opencti/security/advisories/new).
You can expect an acknowledgement within 5 business days.

Vulnerabilities in OpenCTI itself, or in the upstream images, should go to the
relevant upstream project (for OpenCTI: https://github.com/OpenCTI-Platform/opencti/security).

## In scope

- Secret generation, storage, or exposure by `opencti-install.sh`
- Services published to the network unintentionally
- Unsafe commands run with `sudo`

## Known limitations (by design for a lab)

See [Security notes](README.md#security-notes): Elasticsearch security is
disabled, there is no TLS, and the image versions are pinned and ageing.
