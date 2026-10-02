import Foundation

enum StyleGANTrainingBackend {
    static let source = #"""
import argparse, copy, gc, math, pickle, random, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageOps


def fit_frame(image, size, mode):
    image = ImageOps.exif_transpose(image).convert("RGB")
    if mode == "crop":
        return ImageOps.fit(image, (size, size), method=Image.Resampling.LANCZOS)
    if mode == "stretch":
        return image.resize((size, size), Image.Resampling.LANCZOS)
    background = ImageOps.fit(image, (size, size), method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(max(8, size // 18)))
    foreground = ImageOps.contain(image, (size, size), method=Image.Resampling.LANCZOS)
    background.paste(foreground, ((size - foreground.width) // 2, (size - foreground.height) // 2))
    return background


def extract_dataset(args, resolution):
    import imageio_ffmpeg
    dataset = Path(args.dataset_dir)
    dataset.mkdir(parents=True, exist_ok=True)
    existing = sorted(dataset.glob("frame-*.jpg"))
    if existing and not args.reextract:
        print(f"STYLEGAN TRAIN dataset {len(existing)} frames|{dataset}", flush=True)
        return existing
    for old in existing: old.unlink()
    saved = []
    per_video_limit = max(1, math.ceil(args.max_frames / len(args.video)))
    for video_number, video in enumerate(args.video):
        reader = imageio_ffmpeg.read_frames(video, pix_fmt="rgb24")
        try:
            metadata = next(reader)
        except StopIteration:
            continue
        width, height = metadata["size"]
        saved_from_video = 0
        for index, raw in enumerate(reader):
            if index % args.frame_step: continue
            image = Image.frombytes("RGB", (width, height), raw)
            image = fit_frame(image, resolution, args.fit)
            path = dataset / f"frame-{len(saved):06d}.jpg"
            image.save(path, quality=93)
            saved.append(path)
            saved_from_video += 1
            if len(saved) % 25 == 0:
                print(f"STYLEGAN TRAIN extracted {len(saved)} of {args.max_frames}", flush=True)
            if len(saved) >= args.max_frames or saved_from_video >= per_video_limit: break
        if len(saved) >= args.max_frames: break
    if len(saved) < 8:
        raise RuntimeError("Training needs at least eight extracted frames. Add more video or reduce the frame interval.")
    print(f"STYLEGAN TRAIN dataset {len(saved)} frames|{dataset}", flush=True)
    return saved


def augment(torch, images):
    if random.random() < 0.5:
        images = torch.flip(images, dims=[3])
    if random.random() < 0.8:
        brightness = (torch.rand([images.shape[0], 1, 1, 1], device=images.device) - 0.5) * 0.18
        contrast = 0.85 + torch.rand([images.shape[0], 1, 1, 1], device=images.device) * 0.3
        images = ((images + brightness) * contrast).clamp(-1, 1)
    if random.random() < 0.4:
        shift_x, shift_y = random.randint(-8, 8), random.randint(-8, 8)
        images = torch.roll(images, shifts=(shift_y, shift_x), dims=(2, 3))
    return images


def copy_compatible_tensors(source, target):
    source_tensors = dict(source.named_parameters())
    source_tensors.update(dict(source.named_buffers()))
    with __import__("torch").no_grad():
        for name, tensor in list(target.named_parameters()) + list(target.named_buffers()):
            value = source_tensors.get(name)
            if value is not None and value.shape == tensor.shape:
                tensor.copy_(value)


def network_at_resolution(source, resolution):
    if source.img_resolution == resolution:
        return copy.deepcopy(source)
    kwargs = dict(source.init_kwargs)
    kwargs["img_resolution"] = resolution
    resized = type(source)(*source.init_args, **kwargs)
    copy_compatible_tensors(source, resized)
    return resized


def main(args):
    sys.path.insert(0, args.source)
    import torch
    import torch.nn.functional as F
    from torch.utils.data import Dataset, DataLoader
    import legacy

    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print("StyleGAN2 training on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
    with open(args.base_model, "rb") as handle:
        networks = legacy.load_network_pkl(handle)
    native_resolution = networks["G"].img_resolution
    requested_resolution = native_resolution if args.training_resolution == 0 else args.training_resolution
    resolution = min(requested_resolution, native_resolution)
    generator = network_at_resolution(networks["G"], resolution).train().requires_grad_(True).to(device)
    discriminator = network_at_resolution(networks["D"], resolution).train().requires_grad_(True).to(device)
    generator_ema = network_at_resolution(networks["G_ema"], resolution).eval().requires_grad_(False).to(device)
    del networks
    gc.collect()
    if device.type == "mps": torch.mps.empty_cache()
    print(f"STYLEGAN TRAIN resolution {resolution} px (source checkpoint {native_resolution} px)", flush=True)
    paths = extract_dataset(args, resolution)

    class VideoFrames(Dataset):
        def __len__(self): return len(paths)
        def __getitem__(self, index):
            array = np.asarray(Image.open(paths[index]).convert("RGB"), dtype=np.float32).copy()
            return torch.from_numpy(array).permute(2, 0, 1) / 127.5 - 1

    batch = min(args.batch_size, len(paths))
    loader = DataLoader(VideoFrames(), batch_size=batch, shuffle=True, num_workers=0, drop_last=True)
    optimizer_g = torch.optim.Adam(generator.parameters(), lr=args.learning_rate, betas=(0.0, 0.99), eps=1e-8)
    optimizer_d = torch.optim.Adam(discriminator.parameters(), lr=args.learning_rate, betas=(0.0, 0.99), eps=1e-8)
    label_template = torch.zeros([batch, generator.c_dim], device=device)
    if generator.c_dim:
        label_template[:, min(max(args.class_index, 0), generator.c_dim - 1)] = 1
    total_steps = len(loader) * args.epochs
    completed = 0
    fixed_z = torch.randn([1, generator.z_dim], device=device)
    fixed_label = label_template[:1]
    preview_dir = Path(args.dataset_dir) / "Previews"
    preview_dir.mkdir(parents=True, exist_ok=True)

    for epoch in range(args.epochs):
        for real in loader:
            real = real.to(device)
            current_batch = real.shape[0]
            labels = label_template[:current_batch]
            z = torch.randn([current_batch, generator.z_dim], device=device)

            optimizer_d.zero_grad(set_to_none=True)
            with torch.no_grad():
                fake = generator(z, labels, noise_mode="random")
            real_input = augment(torch, real) if args.augment else real
            fake_input = augment(torch, fake) if args.augment else fake
            real_logits = discriminator(real_input, labels)
            fake_logits = discriminator(fake_input, labels)
            loss_d = F.softplus(fake_logits).mean() + F.softplus(-real_logits).mean()
            loss_d.backward()
            torch.nn.utils.clip_grad_norm_(discriminator.parameters(), 10.0)
            optimizer_d.step()

            discriminator.requires_grad_(False)
            optimizer_g.zero_grad(set_to_none=True)
            z = torch.randn([current_batch, generator.z_dim], device=device)
            fake = generator(z, labels, noise_mode="random")
            fake_input = augment(torch, fake) if args.augment else fake
            loss_g = F.softplus(-discriminator(fake_input, labels)).mean()
            loss_g.backward()
            torch.nn.utils.clip_grad_norm_(generator.parameters(), 10.0)
            optimizer_g.step()
            discriminator.requires_grad_(True)

            with torch.no_grad():
                for ema, value in zip(generator_ema.parameters(), generator.parameters()):
                    ema.lerp_(value, 1 - args.ema)
                for ema, value in zip(generator_ema.buffers(), generator.buffers()):
                    ema.copy_(value)
            completed += 1
            if completed == 1 or completed % max(1, total_steps // 100) == 0:
                print(f"STYLEGAN TRAIN step {completed} of {total_steps} · G {float(loss_g.detach().cpu()):.3f} · D {float(loss_d.detach().cpu()):.3f}", flush=True)

        with torch.no_grad():
            sample = generator_ema(fixed_z, fixed_label, truncation_psi=0.7, noise_mode="const")
        array = ((sample[0].permute(1, 2, 0) + 1) * 127.5).clamp(0, 255).to(torch.uint8).cpu().numpy()
        preview = Image.fromarray(array, "RGB")
        if preview.width > 512: preview.thumbnail((512, 512), Image.Resampling.LANCZOS)
        preview_path = preview_dir / f"epoch-{epoch + 1:04d}.png"
        preview.save(preview_path)
        print(f"STYLEGAN TRAIN preview {epoch + 1} of {args.epochs}|{preview_path}", flush=True)

    output = Path(args.output_model)
    output.parent.mkdir(parents=True, exist_ok=True)
    snapshot = {
        "G": copy.deepcopy(generator).eval().requires_grad_(False).cpu(),
        "D": copy.deepcopy(discriminator).eval().requires_grad_(False).cpu(),
        "G_ema": copy.deepcopy(generator_ema).eval().requires_grad_(False).cpu(),
        "training_set_kwargs": None,
        "augment_pipe": None,
    }
    with open(output, "wb") as handle:
        pickle.dump(snapshot, handle)
    print(f"STYLEGAN TRAIN saved|{output}", flush=True)


parser = argparse.ArgumentParser()
parser.add_argument("--source", required=True)
parser.add_argument("--base-model", required=True)
parser.add_argument("--output-model", required=True)
parser.add_argument("--dataset-dir", required=True)
parser.add_argument("--video", action="append", required=True)
parser.add_argument("--max-frames", type=int, default=600)
parser.add_argument("--frame-step", type=int, default=3)
parser.add_argument("--epochs", type=int, default=5)
parser.add_argument("--batch-size", type=int, default=1)
parser.add_argument("--learning-rate", type=float, default=0.002)
parser.add_argument("--training-resolution", type=int, choices=[0, 64, 128, 256, 512], default=256)
parser.add_argument("--ema", type=float, default=0.995)
parser.add_argument("--fit", choices=["fit", "crop", "stretch"], default="fit")
parser.add_argument("--class-index", type=int, default=0)
parser.add_argument("--augment", action="store_true")
parser.add_argument("--reextract", action="store_true")
main(parser.parse_args())
"""#
}
