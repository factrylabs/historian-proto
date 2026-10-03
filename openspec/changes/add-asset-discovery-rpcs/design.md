# Design

## Context

See proposal.md for motivation. The requirements live in `specs/asset-discovery/spec.md` and `specs/server-capabilities/spec.md`.

Current state of the repository (v2.1.0):

- One file, `historian/historian.proto`, `syntax = "proto3"`, `package proto`. Field names are lowerCamelCase (`measurementUUID`, `collectorUUID`). Nested enums use unprefixed values (`MetadataProperty.DataType.STRING`, `Log.Level.PANIC`). proto3 `optional` is already in use (`EngineeringSpecs`, `CreateMeasurement`).
- `HistorianInfo` has `version = 1` and `apiVersion = 2`. historian-server fills them with its build version and the REST OpenAPI version (`historian-server/internal/api/controllers/grpc/collectors.go:260-267`).
- `MetadataProperty` (field 1 `dataType`, field 2 `value`) is the metadata value type since v2.0.0 and is reused here.
- Generated code: `historian.pb.go` from protoc-gen-go v1.36.11 and `historian_grpc.pb.go` from protoc-gen-go-grpc v1.5.1, both with protoc v6.32.0 (file headers). `make gen_proto` runs protoc. None of these tools are installed on this machine today.
- Release history: a `feat:` commit with the proto change and regenerated code, then a `release: bump to vX.Y.Z` commit that touches only `Makefile` and `CHANGELOG.md` (see `21aeafa`, `497b3b2`). Tags are lightweight and point at the release commit. CI (GitHub Actions, PRs to `main`) runs commitlint, `go vet`, `go build` and golangci-lint.
- Consumers: historian-server is on v2.1.0, base collector on v2.0.0. Base gates health updates today by comparing the server version with `7.3.0` (`base/transport/grpc/client.go:412-433`).

## Goals / Non-Goals

**Goals:**

- A wire contract that B1 and S2 can build against in parallel, with semantics clear enough that neither side has to read the other's code.
- Purely additive on the wire and safe for every old/new client and server pairing.
- Room for phase 2 (`MarkAssetsSeen`, `assetDiscovery.seen.v1`) without touching anything added here.

**Non-Goals:**

- Server-side policy such as the source cap value, the property count limit or the name validation rules. The contract only says that such failures come back as `REJECTED` with a `message`.
- Any change to the existing `Asset`, `AssetProperty` or `CreateMeasurement` messages.

## Decisions

### Proto shape

The messages follow design doc section 1 and the plan's P1 section. Comments carry the semantics, because the `.proto` file is the only document most consumers read.

```proto
// in service Historian, core collector functions, after CreateMeasurements:
  // CreateAssets reports the asset tree a collector discovered. Only call it when
  // GetInfo advertises "assetDiscovery.v1". See CreateAssetsRequest for semantics.
  rpc CreateAssets (CreateAssetsRequest) returns (CreateAssetsReply);

message HistorianInfo {
  string version = 1;
  string apiVersion = 2;
  // Optional features this server implements, e.g. "assetDiscovery.v1".
  // Exact, case-sensitive match. Unknown values must be ignored.
  repeated string capabilities = 3;
}

message DiscoveredAssetProperty {
  string name = 1;                     // unique and non-empty within the asset
  string measurementName = 2;          // exactly the CreateMeasurement.name used for discovery
  optional string description = 3;    // unset: not provided by the source
  optional string dataType = 4;        // hint only, same values as CreateMeasurement.dataType
  map<string, MetadataProperty> metadata = 5;
  optional string measurementUUID = 6; // hint: an existing measurement the collector already knows
}

message DiscoveredAsset {
  string sourceRef = 1;                // stable, collector-scoped, non-empty, <= 1024 bytes, no NUL
  optional string parentSourceRef = 2; // unset: top level for this collector
  string name = 3;
  optional string description = 4;     // unset: not provided by the source, never read as a change
  map<string, MetadataProperty> metadata = 5;      // full current state, not a patch
  repeated DiscoveredAssetProperty properties = 6; // additive: absent properties are not removed
}

// Semantics:
// - Each item is the full current state of one source, identified by sourceRef.
// - Order inside a request does not matter. A child that arrives before its
//   parent gets PENDING and the server resolves it later. Do not resend it.
// - Items are never deleted because they are missing from later requests.
// - Do not send the same sourceRef twice in one request.
// - CreateAssets is not a liveness signal. Do not resend unchanged content.
message CreateAssetsRequest {
  repeated DiscoveredAsset assets = 1;
}

message CreateAssetResult {
  enum Status {
    UNSPECIFIED = 0; // never set on purpose by a server; still counts as an ack
    OK = 1;          // stored and bound to an asset; assetUUID is set
    PENDING = 2;     // stored, waiting for its parent or root; the server resolves it
    IGNORED = 3;     // a user ignored this source or an ancestor
    REJECTED = 4;    // content invalid; reason in message; do not resend unchanged
  }
  string sourceRef = 1;
  Status status = 2;
  optional string assetUUID = 3;
  optional string message = 4;
}

// One result per request item, matched by sourceRef, in no particular order.
// Any result, including UNSPECIFIED and values added later, acknowledges the
// content that was sent. An item without a result is not acknowledged.
// A gRPC error means the whole request failed for infrastructure reasons and
// can be retried. UNIMPLEMENTED means the server does not support the RPC.
message CreateAssetsReply {
  repeated CreateAssetResult results = 1;
}
```

Placement: the RPC goes in the "core collector functions" block, after `CreateMeasurements`, because collectors call it. The messages go after `CreateMeasurementsRequest`. Placement has no wire effect; the method path is `/proto.Historian/CreateAssets` either way.

### Field numbers

- `HistorianInfo.capabilities = 3`: the next free number. The file has no `reserved` ranges, so nothing else constrains it.
- New messages number their fields from 1 in declaration order. These are new messages, so no number can collide with an older use.
- Nothing is reserved for phase 2. `MarkAssetsSeen` adds its own request and reply messages. If a later version needs a new field on `DiscoveredAsset`, it takes 7.
- Alternative considered: putting `capabilities` in a new message or a new RPC. Rejected: base already calls `GetInfo` at connect time, and an unknown field 3 is skipped by old decoders.

### Capabilities instead of semver

- Feature support depends on what the server implements, not on which proto version it compiled against. A server can bump to v2.2.0 and still answer `UNIMPLEMENTED` through `UnimplementedHistorianServer`. A proto version check would say yes; the capability says no.
- Comparing the Historian build version means every client carries a table of "feature X needs Historian >= Y". That breaks for patch branches and backports, and it is the pattern base already uses for health updates (`SemverCompare(historianVersion, "7.3.0")`). We do not want a second instance of it.
- `apiVersion` is the REST OpenAPI version. It says nothing about gRPC features.
- A capability can be versioned (`assetDiscovery.v1`, later `assetDiscovery.v2`) and features can ship separately (`assetDiscovery.seen.v1` in phase 2), without a client having to know which Historian release brought which.
- Alternative considered: probing `CreateAssets` with an empty request and treating `UNIMPLEMENTED` as unsupported. Rejected as the primary mechanism: it costs a call, and a server that has the RPC but turns the feature off has no way to say so. `UNIMPLEMENTED` is still handled as a fallback (spec requirement "Unimplemented means unsupported").

### `UNSPECIFIED = 0`

- In proto3 the zero value is what a reader sees when the field is unset. If `OK` were 0, a server bug that forgets to set `status` would read as success.
- Go uses open enums: an unknown number decodes as that number, not as 0. So 0 only ever means "not set". Clients still treat it as an acknowledgement, so a buggy server cannot cause a resend loop.
- Value names are unprefixed (`OK`, not `STATUS_OK`) to match the existing `MetadataProperty.DataType` and `Log.Level`. Values of a nested enum are scoped to the enclosing message, so `OK` cannot clash with another enum in `package proto`. Go names become `CreateAssetResult_OK` and so on.

### Any result is an acknowledgement

- A client resends an item only when its content changes. Without this rule, a client that does not understand a new status (or `REJECTED` for a reason it cannot fix) would retry the same bytes forever.
- The server always returns per-item results for content problems. A gRPC error is reserved for failures where nothing was stored (connection loss, deadlock, timeout), so retrying is always safe because items are upserts by `sourceRef`.

### Compatibility

| Client | Server | Result |
|---|---|---|
| proto <= v2.1.0 | v2.2.0 implementing the RPC | Client ignores field 3 in `HistorianInfo` and never calls `CreateAssets`. Unchanged behavior. |
| v2.2.0 | proto <= v2.1.0 | Field 3 is absent, `capabilities` decodes empty, client sends nothing. A call anyway gets `UNIMPLEMENTED`. |
| v2.2.0 | v2.2.0 without the RPC | Server does not advertise `assetDiscovery.v1`. A call gets `UNIMPLEMENTED` from the embedded stub. |
| v2.2.0 | v2.2.0 with the RPC | Feature on. |
| v2.2.0 | v2.3.0 (phase 2) | Client never calls `MarkAssetsSeen`. Server must handle sources that are never marked seen. |
| v2.3.0 | v2.2.0 | `assetDiscovery.seen.v1` is absent, so the client does not call `MarkAssetsSeen`. `CreateAssets` works as in v1. |

Go source compatibility: `HistorianClient` and `HistorianServer` gain `CreateAssets`. Servers that embed `UnimplementedHistorianServer` (required by the generated code) keep compiling. Hand-written implementations of `HistorianClient`, such as test mocks, must add the method when they bump. This is the usual cost of a new RPC in grpc-go and is why the release is a minor bump. Base jumps from v2.0.0 to v2.2.0, which also pulls in the additive v2.1.0 fields.

## Risks / Trade-offs

- [Invalid UTF-8 in any string field makes Go's proto3 marshal fail for the whole request, which a client could read as a retryable error and retry forever] → Clients validate UTF-8 and NUL locally before building a request and keep failing entries out (B1 does this). The proto comment on `sourceRef` states the constraints.
- [A large request can hit the server's deadline or message size limit, which also shows up as a request-level error] → Clients chunk by count and size and shrink chunks on `DEADLINE_EXCEEDED` or `RESOURCE_EXHAUSTED` (B1). The contract does not fix a chunk size.
- [Semantics live in comments, which the compiler does not check] → The specs in this change are the reference, and S2 and B1 carry tests for each scenario.
- [Unprefixed enum values differ from the common `STATUS_` prefix convention] → Consistent with this file; the repository has no buf lint.
- [The toolchain versions are not installed locally, and a different protoc-gen-go version rewrites the whole generated file] → Regenerate with the exact versions from the file headers so the diff only shows the new code.

## Migration Plan

1. Merge the `feat:` commit and the `release:` commit to `main`, tag `v2.2.0` on the release commit.
2. historian-server (S2) bumps to v2.2.0, implements `CreateAssets` and adds `assetDiscovery.v1` to `GetInfo`.
3. Base (B1) bumps to v2.2.0 and gates on the capability. B1 can be built against the `grpctest` mock before S2 ships.

Rollback: nothing on the wire depends on v2.2.0 until a server advertises the capability. A consumer can stay on or return to v2.1.0. A tagged release is not retracted; a fix goes out as v2.2.1.

## Open Questions

- What the server does when a client breaks the "no duplicate `sourceRef` in one request" rule: process each item in order (last one wins) or reject the duplicates. This is S2's choice. Either way the reply still has one result per item, as the spec requires.
