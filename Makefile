.PHONY: bootstrap fixtures runtime-fixtures test perf-test

bootstrap:
	./scripts/bootstrap_gtc.sh

fixtures:
	./scripts/generate_fixtures.sh

runtime-fixtures:
	./scripts/generate_runtime_fixtures.sh

test:
	bash ci/local_check.sh

perf-test:
	bash ci/perf_test.sh
