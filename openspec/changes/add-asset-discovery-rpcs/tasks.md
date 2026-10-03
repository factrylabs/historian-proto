# Tasks

## 1. Toolchain and branch

- [ ] 1.1 Create the implementation branch from an up-to-date `main` as `feat/<P1 PBI id>-asset-discovery-rpcs` (PBI under Feature 36260) and verify `git log -1 main..HEAD` is empty
- [ ] 1.2 Install protoc v6.32.0, protoc-gen-go v1.36.11 and protoc-gen-go-grpc v1.5.1 (the versions in the headers of `historian/historian.pb.go` and `historian/historian_grpc.pb.go`) and verify each `--version` output matches
- [ ] 1.3 Run `make gen_proto` on the unchanged proto and verify `git diff --exit-code historian/` is clean, which proves the toolchain reproduces the v2.1.0 files byte for byte

## 2. Proto contract (commit `feat: add asset discovery rpcs`)

- [ ] 2.1 Add `repeated string capabilities = 3;` to `HistorianInfo` with the comment from design.md (exact match, ignore unknown values) and verify `protoc` compiles the file
- [ ] 2.2 Add `DiscoveredAssetProperty`, `DiscoveredAsset`, `CreateAssetsRequest`, `CreateAssetResult` (nested `Status` enum, `UNSPECIFIED = 0`, `OK = 1`, `PENDING = 2`, `IGNORED = 3`, `REJECTED = 4`) and `CreateAssetsReply` after `CreateMeasurementsRequest`, with the field numbers and comments from design.md, and verify each field number matches the spec requirements in `specs/asset-discovery/spec.md`
- [ ] 2.3 Write the request-level semantics into the comments of `CreateAssetsRequest` and `CreateAssetsReply` (order independence, full snapshot per item, never removed by omission, no duplicate `sourceRef`, not a liveness signal, one result per item matched by `sourceRef`, any result is an ack, gRPC error is retryable, `UNIMPLEMENTED` means unsupported) and verify every semantics requirement in the spec has a matching comment line
- [ ] 2.4 Add `rpc CreateAssets (CreateAssetsRequest) returns (CreateAssetsReply);` with its comment after `CreateMeasurements` in the core collector block and verify there is no `MarkAssetsSeen` anywhere in the file
- [ ] 2.5 Run `make gen_proto` and verify the generated headers still show the same tool versions, `historian_grpc.pb.go` has `Historian_CreateAssets_FullMethodName = "/proto.Historian/CreateAssets"` and an `UnimplementedHistorianServer.CreateAssets` stub, and `historian.pb.go` has `HistorianInfo.Capabilities` and the `CreateAssetResult_*` constants
- [ ] 2.6 Verify the change is additive: `git diff --numstat historian/historian.proto` shows 0 deleted lines, and no existing field number, name or type changed
- [ ] 2.7 Run `go build ./...`, `go vet ./...` and golangci-lint v1.59.1 (the CI version) and verify all pass
- [ ] 2.8 Commit `historian/historian.proto`, `historian/historian.pb.go` and `historian/historian_grpc.pb.go` as `feat: add asset discovery rpcs` and verify the message passes `commitlint.config.mjs` (type `feat`, lowercase, no forbidden words)

## 3. Release v2.2.0 (commit `release: bump to v2.2.0`)

- [ ] 3.1 Run `make version_minor_bump` and verify `make version` prints `v2.2.0` and the Makefile reads `minor = 2`, `patch = 0`
- [ ] 3.2 Add a `## v2.2.0` section above `## v2.1.0` in `CHANGELOG.md`, in the existing "Added ..." style, covering: the `CreateAssets` RPC; the `DiscoveredAsset`, `DiscoveredAssetProperty`, `CreateAssetsRequest`, `CreateAssetsReply` and `CreateAssetResult` messages; the `capabilities` field on `HistorianInfo` with the value `assetDiscovery.v1`. Verify it has no em dashes and no breaking-changes section
- [ ] 3.3 Commit only `Makefile` and `CHANGELOG.md` as `release: bump to v2.2.0` and verify `git show --stat HEAD` lists exactly those two files, matching the v2.1.0 release commit `497b3b2`

## 4. Pull request and tag

- [ ] 4.1 Fetch `origin`, confirm `main` has not moved past the branch base (rebase if it has), push, and open a GitHub PR to `main` titled `feat: add asset discovery rpcs`, assigned to diericd, with a summary, the ADO work item link and ID, and testing steps (tasks 1.3, 2.5 to 2.7). Verify the CI jobs `commit-lint` and `static-checks` pass
- [ ] 4.2 After merge, tag `v2.2.0` (lightweight, like `v2.1.0`) on the release commit as it landed on `main`, push the tag, and verify `go list -m github.com/factrylabs/historian-proto/v2@v2.2.0` resolves from a scratch module
