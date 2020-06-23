# Audit usage of deprecated APIs on a Kubernetes cluster

The goal of this tool is to report usage of deprecated APIs in a Kubernetes cluster.

It consists of a Docker Image based on [Conftest](https://conftest.dev) that contains the rules to audit deprecated APIs and a couple of shell scripts that run the audit againt a particular cluster, and scripts based on work from [k8s-check-deprecated-apis](https://github.com/sturrent/k8s-check-deprecated-apis)


Build the Docker Image (Cluster Operator only)
---

```sh
# Build Docker Image
docker build -t dockerpac/conftest:audit-k8s-apis .

# Push to DTR (keep same repo:tag as it's used in the scripts)
docker push dockerpac/conftest:audit-k8s-apis
```

Audit an entire cluster (Cluster Operator Only)
---
```sh

# First source a UCP bundle to gain access to the cluster
source env.sh

# Run the check againt the entire cluster
./check-cluster.sh

```

Audit a namespace
---
```sh
# First source a UCP bundle to gain access to the cluster
source env.sh

# Run the check against the selected namespace
./check-ns.sh --namespace mynamespace

```
