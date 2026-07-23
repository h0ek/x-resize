# Security Policy

## Supported Versions

Security fixes are provided for the latest released version of the project.

| Version                    | Supported |
| -------------------------- | --------- |
| Latest release             | Yes       |
| Default development branch | Yes       |
| Older releases             | No        |

Before reporting an issue affecting an older version, verify whether it is still present in the latest release.

## Reporting a Vulnerability

Do not report security vulnerabilities through public GitHub issues, discussions, pull requests, or social media.

Please use GitHub's private vulnerability reporting feature:

1. Open the repository.
2. Go to **Security**.
3. Select **Report a vulnerability**.
4. Submit the report privately.

If private vulnerability reporting is unavailable, contact the maintainer through the security contact listed in the repository profile.

Include the following information when possible:

* affected version or commit;
* affected component or file;
* operating system and environment;
* vulnerability description;
* potential security impact;
* steps required to reproduce the issue;
* minimal proof of concept;
* relevant logs, screenshots, or error messages;
* suggested remediation, if available.

Do not include real credentials, private keys, access tokens, personal data, or data obtained from systems you do not own.

## Testing Guidelines

Security testing must be performed only against:

* your own local installation;
* systems you own;
* systems for which you have explicit authorization.

The following activities are not permitted:

* testing third-party deployments without authorization;
* accessing, modifying, or deleting other users' data;
* denial-of-service or resource-exhaustion testing;
* high-volume automated scanning;
* social engineering or phishing;
* persistence or lateral movement;
* publishing vulnerability details before coordinated disclosure is complete.

Stop testing and report the issue immediately if you gain access to sensitive data or capabilities beyond what is necessary to demonstrate the vulnerability.

## Disclosure Process

The maintainer will make a reasonable effort to:

* confirm receipt of the report;
* reproduce and assess the issue;
* keep the reporter informed about significant progress;
* prepare and release a fix when appropriate;
* coordinate publication of security information.

Please do not publicly disclose the vulnerability until a fix has been released or disclosure has been explicitly agreed upon.

Confirmed vulnerabilities may be handled through a GitHub Security Advisory. A CVE identifier may be requested when appropriate, but it is not guaranteed.

## Recognition and Rewards

This project does not currently operate a paid bug bounty program.

Reports submitted in good faith may receive public credit in the security advisory or release notes if the reporter requests it. Credit may be withheld when disclosure rules were not followed or the report contains no meaningful security impact.
