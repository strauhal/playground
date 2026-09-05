import Foundation

enum PythonBackend {
    static let source = #"""
import argparse, base64, json, os
from pathlib import Path

def run_pix2pix(args):
    import torch
    import torch.nn as nn
    from PIL import Image, ImageOps
    from torchvision.transforms import functional as TF

    class Block(nn.Module):
        def __init__(self, outer, inner, input_nc=None, sub=None, outermost=False, innermost=False, dropout=False):
            super().__init__()
            input_nc = input_nc or outer
            downrelu = nn.LeakyReLU(.2, True)
            uprelu = nn.ReLU(True)
            norm = nn.BatchNorm2d
            if outermost:
                downconv = nn.Conv2d(input_nc, inner, 4, 2, 1, bias=False)
                layers = [downconv, sub, uprelu, nn.ConvTranspose2d(inner * 2, outer, 4, 2, 1), nn.Tanh()]
            elif innermost:
                downconv = nn.Conv2d(input_nc, inner, 4, 2, 1, bias=False)
                layers = [downrelu, downconv, uprelu, nn.ConvTranspose2d(inner, outer, 4, 2, 1, bias=False), norm(outer)]
            else:
                downconv = nn.Conv2d(input_nc, inner, 4, 2, 1, bias=False)
                layers = [downrelu, downconv, norm(inner), sub, uprelu,
                          nn.ConvTranspose2d(inner * 2, outer, 4, 2, 1, bias=False), norm(outer)]
                if dropout: layers.append(nn.Dropout(.5))
            self.model = nn.Sequential(*layers)
            self.outermost = outermost
        def forward(self, x):
            y = self.model(x)
            return y if self.outermost else torch.cat([x, y], 1)

    class Generator(nn.Module):
        def __init__(self):
            super().__init__()
            b = Block(512, 512, innermost=True)
            for _ in range(3): b = Block(512, 512, sub=b, dropout=True)
            b = Block(256, 512, sub=b)
            b = Block(128, 256, sub=b)
            b = Block(64, 128, sub=b)
            self.model = Block(3, 64, input_nc=3, sub=b, outermost=True)
        def forward(self, x): return self.model(x)
    net = Generator()
    state = torch.load(args.model, map_location="cpu", weights_only=True)
    if any(k.startswith("module.") for k in state): state = {k.removeprefix("module."): v for k, v in state.items()}
    net.load_state_dict(state)
    net.eval()

    image = ImageOps.exif_transpose(Image.open(args.input)).convert("RGB").resize((256, 256), Image.Resampling.LANCZOS)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print("Running on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
    net = net.to(device)
    tensor = (TF.to_tensor(image).unsqueeze(0) * 2 - 1).to(device)
    with torch.inference_mode(): result = net(tensor)[0].clamp(-1, 1).cpu()
    TF.to_pil_image((result + 1) / 2).save(args.output, "PNG")

def run_cyclegan(args):
    import torch
    import torch.nn as nn
    from PIL import Image, ImageOps
    from torchvision.transforms import functional as TF

    class ResnetBlock(nn.Module):
        def __init__(self, channels):
            super().__init__()
            self.conv_block = nn.Sequential(
                nn.ReflectionPad2d(1),
                nn.Conv2d(channels, channels, 3, bias=True),
                nn.InstanceNorm2d(channels),
                nn.ReLU(True),
                nn.ReflectionPad2d(1),
                nn.Conv2d(channels, channels, 3, bias=True),
                nn.InstanceNorm2d(channels),
            )
        def forward(self, x): return x + self.conv_block(x)

    class ResnetGenerator(nn.Module):
        def __init__(self):
            super().__init__()
            layers = [
                nn.ReflectionPad2d(3),
                nn.Conv2d(3, 64, 7, bias=True),
                nn.InstanceNorm2d(64),
                nn.ReLU(True),
            ]
            for level in range(2):
                width = 64 * (2 ** level)
                layers += [
                    nn.Conv2d(width, width * 2, 3, stride=2, padding=1, bias=True),
                    nn.InstanceNorm2d(width * 2),
                    nn.ReLU(True),
                ]
            layers += [ResnetBlock(256) for _ in range(9)]
            for level in range(2):
                width = 256 // (2 ** level)
                layers += [
                    nn.ConvTranspose2d(width, width // 2, 3, stride=2, padding=1, output_padding=1, bias=True),
                    nn.InstanceNorm2d(width // 2),
                    nn.ReLU(True),
                ]
            layers += [nn.ReflectionPad2d(3), nn.Conv2d(64, 3, 7, bias=True), nn.Tanh()]
            self.model = nn.Sequential(*layers)
        def forward(self, x): return self.model(x)

    net = ResnetGenerator()
    state = torch.load(args.model, map_location="cpu", weights_only=True)
    if any(k.startswith("module.") for k in state): state = {k.removeprefix("module."): v for k, v in state.items()}
    # Older official checkpoints contain InstanceNorm buffers that modern PyTorch no longer registers.
    state = {k: v for k, v in state.items() if not k.endswith(("running_mean", "running_var", "num_batches_tracked"))}
    net.load_state_dict(state)
    net.eval()

    inference_size = args.output_size if args.output_size in (64, 128) else 256
    image = ImageOps.exif_transpose(Image.open(args.input)).convert("RGB").resize((inference_size, inference_size), Image.Resampling.LANCZOS)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    native_note = " natively" if inference_size in (64, 128) else ""
    print(f"Running CycleGAN{native_note} at {inference_size}px on " + ("Apple GPU via Metal" if device.type == "mps" else "CPU"), flush=True)
    net = net.to(device)
    tensor = (TF.to_tensor(image).unsqueeze(0) * 2 - 1).to(device)
    with torch.inference_mode(): result = net(tensor)[0].clamp(-1, 1).cpu()
    TF.to_pil_image((result + 1) / 2).save(args.output, "PNG")

def run_cats(args):
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import io
    import numpy as np
    import tensorflow.compat.v1 as tf
    from PIL import Image, ImageOps
    tf.disable_v2_behavior()
    model = Path(args.model)
    meta = next(model.rglob("export.meta"))
    prefix = str(meta.with_suffix(""))
    # The exported TF1 U-Net has eight downsampling stages and requires exactly 256×256.
    # Resize only the private inference copy; the user's prepared source remains untouched.
    image = ImageOps.exif_transpose(Image.open(args.input)).convert("RGB").resize((256, 256), Image.Resampling.LANCZOS)
    encoded_image = io.BytesIO()
    image.save(encoded_image, "PNG")
    encoded = base64.urlsafe_b64encode(encoded_image.getvalue()).decode("ascii")
    with tf.Graph().as_default() as graph:
        with tf.Session(graph=graph) as sess:
            saver = tf.train.import_meta_graph(str(meta))
            saver.restore(sess, prefix)
            input_vars = json.loads(tf.get_collection("inputs")[0])
            output_vars = json.loads(tf.get_collection("outputs")[0])
            input_tensor = graph.get_tensor_by_name(input_vars["input"])
            output_tensor = graph.get_tensor_by_name(output_vars["output"])
            value = sess.run(output_tensor, {input_tensor: np.expand_dims(np.array(encoded), 0)})[0]
    if isinstance(value, bytes): value = value.decode("ascii")
    value += "=" * (-len(value) % 4)
    with open(args.output, "wb") as f: f.write(base64.urlsafe_b64decode(value.encode("ascii")))

parser = argparse.ArgumentParser()
parser.add_argument("--architecture", required=True, choices=["pix2pix", "cyclegan", "cats"])
parser.add_argument("--model", required=True)
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--output-size", type=int, choices=[64, 128, 256, 512, 1024, 2048], default=256)
args = parser.parse_args()
if args.architecture == "cats": run_cats(args)
elif args.architecture == "cyclegan": run_cyclegan(args)
else: run_pix2pix(args)
from PIL import Image
image = Image.open(args.output).convert("RGB")
if image.size != (args.output_size, args.output_size):
    resampling = Image.Resampling.NEAREST if args.output_size < 256 else Image.Resampling.LANCZOS
    image.resize((args.output_size, args.output_size), resampling).save(args.output, "PNG")
"""#
}
