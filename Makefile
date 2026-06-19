MINI_NVIM_DIR := .tests/site/pack/deps/start/mini.nvim

.PHONY: test test-deps clean-test-deps

test: test-deps
	nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

test-deps: $(MINI_NVIM_DIR)

$(MINI_NVIM_DIR):
	mkdir -p $(dir $(MINI_NVIM_DIR))
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $(MINI_NVIM_DIR)

clean-test-deps:
	rm -rf .tests
