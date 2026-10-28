NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

.PHONY: test format lint check
test:
	$(NVIM) -n --headless -u NONE -i NONE -l tests/run.lua
	$(NVIM) -n --headless -u NONE -i NONE -l tests/diagram_mouse.lua
	$(NVIM) -n --headless -u NONE -i NONE -l tests/diagram_reopen.lua

format:
	$(STYLUA) lua tests

lint:
	$(STYLUA) --check lua tests
	$(LUACHECK) lua tests

check: test lint
