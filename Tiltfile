# -*- mode: Python -*-

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
NAMESPACE    = 'postgres'
CLUSTER_NAME = 'pg-lab'
OPERATOR_NS  = 'cnpg-system'

# ---------------------------------------------------------------------------
# 1. Operator
#    Installed via local_resource so Tilt re-applies it whenever operator/
#    files change, but does not try to own CRDs as standard workloads.
# ---------------------------------------------------------------------------
OPERATOR_MANIFEST = 'operator/cnpg-1.25.1.yaml'
OPERATOR_URL      = 'https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.25.1/cnpg-1.25.1.yaml'

local_resource(
    name   = 'cnpg-operator-vendor',
    cmd    = '[ -f %s ] || curl -sSL %s -o %s' % (OPERATOR_MANIFEST, OPERATOR_URL, OPERATOR_MANIFEST),
    labels = ['operator'],
)

local_resource(
    name          = 'cnpg-operator',
    cmd           = 'kubectl apply -k operator/ --server-side --force-conflicts',
    deps          = ['operator/'],
    resource_deps = ['cnpg-operator-vendor'],
    labels        = ['operator'],
)

local_resource(
    name          = 'cnpg-operator-ready',
    cmd           = 'kubectl wait --for=condition=Available deployment/cnpg-controller-manager'
                    + ' -n %s --timeout=120s' % OPERATOR_NS,
    resource_deps = ['cnpg-operator'],
    labels        = ['operator'],
)

# ---------------------------------------------------------------------------
# 2. Cluster manifests
#    kustomize() renders cluster/ so Tilt watches every file under it and
#    re-applies on any change.
# ---------------------------------------------------------------------------
k8s_yaml(kustomize('cluster/'))

# --- Infrastructure objects (namespace, storageclass, secrets) -------------
k8s_resource(
    objects  = [
        'postgres:Namespace',                        # cluster-scoped — no namespace segment
        'postgres-ssd:StorageClass',                 # cluster-scoped — no namespace segment
        'cnpg-superuser-secret:Secret:' + NAMESPACE,
        'cnpg-app-secret:Secret:'       + NAMESPACE,
    ],
    new_name      = 'cluster-config',
    labels        = ['cluster'],
    resource_deps = ['cnpg-operator-ready'],
)

# --- CNPG Cluster CRD -------------------------------------------------------
k8s_resource(
    objects       = ['%s:Cluster:%s' % (CLUSTER_NAME, NAMESPACE)],
    new_name      = 'pg-lab-cluster',
    labels        = ['cluster'],
    resource_deps = ['cluster-config'],
)

# --- Adminer ----------------------------------------------------------------
k8s_resource(
    workload      = 'adminer',
    port_forwards = ['8080:8080'],
    labels        = ['cluster'],
    resource_deps = ['pg-lab-cluster'],
)
