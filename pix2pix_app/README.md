# Pix2Pix Studio

A native macOS front end for classic pix2pix and CycleGAN models. It offers drag-and-drop input, automatic center-crop or white-margin preparation, a built-in sketch pad, one-click model and dataset installs, Metal-accelerated inference through PyTorch MPS, 64–2048 px exports, and Finder-friendly output. CycleGAN renders natively at 64px and 128px; the fixed-size pix2pix and Cats U-Nets render at 256px and use nearest-neighbor reduction for those sizes.

Included model buttons cover Edges → Handbags, Edges → Shoes, Labels → Facades, Satellite → Map, Map → Satellite, Day → Night, and the community Edges → Cats model. Dataset buttons cover every dataset published by the original pix2pix project—Facades, Cityscapes, Maps, Edges ↔ Shoes, Edges ↔ Handbags, and Night ↔ Day—plus the community Cats set.

The app also includes all 18 pretrained CycleGAN generators published by the original project: apple/orange, summer/winter Yosemite, horse/zebra, Monet/photo, four painter styles, satellite/map, Cityscapes photo/labels, facades photo/labels, and iPhone/DSLR flowers. These use the matching nine-block ResNet generator instead of the pix2pix U-Net.

The Studio dropdown keeps these categories separate: selecting a pretrained model changes the inference engine; selecting a training dataset opens its download card. Cityscapes must be obtained from its official website because its license does not permit the pix2pix project to redistribute it.

Animation mode repeatedly creates an edge map from the latest generated result and feeds it back into the selected model for a user-selected number of frames. The separate Next Frame tab implements the Derrick Schultz workflow: it trains a dedicated Pix2PixHD-style generator on consecutive frames from a user-selected video, then feeds each directly predicted image back into that model without edge extraction. Frames are retained in `~/Pictures/Pix2Pix Studio/frames`, and Stop or quitting the app terminates the current helper process.

Next Frame prediction includes an optional Anchor to starting frame control. It mixes 18% of the original seed into the model's input to resist long-run visual drift, but every saved frame is entirely generator-produced—the original pixels are never overlaid on the output.

Each Next Frame training run is retained as a named checkpoint in `~/Library/Application Support/Pix2Pix Studio/Next Frame/Models`. The Choose Model menu includes those checkpoints plus the original single `latest_net_G.pth` model, remembers the selected model, and lets prediction reuse it without retraining.

## Open the app

The ready-to-run build is at `dist/Pix2Pix Studio.app`. Double-click it in Finder. You do not need VS Code.

To rebuild after changing the Swift source:

```sh
./scripts/build-app.sh
```

The project is a Swift package, so it can also be opened directly in Xcode using `Package.swift` if full Xcode is installed.

## Storage

- Models, datasets, and private runtimes: `~/Library/Application Support/Pix2Pix Studio`
- Finished images: `~/Pictures/Pix2Pix Studio`

Both locations are exposed as buttons inside the app. The output location can be changed or created from the Files screen.

## Acceleration and compatibility

Official `.pth` generators use PyTorch's MPS backend on supported Macs, backed by Metal Performance Shaders. CPU fallback is automatic. The Cats community model is a TensorFlow 1 graph; Apple documents that TensorFlow Metal does not support V1 graphs, so that preset intentionally uses CPU compatibility mode.
