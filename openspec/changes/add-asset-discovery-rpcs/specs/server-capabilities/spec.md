# Spec Delta

## Purpose

Lets a client find out which optional features a Historian server implements, by reading named capability strings from `GetInfo` instead of comparing version numbers.

## ADDED Requirements

### Requirement: HistorianInfo carries capabilities
`HistorianInfo` SHALL define `repeated string capabilities = 3`, next to the existing `version = 1` and `apiVersion = 2`. `GetInfo` SHALL return the capabilities the answering server implements.

#### Scenario: Server with asset discovery
- **WHEN** a client calls `GetInfo` on a server that implements `CreateAssets`
- **THEN** the reply's `capabilities` contains `assetDiscovery.v1`

### Requirement: Capability string semantics
A capability string SHALL name one feature and one version of its semantics. Clients SHALL compare capability strings by exact, case-sensitive match. A change to the semantics of a feature SHALL use a new capability string; the meaning of an existing string SHALL NOT change.

#### Scenario: Semantics change in a later release
- **WHEN** a later release changes how `CreateAssets` results must be interpreted
- **THEN** that release adds a new string such as `assetDiscovery.v2` and `assetDiscovery.v1` keeps its meaning

### Requirement: Asset discovery capability
A server SHALL advertise `assetDiscovery.v1` only when it implements `CreateAssets` with the semantics of the `asset-discovery` capability. A server built against v2.2.0 that does not implement the RPC SHALL NOT advertise it.

#### Scenario: Server bumped the proto but did not implement the RPC
- **WHEN** a server depends on historian-proto v2.2.0 but answers `CreateAssets` with `UNIMPLEMENTED`
- **THEN** its `GetInfo` reply does not contain `assetDiscovery.v1`

### Requirement: Clients gate features on capabilities
A client SHALL call an optional feature's RPCs only when the server advertises the matching capability. An empty or absent `capabilities` list SHALL mean the server advertises nothing. Clients SHALL ignore capability strings they do not know.

#### Scenario: Server older than v2.2.0
- **WHEN** a client reads `GetInfo` from a server built against historian-proto v2.1.0, which has no field 3
- **THEN** `capabilities` decodes as empty and the client does not call `CreateAssets`

#### Scenario: Unknown capability
- **WHEN** `capabilities` contains a string the client does not recognize
- **THEN** the client ignores that string and still uses the capabilities it knows

### Requirement: Capabilities are read per connection
A client SHALL take the capability set from the server it is currently connected to and SHALL read it again after it reconnects, because a server can be upgraded or downgraded between connections.

#### Scenario: Server downgraded
- **WHEN** a client reconnects after the server was downgraded to a release without asset discovery
- **THEN** the new `GetInfo` reply lacks `assetDiscovery.v1` and the client stops calling `CreateAssets`
