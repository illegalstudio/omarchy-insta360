.PHONY: check release test validate

PYTHON ?= python3

check: validate test

validate:
	@$(PYTHON) -m json.tool manifest.json >/dev/null
	@omarchy plugin validate .

test:
	@$(PYTHON) -m unittest discover -s tests -v

release:
	@scripts/release.sh
