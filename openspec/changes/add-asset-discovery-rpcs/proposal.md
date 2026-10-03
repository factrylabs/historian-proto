# Proposal

## Why

Collectors can report the measurements they discover (`CreateMeasurements`), but they have no way to report the asset hierarchy they see. Sparkplug B already holds a group, node and device tree that is thrown away, and customers work around the gap over REST, keyed on name. Asset discovery (ADO Feature 36260) needs a wire contract first, because the base collector (B1) and historian-server (S2) are built against it in parallel.

## What Changes

- New unary RPC `CreateAssets(CreateAssetsRequest) returns (CreateAssetsReply)` on `service Historian`. A collector sends its discovered asset tree. The server upserts each item by `sourceRef` and returns one result per item.
- New messages:
  - `DiscoveredAsset`: `sourceRef`, optional `parentSourceRef`, `name`, optional `description`, `metadata`, `properties`.
  - `DiscoveredAssetProperty`: `name`, `measurementName`, optional `description`, optional `dataType`, `metadata`, optional `measurementUUID` hint.
  - `CreateAssetsRequest`, `CreateAssetsReply`.
  - `CreateAssetResult` with nested enum `Status`: `UNSPECIFIED = 0`, `OK`, `PENDING`, `IGNORED`, `REJECTED`.
- New field `HistorianInfo.capabilities` (`repeated string`, field 3). A server that implements `CreateAssets` advertises `"assetDiscovery.v1"`.
- The contract semantics are written into the proto comments: order inside a request does not matter, results are per item, any result acknowledges that item's content, and a gRPC error means a retryable infrastructure failure.
- `CHANGELOG.md` gets a `## v2.2.0` entry and the Makefile version moves to 2.2.0.
- Everything is additive. No existing field, message or RPC changes. Nothing is **BREAKING** on the wire.

### Non-goals

- `MarkAssetsSeen` and the capability `assetDiscovery.seen.v1`. These are phase 2 (historian-proto v2.3.0).
- Any server, base collector or mqtt collector code. Those are separate changes in their own repositories (S1, S2, S3, B1, M0, M1).
- A snapshot or "end of tree" marker, and any delete or withdraw RPC.
- Changes to `CreateMeasurements` or to the existing `Asset` and `AssetProperty` messages.

## Capabilities

### New Capabilities

- `asset-discovery`: the `CreateAssets` RPC, its request, item and result messages, and the semantics a collector and a server rely on (identity by `sourceRef`, order independence, per-item results, acknowledgement and retry rules).
- `server-capabilities`: feature gating through `HistorianInfo.capabilities`, the meaning of a capability string, and how clients treat an absent or unknown value. Phase 2 extends this list.

### Modified Capabilities

None. No specs exist yet in this repository.

## Impact

- `historian/historian.proto`: one new RPC, five new messages (one with a nested enum), one new field on `HistorianInfo`.
- `historian/historian.pb.go` and `historian/historian_grpc.pb.go`: regenerated.
- Go API of the module `github.com/factrylabs/historian-proto/v2`: `HistorianClient` and `HistorianServer` gain `CreateAssets`. Servers that embed `UnimplementedHistorianServer` keep compiling and answer `UNIMPLEMENTED`. Hand-written implementations of `HistorianClient` (test mocks) must add the method when they bump.
- `CHANGELOG.md` and `Makefile` (version 2.1.0 to 2.2.0), release tag `v2.2.0`.
- Downstream consumers that bump to v2.2.0: historian-server (S2, implements the RPC and advertises the capability) and base collector `/v4` v4.4.0 (B1, calls it when the capability is present). Neither has to bump at the same time.
