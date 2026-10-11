NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

.PHONY: test format lint check
test:
	$(NVIM) -n --headless -u NONE -i NONE -l tests/run.lua

format:
	$(STYLUA) lua tests

lint:
	$(STYLUA) --check lua tests
	$(LUACHECK) lua tests

check: test lint
