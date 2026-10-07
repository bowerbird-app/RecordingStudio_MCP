# Recording Studio MCP

Mount this engine on a Recording Studio host. It exposes a remote MCP HTTP endpoint. Access is user-delegated OAuth. Domain actions come from Recording Studio API. This gem is a protocol adapter. It is not a second API and not an authorization server.

People Connect an app. The app gets its own Accessible grant. MCP then uses that same grant. The app does not act as the person.
