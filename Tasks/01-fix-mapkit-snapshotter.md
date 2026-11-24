# 01 Fix the MapKit snapshotter type

[Back to TASKS.md](../TASKS.md)

Status: Completed (iOS builds not run: no Mac)

## Objective

`ios/AppleMapPresenter.swift` names a type `MKMapFeaturester` that does not exist. The MapKit type is `MKMapSnapshotter`. Neither iOS build compiles until this is fixed. Later tasks need a compiling iOS build.

## Non-goals

- Changing snapshot behavior, drawing, or error handling.

## Read before editing

- `ios/AppleMapPresenter.swift`: `snapshotters` (line 26) and `snapshot(_:)` (lines 257 to 299).

## Current behavior to preserve

`snapshot(_:)` copies the camera, size, and traits into the snapshotter options, then draws routes and marker icons over the result. It keeps each snapshotter in `snapshotters` until completion, and `close()` cancels them.

## Steps

1. Replace the three `MKMapFeaturester` occurrences with `MKMapSnapshotter`: the dictionary type, `MKMapSnapshotter.Options()`, and the initializer.
2. Search the repository for `Featurester` and similar broken renames (`rg -n "Featurest|Features[a-z]" ios android/src native src`). Fix any other hit the same way.

## Tests

No unit test exists for presenters. The compile and the existing snapshot check in the example are the test.

## Validation

- On a Mac: build the example for the simulator in both configurations (MapKit only, and with `GOOGLE_MAPS_IOS_API_KEY`). Both must compile.
- In the MapKit example, take a snapshot. It must return a `file:` URI showing routes and markers.
- Without a Mac, report both builds as not run.

## Completion criteria

- No `MKMapFeaturester` remains.
- Both iOS configurations compile, or the report says they were not run.

## Commit

`fix(ios): use MKMapSnapshotter for MapKit snapshots`
