# Security Policy

This is an educational demonstration. Do not place production credentials in the repository.

Report suspected vulnerabilities privately to the repository owner. Include the affected file,
impact, reproduction steps and a proposed remediation when possible.

The pipeline uses the automatically scoped `GITHUB_TOKEN`; it does not require long-lived
registry credentials. The verification job has read-only repository permission. Only the
default-branch publishing job receives `packages: write`.
