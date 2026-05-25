.PHONY: up down test test-forward test-rollback test-restore test-cleanup logs shell-a shell-b shell-c shell-d

COMPOSE := docker compose -f docker-compose.yml

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down -v

test: test-forward test-rollback test-restore test-cleanup

test-forward:
	@bash scripts/test-gateway-forward.sh

test-rollback:
	@bash scripts/test-tunnel-down-rollback.sh

test-restore:
	@bash scripts/test-policy-restore.sh

test-cleanup:
	@bash scripts/test-process-exit-cleanup.sh

logs:
	$(COMPOSE) logs -f

shell-a:
	$(COMPOSE) exec node-a sh

shell-b:
	$(COMPOSE) exec node-b sh

shell-c:
	$(COMPOSE) exec web bash

shell-d:
	$(COMPOSE) exec client-d bash
