.PHONY: test-shared test-examples test-bench-smoke test-all test-ci bench-backends bench-backends-heavy

test-shared:
	./tests/run_shared_tests.sh

test-examples:
	./tests/run_example_smokes.sh

test-bench-smoke:
	./tests/unit_backend_bench_smoke.sh

test-all: test-shared test-examples

test-ci: test-all test-bench-smoke

bench-backends:
	./bench/run_backend_compare.sh

bench-backends-heavy:
	./bench/run_backend_compare_heavy.sh
