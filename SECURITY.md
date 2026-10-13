# Security policy

QBank holds a student's study history and signs in to a private server, so security and privacy reports are taken seriously and handled privately.

## Supported versions

Security fixes land only on the `main` branch of this repository. If you build the app yourself, rebuild from the latest `main` to pick up fixes.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting for this repository:

**<https://github.com/D-E-A-G/qbank/security/advisories/new>**

**Do not open a public issue, discussion, or pull request for a security or privacy finding.** This applies with extra force to anything involving sign-in, sessions, or a student's data: never post such findings, reproduction data, or screenshots publicly.

When reporting, please include what you can of: the affected file or flow, reproduction steps, the impact you believe is possible, and any suggested fix. Use synthetic data only; do not include real account or credential material in a report.

What to expect: this is a small, best-effort project with no bug bounty. You should receive an acknowledgment within a few days, and validated reports will be fixed on `main` and credited in the advisory if you wish.

## Scope

This repository contains only the iPhone client. Reports about the private QBank server may be sent through the same private route; they reach the same owner. Please do not probe the production server beyond what is needed to demonstrate a finding, and never attempt to access data that is not yours.
