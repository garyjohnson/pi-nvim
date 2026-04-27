.PHONY: test clean-deps

TEST_CMD := nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

test:
	$(TEST_CMD)

clean-deps:
	rm -rf $$(nvim --headless -c 'echo stdpath("data")/site/pack/deps/start/plenary.nvim' -c 'quit' 2>&1)
