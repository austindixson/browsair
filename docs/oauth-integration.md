# OAuth integration

The AI settings **Connect OAuth…** button now uses the live xAI OpenID Connect configuration for SuperGrok:

- Authorization: `https://auth.x.ai/oauth2/authorize`
- Token exchange: `https://auth.x.ai/oauth2/token`
- Public client: the Grok CLI client ID
- Flow: Authorization Code + PKCE (`S256`)
- Callback: `browsair://oauth/callback`

After login and consent, the callback state is verified, the authorization code is exchanged, and the access/refresh tokens are stored in the macOS Keychain. The account picker then lists the connected account.

OpenAI and Anthropic remain represented in the provider UI but require provider-specific client registration and OAuth metadata before their buttons can be enabled. Browsair must not guess or scrape those integrations.
