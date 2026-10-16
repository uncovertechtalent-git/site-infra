# ADR-0002: A self-hosted runner in the enterprise pattern

- Status: proposed (build after the machinebehavior.io cutover)
- Date: 2026-10-15
- Decider: Stefan Coetzee

## Context

Enterprises often run their infrastructure pipelines on their own runners. Their reasons: reach into private networks, egress from known addresses, data that must not leave the network, and audit of the build machines. This repository runs on GitHub-hosted runners with OIDC ([ADR-0001](0001-keyless-ci-on-github-hosted-runners.md)), and nothing in it needs a private network. The runner is built to show the pattern done right, next to the simpler one, without weakening it.

## Decision

- **Its own network.** A dedicated VPC with private subnets only. No inbound rule, no public address. Egress through a NAT gateway, or VPC endpoints where they exist (STS, S3). No route or peering to any other VPC or host, the existing EC2 instance included.
- **Ephemeral just-in-time runners.** A small controller asks GitHub for a just-in-time runner configuration per queued job, starts a fresh instance with it, and terminates the instance when the job ends. The runner takes one job and never sees a second one.
- **A runner group.** The repository lives in the organisation uncovertechtalent-git, where a runner group limits the runners to this repository and to named workflows.
- **Only trusted triggers.** The runner label is used only by jobs that run on push to main, on `workflow_dispatch`, or in the `production` environment. Pull request jobs, and fork pull requests above all, stay on GitHub-hosted runners.
- **Minimal instance identity.** IMDSv2 required, hop limit 1, so a container on the runner cannot reach the instance metadata. The instance role can only write its own logs and report itself done. AWS access for the job still comes from the job's OIDC role, exactly as on GitHub-hosted runners.
- **Pinned image.** The runner image is built from a pinned base image and the pinned runner version, and its digest is recorded.

## Threat model

| Threat | Path | Control |
|---|---|---|
| Code from a fork runs on the runner | a pull request from a fork | runner label only on push, dispatch and environment jobs; runner group limited to this repository; pull requests stay on GitHub-hosted runners |
| A job leaves something behind for the next one | a persistent runner | one job per instance, instance terminated after it |
| A job steals the instance's credentials | instance metadata service | IMDSv2 with hop limit 1; an instance role with no AWS access beyond its own logs |
| A compromised job moves sideways | the network | own VPC, no inbound, no route or peering to other hosts |
| A compromised job widens its AWS access | IAM | job roles from OIDC, apply role without IAM actions (ADR-0001) |
| Data leaves through egress | outbound traffic | egress through NAT or endpoints only, flow logs on |
| A tampered runner image | the build of the image | pinned base and runner version, recorded digest |
| The controller is abused to start instances | the controller's credentials | a GitHub App with the runner-administration permission only, and an AWS role that can only start the runner template in the runner subnet |

## Consequences

- Cost: instances per job, a NAT gateway or endpoints, the controller. All small at this volume, and visible on the spend dashboard.
- More moving parts to operate: the controller and the image builds.
- GitHub-hosted runners stay the default for everything that does not need the runner. A red-team exercise against the finished setup follows in its own session.
