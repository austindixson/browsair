# Browsair AI Sidebar PRD

**Status:** Proposed implementation
**Date:** 2026-09-01

## Objective

Add an optional, collapsible sidebar chat that helps users understand and interact with the active page without turning Browsair into a bloated AI product. Browsing remains fully usable with the sidebar closed and without an AI key.

## Goals

- Support xAI/SpaceXAI first through its OpenAI-compatible API.
- Support OpenAI-compatible endpoints through configurable base URL and model.
- Leave room for a native Anthropic adapter and official subscription/OAuth integrations.
- Keep credentials in macOS Keychain, never in page JavaScript, source, logs, or Git.
- Provide explicit page context controls: selected text, bounded inspect snapshot, page text, URL, and title.
- Stream responses, allow cancellation, and show provider errors clearly.
- Keep all provider traffic user-initiated and visible.

## Non-goals

- Scraping Claude, Grok, or ChatGPT consumer websites.
- Reading cookies or extracting existing browser sessions.
- Sending page content automatically when the sidebar opens.
- Cloud-syncing conversations or browsing history.
- Letting model output execute arbitrary JavaScript or shell commands.

## Initial scope

1. Sidebar toggle in the browser toolbar.
2. Chat transcript and input with active-tab context controls.
3. Provider settings: xAI default, OpenAI-compatible custom endpoint, model, and Keychain-backed API key.
4. Non-streaming baseline service with a streaming-compatible protocol boundary.
5. Context sanitizer that excludes cookies, passwords, form values, hidden content, and scripts.
6. TDD for request encoding, provider configuration, context limits, and chat state.

## Acceptance criteria

- Sidebar is hidden by default and has no effect on normal browsing.
- No request is sent until the user submits a prompt.
- API keys are retrieved from Keychain only at request time and are not persisted in UserDefaults.
- xAI defaults to `https://api.x.ai/v1` and `grok-4.5`.
- Context is bounded and explicitly selected by the user.
- Requests use HTTPS; localhost is allowed only for deliberate custom development endpoints.
- `swift test` and `swift build` pass.

## Architecture

`AIProviderConfiguration` describes a provider without storing secrets. `CredentialStore` abstracts Keychain access. `AIContextPolicy` sanitizes bounded page context. `ChatMessage` and `AIRequest` are provider-neutral. `AIProviderClient` is the transport boundary; `OpenAICompatibleClient` handles xAI, OpenAI, and compatible endpoints. `AIChatStore` owns sidebar state and cancellation. SwiftUI renders the optional sidebar.

Official subscription access should be added only through documented provider APIs and OAuth flows. The current provider catalog intentionally does not inspect browser cookies, local sessions, or consumer websites. Based on the provider documentation checked for this implementation, xAI and OpenAI expose API-key access for this use case, while Anthropic does not offer public third-party OAuth for Claude subscriptions. Therefore the UI reports subscription OAuth availability honestly and falls back to API keys.

The account registry now supports multiple OAuth accounts when an approved client integration has provisioned tokens into Browsair's Keychain. Discovery is deliberately scoped to accounts registered by an explicit provider sign-in flow or an approved local integration; it does not scan arbitrary app sandboxes or browser cookies. A future OAuth adapter must define client registration, scopes, redirect requirements, refresh behavior, and provider terms before shipping.
