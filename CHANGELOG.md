# Changelog

## v2.0.0

### Breaking changes

- `metadata` fields on `CreateMeasurement`, `Asset`, `AssetProperty`, and `TimeseriesDatabase` changed from `google.protobuf.Struct` to `map<string, MetadataProperty>`. `MetadataProperty` carries a `DataType` enum (`STRING`, `NUMBER`, `BOOLEAN`) and a `google.protobuf.Value`, matching the receiver-side schema. Field numbers are preserved, but the wire format is incompatible with v1.x.

## v1.8.0

- Added `metadata` field to `CreateMeasurement`.

## v1.7.0

- Added `Pagination` message, integrated into `GetMeasurementsByFilterRequest`.
- Added new RPC methods.
