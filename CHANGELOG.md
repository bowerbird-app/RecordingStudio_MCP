# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- MCP admin (`:mcp`) lists ops MCP connection paths: `/recording_studio_mcp/apis/operations` and `/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations`, plus a hint to register ChatGPT and Grok Bot in Registered apps with `api_key: "operations"`. No OauthClient seeding. Public MCP and Workspace are unchanged.

## [0.9.0] - 2026-10-07
