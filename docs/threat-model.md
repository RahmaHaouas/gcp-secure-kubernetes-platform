# Secure Multi-Cluster Kubernetes Platform on GCP

## Purpose

This platform is designed from an explicit threat model rather than from a list of
tools. Each security control below answers a specific attack path. Where a control
has been validated by running the attack and confirming it fails, evidence is linked.

The starting point is a deliberately insecure baseline: a default GKE cluster, as
demonstrated in Google's own hardening lab (GSP496). On that baseline, three commands
are enough to go from a compromised pod to a root shell on the underlying node. This
document shows how each such path is closed.

## Status legend

| Symbol | Meaning |
|---|---|
| ✅ Validated | Attack was executed against the hardened cluster and failed. Evidence linked. |
| 🔧 Implemented | Control is defined in Terraform / manifests and deployed, but not yet exercised by a dedicated attack. |
| 📅 Planned | Control belongs to a later phase and is not yet implemented. |

---

## Threat catalog

| # | Threat | Attack vector | Countermeasure | Implemented in | Status |
|---|---|---|---|---|---|
| T1 | Theft of kubelet bootstrap credentials | SSRF / RCE in a pod → query the Compute metadata endpoint → read `kube-env` (CA_CERT, KUBELET_CERT, KUBELET_KEY) → escalate to cluster-admin | Workload Identity + `GKE_METADATA` mode (metadata concealment) | `terraform/modules/gke` | ✅ Validated |
| T2 | Pod escape to the node | RCE in a pod → mount host filesystem via `hostPath: /` → `chroot /rootfs` → root on the node | Pod Security Admission, `restricted` profile | `kubernetes/namespaces` | ✅ Validated |
| T3 | Privilege escalation via the node service account | Node runs with the default Compute SA, which holds the project-wide Editor role → a compromised pod inherits near-full project control | Dedicated node service account with 5 least-privilege roles (Artifact Registry read-only) | `terraform/modules/iam` | 🔧 Implemented |
| T8 | Exposed control plane | Kubernetes API server reachable from the public internet → brute force / exploit | Private nodes + master authorized networks (only the admin IP is allowed) | `terraform/modules/gke` | 🔧 Implemented |
| T4 | Lateral movement between services | A compromised pod opens connections to any other pod / service in the cluster | Default-deny NetworkPolicy (L3/L4) + Istio AuthorizationPolicy (L7) | `kubernetes/policies`, `kubernetes/istio` | 📅 Planned |
| T5 | Sniffing of internal traffic | Service-to-service traffic travels in clear text and can be intercepted | Istio strict mTLS | `kubernetes/istio` | 📅 Planned |
| T6 | Vulnerable image reaches production | An image carrying a known CVE is built and deployed with no gate | Trivy scan in CI with a blocking gate (`exit-code: 1` on CRITICAL/HIGH) | `.github/workflows` | 📅 Planned |
| T7 | Configuration drift | Manual `kubectl edit` in production silently diverges from the source of truth | GitOps with ArgoCD self-heal + Kyverno admission policies | `gitops/`, `kubernetes/policies` | 📅 Planned |

---

## Validated attacks (Phase 2)

### T1: Metadata credential theft is blocked

**Baseline (GSP496).** On a default cluster, a pod can read the bootstrap credentials
directly:

```
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/kube-env
# → full kube-env: CA_CERT, KUBELET_CERT, KUBELET_KEY  → escalate to cluster-admin
```

**Hardened cluster.** With Workload Identity and `GKE_METADATA` mode, the same request
against the sensitive endpoint fails, while a non-sensitive endpoint still works,
proving the metadata service is up but that only sensitive paths are concealed:

```
$ curl -s -H "Metadata-Flavor: Google" .../instance/attributes/kube-env
Not Found

$ curl -s -H "Metadata-Flavor: Google" .../instance/name
gke-gke-prod-gke-prod-pool-fe9266d6-tf8p
```

The test pod itself runs as `nobody`, confirming the non-root constraint is also
enforced. Evidence: `docs/evidence/metadata-concealed.png`.

### T2: Pod escape is blocked at admission

**Baseline (GSP496).** On a default cluster, a pod that mounts `hostPath: /` is created
successfully, after which `chroot /rootfs` yields a root shell on the node.

**Hardened cluster.** The same pod is rejected by Pod Security Admission before it is
ever scheduled. The `restricted` profile flags five independent violations at once:

```
Error from server (Forbidden): pods "attacker" is forbidden:
violates PodSecurity "restricted:latest":
  - allowPrivilegeEscalation != false
  - unrestricted capabilities (must drop ["ALL"])
  - restricted volume types (volume "rootfs" uses hostPath)
  - runAsNonRoot != true
  - seccompProfile
```

This is defense in depth: even if an attacker corrected the `hostPath` violation, four other constraints would still block the pod. Evidence: `docs/evidence/psa-blocked.png`.

---

## Implemented but not yet attack-tested

### T3: Node service account

By default, GKE attaches the Compute Engine default service account (Editor role) to every node. A single compromised pod could then act with Editor permissions across the whole project. The platform instead provisions a dedicated service account whose only roles are: `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer`, and `artifactregistry.reader` (pull only, never push). A dedicated validation is planned.

### T8: Control plane exposure

Nodes are private (no public IP) and the API server accepts connections only from the authorized admin IP via master authorized networks. Verified indirectly (the cluster is reachable from the admin workstation and nodes carry no external IP); an explicit from-elsewhere test is planned.

---

## Planned (Phases 3-7)

T4, T5, T6 and T7 depend on components introduced in later phases (a demo application to generate real service-to-service traffic, the CI pipeline, the service mesh, and the GitOps layer). Each will be validated the same way T1 and T2 were: run the attack, confirm it fails, capture the evidence.

---

## What "hardened" means here

Every control in this document maps to a concrete attack, and the two most dangerous paths on a default cluster are not merely configured but demonstrated to fail. That distinction, configured versus proven, is the point of this project.