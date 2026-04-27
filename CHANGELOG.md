# Changelog

All notable changes to this project will be documented in this file. See [standard-version](https://github.com/conventional-changelog/standard-version) for commit guidelines.

### 0.1.1 (2026-04-27)


### Features

* project scaffolding with plugin structure ([b736d1b](https://github.com/garyjohnson/pi-nvim/commit/b736d1b1ff241c226440923c6696eb543abf3a8f))
* **rpc:** implement RPC subprocess communication module ([1bc9447](https://github.com/garyjohnson/pi-nvim/commit/1bc9447392d0c4ca5ca6699ea88fb8d898b81197))
* **session:** implement session lifecycle management ([6613892](https://github.com/garyjohnson/pi-nvim/commit/661389264fc35cbcd080aca2962aabad50fe6c99))
* **socket:** add neovim-pi integration via unix domain socket ([ae40dd8](https://github.com/garyjohnson/pi-nvim/commit/ae40dd8d1a838017ae415b89f6d1447190924a0c))
* **state:** enhance shared state module ([50d760d](https://github.com/garyjohnson/pi-nvim/commit/50d760d481855e92ccbab875a72514004fa8880f))
* **terminal:** auto-enter insert mode and map Esc to exit terminal mode ([ae73db7](https://github.com/garyjohnson/pi-nvim/commit/ae73db72b8d603b752191700f394007d72c1c371))
* **ui/overlay:** implement selection overlay for sending to pi ([b8111d5](https://github.com/garyjohnson/pi-nvim/commit/b8111d5399ac98f0c22dc597f771e7daa7ce066d))
* **ui:** implement layout, chat, input, status, diff modules ([5c6bc23](https://github.com/garyjohnson/pi-nvim/commit/5c6bc2302e9947d2c74ae0cfc9a455f236391716))


### Bug Fixes

* install neovim in github action workflow ([bd35825](https://github.com/garyjohnson/pi-nvim/commit/bd358257bd9d088c3a3f57eba315b3a8a6c95985))
* remove circular require in diff.lua ([75a92b9](https://github.com/garyjohnson/pi-nvim/commit/75a92b95ddad3097ab0b7c4e2e21cb8a881fa910))
* **security:** add input validation for all handler params ([3bac18c](https://github.com/garyjohnson/pi-nvim/commit/3bac18c76f1a9613409418762feab87bb7935225))
* **security:** sanitize openFile paths to prevent VimScript injection ([7f2c1bd](https://github.com/garyjohnson/pi-nvim/commit/7f2c1bd30b3337aeaa2784563a07c5ffc3afae68))
* **terminal:** map Ctrl-w to enable window navigation from terminal mode ([7c88a86](https://github.com/garyjohnson/pi-nvim/commit/7c88a8658f5bc7d4ee13b204b83eabbecf7fa207))
* wrap handlers in vim.schedule to avoid fast event context errors ([095c1dc](https://github.com/garyjohnson/pi-nvim/commit/095c1dc49d45b97e74fd50e21094079c9e38cef9))

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

<!-- dummy changelog entry - standard-version will replace this -->