# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report them privately through a
[GitHub Security Advisory](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository. We aim to acknowledge reports within a few business days and
will keep you informed as we work on a fix.

## Scope

Because this engine renders UI from server-supplied payloads, we take the
following especially seriously:

- Payloads that can crash or hang the client (the runtime is designed to degrade
  safely — a reproducible crash from a malformed payload is a bug).
- Bindings or actions that could exfiltrate data or trigger unintended
  navigation, requests, or device access.
- Any way a `custom.*` component or action could escape the host's intended
  sandbox.

## Supported versions

While the project is pre-1.0, security fixes are applied to the latest release
on the `main` branch.
