import Foundation

enum NFPBackend {
    static let source = #"""
import argparse, os, tempfile
from pathlib import Path

def torch_parts():
    import torch
    import torch.nn as nn

    class ResnetBlock(nn.Module):
        def __init__(self, channels):
            super().__init__()
            self.block = nn.Sequential(
                nn.ReflectionPad2d(1), nn.Conv2d(channels, channels, 3),
                nn.InstanceNorm2d(channels), nn.ReLU(True),
                nn.ReflectionPad2d(1), nn.Conv2d(channels, channels, 3),
                nn.InstanceNorm2d(channels),
            )
        def forward(self, x): return x + self.block(x)

    class GlobalGenerator(nn.Module):
        """Compact Pix2PixHD global generator: image in, subsequent video frame out."""
        def __init__(self, ngf=48, downs=3, blocks=6):
            super().__init__()
            layers = [nn.ReflectionPad2d(3), nn.Conv2d(3, ngf, 7), nn.InstanceNorm2d(ngf), nn.ReLU(True)]
            for level in range(downs):
                width = ngf * (2 ** level)
                layers += [nn.Conv2d(width, width * 2, 3, 2, 1), nn.InstanceNorm2d(width * 2), nn.ReLU(True)]
            width = ngf * (2 ** downs)
            layers += [ResnetBlock(width) for _ in range(blocks)]
            for level in range(downs):
                width = ngf * (2 ** (downs - level))
                layers += [nn.ConvTranspose2d(width, width // 2, 3, 2, 1, output_padding=1),
                           nn.InstanceNorm2d(width // 2), nn.ReLU(True)]
            layers += [nn.ReflectionPad2d(3), nn.Conv2d(ngf, 3, 7), nn.Tanh()]
            self.model = nn.Sequential(*layers)
        def forward(self, x): return self.model(x)

    class PatchDiscriminator(nn.Module):
        def __init__(self, ndf=48):
            super().__init__()
            channels = [6, ndf, ndf * 2, ndf * 4, ndf * 8, 1]
            blocks = []
            for index in range(len(channels) - 1):
                stride = 2 if index < 3 else 1
                layer = [nn.Conv2d(channels[index], channels[index + 1], 4, stride, 1)]
                if index not in (0, len(channels) - 2): layer.append(nn.InstanceNorm2d(channels[index + 1]))
                if index != len(channels) - 2: layer.append(nn.LeakyReLU(.2, True))
                blocks.append(nn.Sequential(*layer))
            self.blocks = nn.ModuleList(blocks)
        def forward(self, x):
            features = []
            for block in self.blocks:
                x = block(x); features.append(x)
            return features

    return torch, nn, GlobalGenerator, PatchDiscriminator

def device_for(torch):
    if torch.backends.mps.is_available(): return torch.device("mps")
    return torch.device("cpu")

def image_tensor(image, size=256):
    from PIL import Image, ImageOps
    import torch
    from torchvision.transforms import functional as TF
    image = ImageOps.fit(image.convert("RGB"), (size, size), method=Image.Resampling.LANCZOS)
    return TF.to_tensor(image) * 2 - 1

def train(args):
    import imageio_ffmpeg
    from PIL import Image, ImageOps
    from torch.utils.data import Dataset, DataLoader
    from torchvision.transforms import functional as TF
    torch, nn, GlobalGenerator, PatchDiscriminator = torch_parts()

    model_path = Path(args.model)
    model_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pix2pix-studio-nfp-") as temp_name:
        temp = Path(temp_name)
        reader = imageio_ffmpeg.read_frames(args.video, pix_fmt="rgb24")
        metadata = next(reader)
        source_size = metadata["size"]
        frame_paths = []
        print("Extracting consecutive training frames…", flush=True)
        for index, raw in enumerate(reader):
            if index >= args.max_frames: break
            frame = Image.frombytes("RGB", source_size, raw)
            frame = ImageOps.fit(frame, (256, 256), method=Image.Resampling.LANCZOS)
            path = temp / f"{index:06d}.jpg"
            frame.save(path, quality=92)
            frame_paths.append(path)
        if len(frame_paths) < 3:
            raise RuntimeError("The training video needs at least three readable frames.")
        print(f"Training from {len(frame_paths) - 1} consecutive frame pairs", flush=True)

        class FramePairs(Dataset):
            def __len__(self): return len(frame_paths) - 1
            def __getitem__(self, index):
                first = image_tensor(Image.open(frame_paths[index]))
                second = image_tensor(Image.open(frame_paths[index + 1]))
                if torch.rand(()) < .5:
                    first = TF.hflip(first); second = TF.hflip(second)
                return first, second

        device = device_for(torch)
        print("Training NFP on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
        generator = GlobalGenerator().to(device)
        discriminator = PatchDiscriminator().to(device)
        loader = DataLoader(FramePairs(), batch_size=1, shuffle=True, num_workers=0)
        optimizer_g = torch.optim.Adam(generator.parameters(), lr=.0002, betas=(.5, .999))
        optimizer_d = torch.optim.Adam(discriminator.parameters(), lr=.0002, betas=(.5, .999))
        gan_loss = nn.MSELoss()
        l1 = nn.L1Loss()

        for epoch in range(args.epochs):
            for current, future in loader:
                current, future = current.to(device), future.to(device)
                generated = generator(current)

                optimizer_d.zero_grad(set_to_none=True)
                real_features = discriminator(torch.cat((current, future), 1))
                fake_features = discriminator(torch.cat((current, generated.detach()), 1))
                loss_d = (gan_loss(real_features[-1], torch.ones_like(real_features[-1])) +
                          gan_loss(fake_features[-1], torch.zeros_like(fake_features[-1]))) * .5
                loss_d.backward(); optimizer_d.step()

                optimizer_g.zero_grad(set_to_none=True)
                fake_features = discriminator(torch.cat((current, generated), 1))
                with torch.no_grad(): real_features = discriminator(torch.cat((current, future), 1))
                feature_loss = sum(l1(a, b) for a, b in zip(fake_features[:-1], real_features[:-1]))
                loss_g = gan_loss(fake_features[-1], torch.ones_like(fake_features[-1])) + feature_loss * 5 + l1(generated, future) * 10
                loss_g.backward(); optimizer_g.step()
            print(f"NFP epoch {epoch + 1} of {args.epochs}", flush=True)
            torch.save({"generator": generator.state_dict(), "size": 256, "ngf": 48, "downs": 3, "blocks": 6}, model_path)
    print("NFP model ready", flush=True)

def predict(args):
    from PIL import Image, ImageOps
    from torchvision.transforms import functional as TF
    torch, nn, GlobalGenerator, PatchDiscriminator = torch_parts()
    checkpoint = torch.load(args.model, map_location="cpu", weights_only=True)
    generator = GlobalGenerator(checkpoint.get("ngf", 48), checkpoint.get("downs", 3), checkpoint.get("blocks", 6))
    generator.load_state_dict(checkpoint["generator"])
    generator.eval()
    device = device_for(torch)
    generator = generator.to(device)
    current = image_tensor(ImageOps.exif_transpose(Image.open(args.input))).unsqueeze(0).to(device)
    seed = current.clone()
    output_dir = Path(args.output_dir); output_dir.mkdir(parents=True, exist_ok=True)
    print("Predicting directly on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
    prefix = args.prefix
    with torch.inference_mode():
        for frame_number in range(1, args.frames + 1):
            # Guide the model input toward the seed, but never composite seed pixels
            # into the output. Every saved frame is entirely generator-produced.
            model_input = (current * .82 + seed * .18).clamp(-1, 1) if args.anchor_to_seed else current
            current = generator(model_input).clamp(-1, 1)
            image = TF.to_pil_image(((current[0].cpu() + 1) / 2))
            if args.output_size != 256:
                resample = Image.Resampling.NEAREST if args.output_size < 256 else Image.Resampling.LANCZOS
                image = image.resize((args.output_size, args.output_size), resample)
            output = output_dir / f"{prefix}-frame-{frame_number:04d}.png"
            image.save(output, "PNG")
            print(f"NFP frame {frame_number} of {args.frames}|{output}", flush=True)

parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="command", required=True)
train_parser = sub.add_parser("train")
train_parser.add_argument("--video", required=True)
train_parser.add_argument("--model", required=True)
train_parser.add_argument("--epochs", type=int, default=10)
train_parser.add_argument("--max-frames", type=int, default=600)
predict_parser = sub.add_parser("predict")
predict_parser.add_argument("--model", required=True)
predict_parser.add_argument("--input", required=True)
predict_parser.add_argument("--output-dir", required=True)
predict_parser.add_argument("--prefix", required=True)
predict_parser.add_argument("--frames", type=int, required=True)
predict_parser.add_argument("--output-size", type=int, choices=[64, 128, 256, 512, 1024, 2048], default=256)
predict_parser.add_argument("--anchor-to-seed", action="store_true")
arguments = parser.parse_args()
train(arguments) if arguments.command == "train" else predict(arguments)
"""#
}
