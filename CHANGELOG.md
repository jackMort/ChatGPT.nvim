<!-- markdownlint-disable MD024 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org).

## [Unreleased]

## Added

- OpenAI API key can now be securely provided by an external program using the
  `api_key_cmd` configuration option. The value assigned to `api_key_cmd` must
  be a string and is executed as is during startup. The value as stdout by the
  executed command is used as the API key.

## [v0.1.0-alpha](https://github.com/jackMort/ChatGPT.nvim/tree/v0.1.0-alpha) - 2022-12-30

[Full Changelog](https://github.com/jackMort/ChatGPT.nvim/compare/19e3f193c38dcc9be56eff71716b7ac2b582f49b...v0.1.0-alpha)
