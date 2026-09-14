SHELL := /bin/sh

.PHONY: help setup test lint security ci

help:
	@printf '%s\n' 'Targets: setup test lint security ci'

setup:
	python -m pip install pytest

test:
	python -m pytest -q

lint:
	@grep -q '#requires -Version 7.0' install-openssh.ps1
	@grep -q 'Format-List | Out-Host' install-openssh.ps1

security:
	@if git ls-files | grep -E '(^|/)(\.env|id_rsa|id_ed25519|.*\.pem|.*\.key)$$' | grep -v '^\.env\.example$$'; then \
		echo 'Potential secret-bearing file is tracked.'; \
		exit 1; \
	fi

ci: test lint security
