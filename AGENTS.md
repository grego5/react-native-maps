# React Native Maps

Start with the [docs index](docs/README.md). Read the [architecture](docs/architecture.md) before changing a boundary between React and a native presenter. Use the [validation guide](docs/validation.md) to choose checks for the paths you change.

## Repository map

| Directory | Responsibility |
| --- | --- |
| `src/` | Public React/TypeScript API and Nitrogen specs |
| [`android/`](android/AGENTS.md) | Android Google Maps surface, runtime, and JNI |
| [`ios/`](ios/AGENTS.md) | MapKit and optional Google Maps presenters, runtime, and native attachment |
| `nitrogen/generated/` | Generated bindings and autolinking |
| `example/` | Expo development app for integration and device checks |
| [`lab/`](lab/AGENTS.md) | Validation sources, harnesses, and local outputs |

## Working rules

- Use React Native Maps as the project name. The package manifest declares `@grego5/react-native-maps`. Nitro Modules is the binding layer and Nitrogen generates it.
- Keep persistent marker and route data in application state. Pass ordered feature arrays to the mounted surface. Reconcile SDK handles by feature ID and release them with the surface.
- Edit `src/*.nitro.ts` and `nitro.json` as needed for binding changes, then run `npm run nitrogen`. Keep generated files in sync with the specs. Check both native platforms when changing a shared spec.
- Update the relevant docs when changing public behavior or architecture. Keep validation harnesses and local outputs in `lab/`. Preserve the [license](LICENSE) and applicable notices.
- Refresh the installed local package in `example/` before testing changed code. Report build checks separately from on-device or simulator checks.
- Commit or push only when requested.
