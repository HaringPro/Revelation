import argparse
import pathlib
from buildsystem.daemon import *
from buildsystem.render_pass import *
from buildsystem.transformer import *

parser = argparse.ArgumentParser()
parser.add_argument("-W", "--watch_dog", action="store_true", help="Run with watchdog")
parser.add_argument("output_dir", type=pathlib.Path, help="Output directory")
args = parser.parse_args()

output_dir = args.output_dir
# output_dir = Path("../RevelationBuild")

if not output_dir.exists():
    output_dir.mkdir(parents=True, exist_ok=True)

world0_deferred = ["Atmosphere", "Lighting"]
world0_composite = ["Combine", "Temporal", "BloomDownsample", "BlurH", "BlurV", "Grade"]
world0 = WorldFolder("world0", world0_deferred, world0_composite)

worlds = [world0]

transform(output_dir, worlds)

if args.watch_dog:
    print("Running with watchdog. Press CTRL+C to stop.")
    daemon = Daemon(output_dir / "shaders", worlds)
