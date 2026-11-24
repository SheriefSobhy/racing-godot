# Credits

Every third-party asset in this project is released under
[CC0 1.0 Universal (public domain)](https://creativecommons.org/publicdomain/zero/1.0/).
Credit isn't required, but it's listed here with thanks. No real car brands are used:
the car names in the Garage (Vortex GT, Kestrel RS, Solaris X, Umbra Z9) are made up.

## Cars: Kenney, Car Kit (CC0)

https://kenney.nl/assets/car-kit (Car Kit 3.1, license in `assets/models/cars/carkit_License.txt`).
kenney.nl is blocked on the network this was built on, so the GLB files were downloaded from
the GitHub mirror https://github.com/Arslan12216775/kenney_car-kit, which carries Kenney's CC0
license file unchanged.

| File (`assets/models/cars/`) | Used for |
| --- | --- |
| `race.glb` | Garage car 1: VORTEX GT |
| `sedan-sports.glb` | Garage car 2: KESTREL RS |
| `hatchback-sports.glb` | Garage car 3: SOLARIS X |
| `race-future.glb` | Garage car 4: UMBRA Z9 |
| `sedan.glb`, `suv.glb`, `suv-luxury.glb`, `taxi.glb`, `van.glb`, `truck.glb`, `delivery.glb` | Traffic |

Each model's wheels are moved onto Godot `VehicleWheel3D` nodes at run time, and the player
cars get a glossier paint material. The `*_colormap.png` files are the texture Godot extracts
from each GLB.

## Textures and sky (CC0)

The same files as the Three.js version ([racing-3d](https://github.com/SheriefSobhy/racing-3d)),
already resized and converted to WebP there.

| File (`assets/`) | Used for | Source |
| --- | --- | --- |
| `sky/sky.webp` | Sky panorama and ambient light | Kloofendal 48d Partly Cloudy (Pure Sky) by Greg Zaal and Jarod Guest, [Poly Haven](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) |
| `textures/road.webp`, `asphalt_n.webp` | Road (lane markings and curbs painted on) | Asphalt 02, [Poly Haven](https://polyhaven.com/a/asphalt_02) |
| `textures/grass.webp`, `grass_n.webp` | Grass | Leafy Grass, [Poly Haven](https://polyhaven.com/a/leafy_grass) |
| `textures/concrete.webp`, `concrete_n.webp` | Road shoulders, roofs | Brushed Concrete, [Poly Haven](https://polyhaven.com/a/brushed_concrete) |
| `textures/facade0-3.webp` | Building walls | Facade 005, 006, 018A, 020A by Lennart Demes, [ambientCG](https://ambientcg.com/list?q=facade) |
| `textures/trees.webp` | Tree billboards and bark | Leaf Set 019 and 024, [ambientCG](https://ambientcg.com/list?q=leafset); Pine Bark, [Poly Haven](https://polyhaven.com/a/pine_bark) |

Guard rails, lamp posts, sign gantries, terrain and buildings are built in code
(`scripts/world.gd`).

## Sounds (CC0)

| File (`assets/sounds/`) | Used for | Source |
| --- | --- | --- |
| `engine_low.wav`, `engine_high.wav` | Engine (two loops crossfaded, pitch follows speed) | domasx2, "Racing car engine sound loops" (`loop_0.wav`, `loop_5.wav`), [OpenGameArt](https://opengameart.org/content/racing-car-engine-sound-loops) |
| `crash.ogg` | Crash | qubodup, "Crash Collision", [OpenGameArt](https://opengameart.org/content/crash-collision) |
| `coin.wav` | Coin pickup (trimmed to 0.6 s, normalised, mono) | Fupi, "Plingy coin", [OpenGameArt](https://opengameart.org/content/plingy-coin) |
| `nitro.mp3` | Nitro boost and nitro pickup | EZduzziteh, "Boost or launch or thruster sound effect", [OpenGameArt](https://opengameart.org/content/boost-or-launch-or-thruster-sound-effect) |
| `whoosh.wav` | Near miss (one whoosh cut from the file, normalised, mono) | pyranostudios, "Air whoosh", [OpenGameArt](https://opengameart.org/content/air-whoosh) |

## Music (CC0)

| File | Source |
| --- | --- |
| `assets/music/pure_raceway.mp3` | MintoDog, "Pure Raceway", [OpenGameArt](https://opengameart.org/content/pure-raceway) (the 96 kbps MP3 from racing-3d) |

## Engine

Made with [Godot Engine](https://godotengine.org) 4.7.2 (MIT license). The UI uses Godot's
built-in default font.
