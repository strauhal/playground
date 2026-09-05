# Pix2Pix Studio

A native macOS front end for classic pix2pix models. It offers drag-and-drop input, automatic center-crop or white-margin preparation, a built-in sketch pad, one-click model and dataset installs, Metal-accelerated inference through PyTorch MPS, 256–2048 px exports, and Finder-friendly output.

Included model buttons cover Edges → Handbags, Edges → Shoes, Labels → Facades, Satellite → Map, Map → Satellite, Day → Night, and the community Edges → Cats model. Dataset buttons cover every dataset published by the original pix2pix project—Facades, Cityscapes, Maps, Edges ↔ Shoes, Edges ↔ Handbags, and Night ↔ Day—plus the community Cats set.

## Open the app

The ready-to-run build is at `dist/Pix2Pix Studio.app`. Double-click it in Finder. You do not need VS Code.

To rebuild after changing the Swift source:

```sh
./Scripts/build-app.sh
```

The project is a Swift package, so it can also be opened directly in Xcode using `Package.swift` if full Xcode is installed.

## Storage

- Models, datasets, and private runtimes: `~/Library/Application Support/Pix2Pix Studio`
- Finished images: `~/Pictures/Pix2Pix Studio`

Both locations are exposed as buttons inside the app. The output location can be changed or created from the Files screen.

## Acceleration and compatibility

Official `.pth` generators use PyTorch's MPS backend on supported Macs, backed by Metal Performance Shaders. CPU fallback is automatic. The Cats community model is a TensorFlow 1 graph; Apple documents that TensorFlow Metal does not support V1 graphs, so that preset intentionally uses CPU compatibility mode.
