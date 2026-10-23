.PHONY: verify check-evidence
verify:
	bash scripts/build.sh
check-evidence:
	bash scripts/check-evidence.sh
