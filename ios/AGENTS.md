# iOS

- `HybridMapSurface.swift` owns the surface and its provider presenter. Provider SDK code belongs in `AppleMapPresenter.swift` or `GoogleMapPresenter.swift`. Use `MapPresenter.swift` for shared presenter contracts and `MapDragGesture.swift` for shared drag handling.
- Keep UIKit and provider SDK calls on the main thread. Reconcile SDK handles per surface by feature ID. Invalidate scheduled callbacks when changing provider or view lifetime.
- Maintain an Apple-only build and a Google-enabled build. Guard Google imports and references with `#if REACT_NATIVE_MAPS_GOOGLE && canImport(GoogleMaps)`.
- Use the [iOS example](../docs/validation.md#ios) for native validation. Exercise each affected provider on a Mac and record simulator or device coverage separately from compile results.
