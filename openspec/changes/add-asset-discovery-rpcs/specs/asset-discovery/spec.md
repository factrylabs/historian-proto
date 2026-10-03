# Spec Delta

## Purpose

Lets a collector report the asset tree and proposed asset properties it discovers to Historian over gRPC, and defines the per-item results and retry rules both sides rely on.

## ADDED Requirements

### Requirement: CreateAssets RPC
The `Historian` service SHALL define a unary RPC `CreateAssets(CreateAssetsRequest) returns (CreateAssetsReply)`. `CreateAssetsRequest` SHALL carry `repeated DiscoveredAsset assets = 1`. The calling collector SHALL be identified by the collector UUID header, as for the other collector RPCs.

#### Scenario: Collector sends a batch of discovered assets
- **WHEN** a collector calls `CreateAssets` with three `DiscoveredAsset` items
- **THEN** the call uses the method path `/proto.Historian/CreateAssets` and the server attributes the items to the collector named in the header

### Requirement: DiscoveredAsset message
`DiscoveredAsset` SHALL define these fields: `string sourceRef = 1`, `optional string parentSourceRef = 2`, `string name = 3`, `optional string description = 4`, `map<string, MetadataProperty> metadata = 5`, `repeated DiscoveredAssetProperty properties = 6`. `metadata` SHALL reuse the existing `MetadataProperty` message.

#### Scenario: Asset with metadata and properties
- **WHEN** a collector builds a `DiscoveredAsset` for a Sparkplug device with one metadata key and two properties
- **THEN** the message encodes with the field numbers listed above and the metadata value is a `MetadataProperty`

### Requirement: Source reference identity
`sourceRef` SHALL identify an item within the scope of the owning collector, and SHALL stay stable for the same source object across requests and restarts. A valid `sourceRef` SHALL be non-empty, at most 1024 bytes and free of NUL characters. The server SHALL treat a later item with the same `sourceRef` as an update of the earlier one.

#### Scenario: Same source sent twice
- **WHEN** a collector sends an item with `sourceRef` `spb:G/N/D`, then sends it again later with a different `name`
- **THEN** the server updates the existing source and does not create a second one

#### Scenario: Invalid source reference
- **WHEN** an item has an empty `sourceRef` or one longer than 1024 bytes
- **THEN** the result for that item has status `REJECTED` and the other items in the request are processed normally

### Requirement: Item is a full snapshot
Each `DiscoveredAsset` SHALL describe the complete current state of that source as the collector sees it, not a patch. A metadata key missing from a later item SHALL mean the source no longer reports that key. An unset `description` SHALL mean the source does not provide one; it SHALL NOT be read as a request to clear the description.

#### Scenario: Metadata key dropped by the source
- **WHEN** a collector first sends metadata keys `a` and `b` for a `sourceRef`, then sends only `a`
- **THEN** the server treats `b` as no longer reported by the source

#### Scenario: Description not provided
- **WHEN** an item leaves `description` unset
- **THEN** the server does not treat this as a change to the description

### Requirement: Parent reference
An unset `parentSourceRef` SHALL mean the item is a top-level asset for that collector. A set `parentSourceRef` SHALL refer to the `sourceRef` of another item from the same collector, sent in the same request or in an earlier one. An item SHALL NOT name itself as its parent.

#### Scenario: Top-level asset
- **WHEN** an item has no `parentSourceRef`
- **THEN** the server places it at the top level for that collector

#### Scenario: Item names itself as parent
- **WHEN** an item has `parentSourceRef` equal to its own `sourceRef`
- **THEN** the result for that item has status `REJECTED`

### Requirement: Order independence
The order of items inside a request SHALL NOT affect the outcome. A child whose parent is not known yet SHALL get status `PENDING`. The server SHALL resolve a `PENDING` item itself once the parent arrives, and the collector SHALL NOT resend an item only because it was `PENDING`.

#### Scenario: Child before parent in one request
- **WHEN** a request lists a device item before the node item it names as parent
- **THEN** both items are placed as if the parent had come first

#### Scenario: Parent arrives in a later request
- **WHEN** a child item gets `PENDING` and its parent is sent in a later request
- **THEN** the server resolves the child without the collector resending it

### Requirement: Requests never remove assets
`CreateAssets` SHALL be additive. A source that is missing from later requests SHALL NOT be removed or deleted because of its absence.

#### Scenario: Source not sent again
- **WHEN** a collector stops including a `sourceRef` in its requests
- **THEN** the source and any asset bound to it are kept

### Requirement: DiscoveredAssetProperty message
`DiscoveredAssetProperty` SHALL define these fields: `string name = 1`, `string measurementName = 2`, `optional string description = 3`, `optional string dataType = 4`, `map<string, MetadataProperty> metadata = 5`, `optional string measurementUUID = 6`. `measurementName` SHALL equal the `CreateMeasurement.name` the collector uses when it discovers that measurement.

#### Scenario: Property proposed for a discovered measurement
- **WHEN** a collector discovers measurement `G/N/D/Temperature` and proposes property `Temperature` on asset `spb:G/N/D`
- **THEN** the property carries `name` `Temperature` and `measurementName` `G/N/D/Temperature`

### Requirement: Property names unique per item
Every property `name` SHALL be non-empty and unique within its `DiscoveredAsset`. An item that breaks this rule SHALL get status `REJECTED`.

#### Scenario: Duplicate property name
- **WHEN** an item carries two properties named `Temperature`
- **THEN** the result for that item has status `REJECTED` with a `message` that states the reason

### Requirement: Property hints
`dataType` and `measurementUUID` SHALL be hints. `dataType` SHALL use the same values as `CreateMeasurement.dataType`. `measurementUUID` SHALL name an existing measurement the collector already knows. The server SHALL NOT reject an item because a hint does not match a measurement.

#### Scenario: Hint points to an unknown measurement
- **WHEN** a property carries a `measurementUUID` that does not exist on the server
- **THEN** the item is still accepted and the server falls back to `measurementName`

### Requirement: Properties are not removed by omission
A property that was sent for a `sourceRef` and is missing from a later item for the same `sourceRef` SHALL NOT be deleted by the server.

#### Scenario: Property dropped from the payload
- **WHEN** a collector sends properties `A` and `B` for an asset, then sends only `A`
- **THEN** property `B` is kept on the server and is not deleted

### Requirement: One result per item
On success, `CreateAssetsReply` SHALL carry `repeated CreateAssetResult results = 1` with exactly one result per request item. Each result SHALL carry the item's `sourceRef`. Clients SHALL match results by `sourceRef`, not by position.

#### Scenario: Reply for a mixed batch
- **WHEN** a request contains a valid item, an item with an invalid name and a child whose parent is unknown
- **THEN** the reply has three results with statuses `OK`, `REJECTED` and `PENDING`, each carrying its item's `sourceRef`

#### Scenario: Result missing for an item
- **WHEN** a reply has no result for one of the request items
- **THEN** the client treats that item as not acknowledged and sends it again later

### Requirement: CreateAssetResult message
`CreateAssetResult` SHALL define `string sourceRef = 1`, `Status status = 2`, `optional string assetUUID = 3` and `optional string message = 4`. The nested enum `Status` SHALL define `UNSPECIFIED = 0`, `OK = 1`, `PENDING = 2`, `IGNORED = 3` and `REJECTED = 4`. A server SHALL always set `status` to a value other than `UNSPECIFIED`.

#### Scenario: Result encoding
- **WHEN** the server returns a result for an accepted item
- **THEN** `status` is `OK` (1) and `assetUUID` holds the UUID of the bound asset

### Requirement: Status meanings
`OK` SHALL mean the item is stored and bound to an asset, with `assetUUID` set. `PENDING` SHALL mean stored and waiting for its parent or root, resolved by the server. `IGNORED` SHALL mean a user ignored this source or an ancestor. `REJECTED` SHALL mean the content is invalid, with the reason in `message`.

#### Scenario: Ignored source sent again
- **WHEN** a user has ignored a source and the collector sends it again with changed content
- **THEN** the result has status `IGNORED` and no asset is created for it

#### Scenario: Rejected item
- **WHEN** the server rejects an item because its source limit is reached
- **THEN** the result has status `REJECTED` and `message` states the reason

### Requirement: Any result acknowledges the content
A client SHALL treat any result for an item as final for the content it sent, including `UNSPECIFIED` and enum values added in later versions. The client SHALL NOT resend that item until its content changes. This applies to `REJECTED` as well.

#### Scenario: Unknown status value
- **WHEN** a client built against v2.2.0 receives a result with status value 5
- **THEN** it treats the item as acknowledged and does not resend it unchanged

#### Scenario: Rejected item not retried
- **WHEN** an item gets `REJECTED` and its content does not change
- **THEN** the client does not send it again

### Requirement: Request-level errors are retryable
A gRPC error status on `CreateAssets` SHALL mean the whole request failed for infrastructure reasons and no item is acknowledged. The client SHALL be allowed to retry the same items. The server SHALL report problems with item content as per-item results, not as a gRPC error, and SHALL make a retry of the same items safe.

#### Scenario: Deadline exceeded
- **WHEN** a `CreateAssets` call fails with `DEADLINE_EXCEEDED`
- **THEN** the client keeps all items of that request unacknowledged and retries them later

#### Scenario: One invalid item in a large batch
- **WHEN** one item in a batch of 500 has invalid content
- **THEN** the call succeeds, that item gets `REJECTED` and the other 499 items get their own results

### Requirement: Unimplemented means unsupported
A client SHALL treat a `CreateAssets` call that fails with `UNIMPLEMENTED` as a server that does not support asset discovery, not as a retryable failure.

#### Scenario: Server without the RPC
- **WHEN** a client calls `CreateAssets` on a server that does not implement it and gets `UNIMPLEMENTED`
- **THEN** the client stops sending asset discovery requests to that server

### Requirement: No duplicate source references in a request
A client SHALL NOT send two items with the same `sourceRef` in one request.

#### Scenario: Collector updates a source twice before a sync
- **WHEN** a collector updates the same source twice before its next request
- **THEN** the request carries only the latest state for that `sourceRef`

### Requirement: CreateAssets is not a liveness signal
Sending an item SHALL NOT be defined as proof that the source is still present. Resending unchanged content SHALL NOT be required for, or counted as, a liveness refresh.

#### Scenario: Unchanged content
- **WHEN** a collector has an acknowledged item whose content has not changed
- **THEN** the collector does not resend it, and the server does not infer that the source has disappeared
