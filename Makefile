.PHONY: help \
        tilt-up tilt-down tilt-ci \
        operator-vendor operator-install operator-wait operator-delete \
        cluster-install cluster-delete cluster-restart \
        install delete \
        status pods events \
        psql psql-ro \
        logs logs-primary \
        backup-list

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CLUSTER_NAME      := pg-lab
NAMESPACE         := postgres
OPERATOR_NS       := cnpg-system
CNPG_VERSION      := 1.25.1
OPERATOR_MANIFEST := operator/cnpg-$(CNPG_VERSION).yaml
OPERATOR_URL      := https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v$(CNPG_VERSION)/cnpg-$(CNPG_VERSION).yaml

# Detect the primary pod dynamically
PRIMARY := $(shell kubectl get cluster $(CLUSTER_NAME) -n $(NAMESPACE) \
             -o jsonpath='{.status.currentPrimary}' 2>/dev/null)

# Colors
BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
CYAN  := \033[36m
YELLOW:= \033[33m
RED   := \033[31m

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help: ## Show this help
	@echo ""
	@echo "$(BOLD)CloudNativePG Lab$(RESET)"
	@echo ""
	@echo "$(YELLOW)Tilt (recommended for local development):$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^tilt[a-zA-Z_-]+:.*##/ { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Manual lifecycle (without Tilt):$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^(operator|cluster|install|delete)[a-zA-Z_-]*:.*##/ { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Operations (usable alongside Tilt):$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^(status|pods|events|logs|psql|backup)[a-zA-Z_-]*:.*##/ { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# ---------------------------------------------------------------------------
# Tilt
# ---------------------------------------------------------------------------
tilt-up: ## Start Tilt (watches files, auto-applies on change, port-forwards Adminer)
	tilt up

tilt-down: ## Stop Tilt and delete all resources it manages
	tilt down

tilt-ci: ## Run Tilt in CI mode (applies everything once, exits on success/failure)
	tilt ci

# ---------------------------------------------------------------------------
# Manual lifecycle (use these when running without Tilt)
# ---------------------------------------------------------------------------
operator-vendor: ## Download (vendor) the operator manifest for the pinned version
	@echo "$(BOLD)Vendoring CloudNativePG v$(CNPG_VERSION)...$(RESET)"
	curl -sSL $(OPERATOR_URL) -o $(OPERATOR_MANIFEST)
	@echo "$(GREEN)Saved to $(OPERATOR_MANIFEST)$(RESET)"

operator-install: operator-vendor ## [manual] Install the CloudNativePG operator
	@echo "$(BOLD)Installing CloudNativePG operator...$(RESET)"
	kubectl apply -k operator/ --server-side --force-conflicts

operator-wait: ## [manual] Wait until the operator deployment is Available
	@echo "$(BOLD)Waiting for operator to become ready...$(RESET)"
	kubectl wait --for=condition=Available deployment/cnpg-controller-manager \
	  -n $(OPERATOR_NS) --timeout=120s

operator-delete: ## [manual] Remove the CloudNativePG operator
	@echo "$(RED)Deleting CloudNativePG operator...$(RESET)"
	kubectl delete -k operator/ --ignore-not-found

cluster-install: ## [manual] Apply cluster manifests
	@echo "$(BOLD)Deploying cluster resources...$(RESET)"
	kubectl apply -k cluster/

cluster-delete: ## [manual] Delete cluster resources (PVCs kept)
	@echo "$(RED)Deleting cluster resources...$(RESET)"
	kubectl delete -k cluster/ --ignore-not-found

cluster-restart: ## Trigger a rolling restart of the cluster
	@echo "$(BOLD)Triggering rolling restart of $(CLUSTER_NAME)...$(RESET)"
	kubectl cnpg restart $(CLUSTER_NAME) -n $(NAMESPACE)

install: operator-install operator-wait cluster-install ## [manual] Full install: operator + wait + cluster
	@echo "$(GREEN)$(BOLD)All resources applied. Run 'make status' to check.$(RESET)"

delete: cluster-delete operator-delete ## [manual] Tear down cluster + operator (PVCs kept)
	@echo "$(GREEN)Done. To also remove PVCs:$(RESET)"
	@echo "  kubectl delete pvc -n $(NAMESPACE) --all"

# ---------------------------------------------------------------------------
# Operations — usable at any time, with or without Tilt
# ---------------------------------------------------------------------------
status: ## Show Cluster status and instance summary
	@echo "$(BOLD)Cluster:$(RESET)"
	kubectl get cluster $(CLUSTER_NAME) -n $(NAMESPACE) -o wide
	@echo ""
	@echo "$(BOLD)Pods:$(RESET)"
	kubectl get pods -n $(NAMESPACE) -l cnpg.io/cluster=$(CLUSTER_NAME) -o wide

pods: ## List all pods in the postgres namespace
	kubectl get pods -n $(NAMESPACE) -o wide

events: ## Show recent events in the postgres namespace (newest last)
	kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp'

logs: ## Stream logs from all cluster pods (primary + replicas)
	kubectl logs -n $(NAMESPACE) -l cnpg.io/cluster=$(CLUSTER_NAME) \
	  --all-containers --prefix --follow

logs-primary: ## Stream logs from the current primary only
	@echo "$(BOLD)Primary: $(PRIMARY)$(RESET)"
	kubectl logs -n $(NAMESPACE) $(PRIMARY) --follow

psql: ## Open a psql shell on the primary (read-write)
	@echo "$(BOLD)Connecting to primary ($(PRIMARY))...$(RESET)"
	kubectl exec -it -n $(NAMESPACE) $(PRIMARY) -- \
	  psql -U postgres app

psql-ro: ## Open a psql shell on a replica (read-only)
	$(eval REPLICA := $(shell kubectl get pods -n $(NAMESPACE) \
	  -l cnpg.io/cluster=$(CLUSTER_NAME),role=replica \
	  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null))
	@echo "$(BOLD)Connecting to replica ($(REPLICA))...$(RESET)"
	kubectl exec -it -n $(NAMESPACE) $(REPLICA) -- \
	  psql -U postgres app

backup-list: ## List ScheduledBackups and Backups in the cluster namespace
	kubectl get scheduledbackup,backup -n $(NAMESPACE)
