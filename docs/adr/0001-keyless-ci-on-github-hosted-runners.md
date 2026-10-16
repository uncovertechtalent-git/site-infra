# ADR-0001: Keyless CI on GitHub-hosted runners; IAM only by the operator

- Status: accepted
- Date: 2026-10-15
- Decider: Stefan Coetzee

## Context

This repository is public: the pipeline is meant to be read and audited. Terraform needs AWS access to plan and apply. The options were:

1. **Applies only from the operator host**, the one machine with long-lived AWS credentials. Safe, but nothing runs in the open; a reader sees a plan summary pasted by hand.
2. **GitHub-hosted runners with GitHub OIDC.** Each job gets a short-lived token from GitHub and exchanges it for a role session. GitHub stores no AWS secret.
3. **A self-hosted runner** on an existing EC2 instance, close to the network. GitHub warns against self-hosted runners on public repositories: a pull request from a fork can run code on them. Runner groups can limit a runner to named repositories and workflows, but not to trusted triggers alone. And an instance that already runs other services would become reachable from CI.

## Decision

Option 2, with three limits.

- **Two Terraform roles.** The plan role trusts this repository's pull request tokens and only reads. The apply role trusts jobs of the `production` environment, which allows main and needs the owner's approval. Both match GitHub's immutable subject, which carries the numeric owner and repository ids (`repo:uncovertechtalent-git@257729892/site-infra@1421056340:pull_request`, `...:environment:production`): a repository renamed or re-created under the same name gets other ids and cannot assume the roles. The workflow never uses `pull_request_target`, and GitHub gives fork pull requests no OIDC token, so code from a fork never meets AWS.
- **IAM is the operator's.** Every role and the OIDC provider live in the bootstrap stack, which only the operator applies with the long-lived credentials (break-glass). The apply role has no IAM action, cannot write the bootstrap state or the tfvars, and cannot change the state bucket. Whatever runs in CI cannot widen its own access. `scripts/role-boundaries.sh` checks these limits with the IAM policy simulator.
- **Nothing private in the log.** Plan and apply output stays in files on the runner. The log, the job summary and the pull request comment carry counts per resource type. The tfvars (account id, zone ids, bucket names) come from the state bucket, and their values are masked before Terraform runs. The role ARNs and the state bucket name are GitHub secrets: not credentials, but GitHub masks only secrets in a step's log header, and the account id is in them.

Content deploys follow the same pattern: each site repository's main branch assumes a deploy role that can list and write its own bucket and invalidate its own distribution.

Self-hosted runners stay off the public path. The existing EC2 instance, which runs other services, is never a runner. A runner in the enterprise pattern is the next step ([ADR-0002](0002-self-hosted-runner-enterprise-pattern.md)), built after the cutover.

## Consequences

- A merge to main does nothing in AWS until the owner approves the apply job. That is one more click per infrastructure change, and the point of it.
- An IAM change (a new site's deploy role, a wider apply policy) needs the operator: a bootstrap plan in the pull request, then `scripts/tf.sh bootstrap apply` by hand.
- A pull request plan runs with `-lock=false`: it can read a state that an apply is changing at that moment. The plan is advice; the apply job plans again under the lock.
- GitHub's OIDC issuer and AWS STS are now in the path of every change. If either is down, the break-glass path still works.
