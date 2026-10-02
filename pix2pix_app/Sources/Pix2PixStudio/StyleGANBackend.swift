import Foundation

enum StyleGANBackend {
    static let source = #"""
import argparse, math, sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageOps


def setup(args):
    sys.path.insert(0, args.source)
    import torch
    import torch.nn.functional as F
    import legacy
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print("StyleGAN2 running on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
    with open(args.model, "rb") as handle:
        generator = legacy.load_network_pkl(handle)["G_ema"].eval().requires_grad_(False).to(device)
    label = torch.zeros([1, generator.c_dim], device=device)
    if generator.c_dim:
        label[0, min(max(args.class_index, 0), generator.c_dim - 1)] = 1
    return torch, F, generator, label, device


def mapped(generator, torch, device, label, z, truncation):
    tensor = torch.as_tensor(z, dtype=torch.float32, device=device).reshape(1, generator.z_dim)
    return generator.mapping(tensor, label, truncation_psi=truncation)


def slerp(torch, first, second, amount):
    a = first.reshape(1, -1)
    b = second.reshape(1, -1)
    an = a / a.norm(dim=1, keepdim=True).clamp_min(1e-8)
    bn = b / b.norm(dim=1, keepdim=True).clamp_min(1e-8)
    dot = (an * bn).sum(dim=1, keepdim=True).clamp(-0.9995, 0.9995)
    angle = torch.acos(dot)
    sine = torch.sin(angle)
    if float(sine.abs().max().cpu()) < 1e-5:
        return first.lerp(second, amount)
    result = (torch.sin((1 - amount) * angle) / sine) * a + (torch.sin(amount * angle) / sine) * b
    return result.reshape_as(first)


def blend(torch, first, second, amount, kind):
    if kind == "smooth":
        amount = amount * amount * (3 - 2 * amount)
    if kind == "spherical":
        return slerp(torch, first, second, amount)
    return first.lerp(second, amount)


def resize_output(image, size):
    if image.size == (size, size):
        return image
    method = Image.Resampling.NEAREST if size < image.width else Image.Resampling.LANCZOS
    return image.resize((size, size), method)


def tensor_image(torch, generated, output_size):
    array = ((generated[0].permute(1, 2, 0) + 1) * 127.5).clamp(0, 255).to(torch.uint8).cpu().numpy()
    return resize_output(Image.fromarray(array, "RGB"), output_size)


def random_anchors(args, torch, generator, label, device):
    rng = np.random.RandomState(args.seed)
    center = rng.randn(generator.z_dim).astype(np.float32)
    anchors = []
    for _ in range(args.keyframes):
        direction = rng.randn(generator.z_dim).astype(np.float32)
        direction /= max(float(np.linalg.norm(direction)), 1e-8)
        z = center + direction * args.distance * math.sqrt(generator.z_dim)
        anchors.append(mapped(generator, torch, device, label, z, args.truncation))
    return anchors


def fit_video_frame(image, size, fit):
    image = ImageOps.exif_transpose(image).convert("RGB")
    if fit == "crop":
        return ImageOps.fit(image, (size, size), method=Image.Resampling.LANCZOS)
    if fit == "stretch":
        return image.resize((size, size), Image.Resampling.LANCZOS)
    background = ImageOps.fit(image, (size, size), method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(max(8, size // 18)))
    foreground = ImageOps.contain(image, (size, size), method=Image.Resampling.LANCZOS)
    background.paste(foreground, ((size - foreground.width) // 2, (size - foreground.height) // 2))
    return background


def extract_video_keyframes(args):
    import imageio_ffmpeg
    reader = imageio_ffmpeg.read_frames(args.video, pix_fmt="rgb24")
    metadata = next(reader)
    width, height = metadata["size"]
    fps = float(metadata.get("fps") or 30)
    duration = float(metadata.get("duration") or 0)
    estimated = max(args.video_keyframes, int(round(duration * fps)))
    targets = np.linspace(0, max(estimated - 1, 1), args.video_keyframes).round().astype(int).tolist()
    frames, target_position = [], 0
    for index, raw in enumerate(reader):
        if target_position >= len(targets): break
        if index >= targets[target_position]:
            frames.append(Image.frombytes("RGB", (width, height), raw))
            target_position += 1
    if len(frames) < 2:
        raise RuntimeError("The video needs at least two readable frames.")
    while len(frames) < args.video_keyframes:
        frames.append(frames[-1].copy())
    return frames


def projection_feature_net(torch, device, cache_dir):
    torch.hub.set_dir(cache_dir)
    from torchvision.models import squeezenet1_1, SqueezeNet1_1_Weights
    print("Preparing the lightweight perceptual projector", flush=True)
    network = squeezenet1_1(weights=SqueezeNet1_1_Weights.DEFAULT).features.eval().requires_grad_(False).to(device)
    return network


def project_frame(args, index, count, image, torch, F, generator, label, device, feature_net, w_average, previous):
    target_pil = fit_video_frame(image, 224, args.fit)
    target = torch.from_numpy(np.asarray(target_pil, dtype=np.float32).copy()).permute(2, 0, 1).unsqueeze(0).to(device) / 255
    mean = torch.tensor([0.485, 0.456, 0.406], device=device).reshape(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225], device=device).reshape(1, 3, 1, 1)
    with torch.no_grad():
        target_features = feature_net((target - mean) / std)
    initial = previous.detach().clone() if previous is not None else w_average.detach().clone()
    value = initial.requires_grad_(True)
    optimizer = torch.optim.Adam([value], lr=0.06, betas=(0.9, 0.999))
    for step in range(args.projection_steps):
        position = step / max(args.projection_steps - 1, 1)
        learning_rate = 0.06 * (0.5 - 0.5 * math.cos(math.pi * min(1.0, (1.0 - position) / 0.25)))
        for group in optimizer.param_groups: group["lr"] = learning_rate
        generated = generator.synthesis(value, noise_mode="const")
        small = F.interpolate((generated + 1) / 2, size=(224, 224), mode="bilinear", align_corners=False)
        features = feature_net((small - mean) / std)
        perceptual = F.mse_loss(features, target_features)
        pixels = F.mse_loss(F.interpolate(small, size=(96, 96), mode="bilinear", align_corners=False), F.interpolate(target, size=(96, 96), mode="bilinear", align_corners=False))
        regularity = F.mse_loss(value, w_average)
        loss = perceptual + pixels * 0.15 + regularity * 0.0002
        optimizer.zero_grad(set_to_none=True)
        loss.backward()
        optimizer.step()
        if step == 0 or (step + 1) % max(1, args.projection_steps // 10) == 0:
            print(f"STYLEGAN projecting {index} of {count} · step {step + 1} of {args.projection_steps}", flush=True)
    return value.detach()


def video_anchors(args, torch, F, generator, label, device):
    frames = extract_video_keyframes(args)
    rng = np.random.RandomState(args.seed)
    samples = torch.from_numpy(rng.randn(256, generator.z_dim).astype(np.float32)).to(device)
    labels = label.repeat(samples.shape[0], 1)
    with torch.no_grad():
        w_average = generator.mapping(samples, labels).mean(dim=0, keepdim=True)
    feature_net = projection_feature_net(torch, device, args.cache_dir)
    anchors, previous = [], None
    for index, frame in enumerate(frames, 1):
        previous = project_frame(args, index, len(frames), frame, torch, F, generator, label, device, feature_net, w_average, previous)
        anchors.append(previous)
    center = torch.stack(anchors).mean(dim=0)
    anchors = [center + (item - center) * args.distance for item in anchors]
    if args.truncation != 1:
        anchors = [w_average + (item - w_average) * args.truncation for item in anchors]
    return anchors


def render(args, torch, generator, label, device, anchors):
    import imageio_ffmpeg
    output = Path(args.output_dir)
    frames_dir = output / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.RandomState(args.seed + 9182)
    reference_z = rng.randn(generator.z_dim).astype(np.float32)
    reference = mapped(generator, torch, device, label, reference_z, args.truncation)
    cutoff = min(max(args.style_cutoff, 0), generator.num_ws)
    segments = len(anchors) if args.loop else len(anchors) - 1
    total = segments * args.transition_frames + (0 if args.loop else 1)
    video_path = output / "stylegan2-animation.mp4"
    writer = imageio_ffmpeg.write_frames(str(video_path), (args.output_size, args.output_size), fps=args.fps, codec="libx264", quality=8, pix_fmt_in="rgb24", output_params=["-pix_fmt", "yuv420p"])
    writer.send(None)
    frame_number = 0

    def emit(ws):
        nonlocal frame_number
        if args.style_mix > 0 and cutoff < generator.num_ws:
            ws = ws.clone()
            ws[:, cutoff:] = ws[:, cutoff:].lerp(reference[:, cutoff:], args.style_mix)
        with torch.no_grad():
            generated = generator.synthesis(ws, noise_mode=args.noise)
        image = tensor_image(torch, generated, args.output_size)
        frame_number += 1
        path = frames_dir / f"frame-{frame_number:05d}.png"
        image.save(path, "PNG")
        writer.send(np.asarray(image, dtype=np.uint8).tobytes())
        print(f"STYLEGAN frame {frame_number} of {total}|{path}", flush=True)

    try:
        for segment in range(segments):
            first = anchors[segment]
            second = anchors[(segment + 1) % len(anchors)]
            for step in range(args.transition_frames):
                emit(blend(torch, first, second, step / args.transition_frames, args.interpolation))
        if not args.loop:
            emit(anchors[-1])
    finally:
        writer.close()
    print(f"STYLEGAN video|{video_path}", flush=True)


def main(args):
    torch, F, generator, label, device = setup(args)
    if args.mode == "video":
        anchors = video_anchors(args, torch, F, generator, label, device)
    else:
        anchors = random_anchors(args, torch, generator, label, device)
    render(args, torch, generator, label, device, anchors)


parser = argparse.ArgumentParser()
parser.add_argument("--source", required=True)
parser.add_argument("--model", required=True)
parser.add_argument("--output-dir", required=True)
parser.add_argument("--cache-dir", required=True)
parser.add_argument("--mode", choices=["latent", "video"], default="latent")
parser.add_argument("--video")
parser.add_argument("--fit", choices=["fit", "crop", "stretch"], default="fit")
parser.add_argument("--video-keyframes", type=int, default=4)
parser.add_argument("--projection-steps", type=int, default=100)
parser.add_argument("--keyframes", type=int, default=4)
parser.add_argument("--transition-frames", type=int, default=48)
parser.add_argument("--fps", type=int, default=24)
parser.add_argument("--output-size", type=int, choices=[64, 128, 256, 512, 1024, 2048], default=512)
parser.add_argument("--seed", type=int, default=42)
parser.add_argument("--distance", type=float, default=1.0)
parser.add_argument("--truncation", type=float, default=0.7)
parser.add_argument("--interpolation", choices=["smooth", "linear", "spherical"], default="smooth")
parser.add_argument("--noise", choices=["const", "random", "none"], default="const")
parser.add_argument("--loop", action="store_true")
parser.add_argument("--style-mix", type=float, default=0.0)
parser.add_argument("--style-cutoff", type=int, default=8)
parser.add_argument("--class-index", type=int, default=0)
arguments = parser.parse_args()
if arguments.mode == "video" and not arguments.video:
    parser.error("--video is required in video mode")
main(arguments)
"""#
}
