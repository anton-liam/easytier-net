.PHONY: up down test test-forward test-rollback logs shell-a shell-b shell-c shell-d

COMPOSE := docker compose -f docker-compose.yml

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down -v

test: test-forward test-rollback

test-forward:
	@bash scripts/test-gateway-forward.sh

test-rollback:
	@bash scripts/test-tunnel-down-rollback.sh

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
