# ✈️ Sky Fighter: Ricochet Skies

An arcade 3D combat flight simulation game built with **Godot 4.3+** and featuring high-speed jet dogfights, dynamic missile deflection (Ricochet Parry), realistic 3D environments, and responsive aerial physics.

Also includes a standalone single-file playable web edition (`flight.html`).

---

## 🎮 Key Features

- **Iconic Jet Fighters**:
  - **Player**: F-15 Eagle with coordinated banking, afterburners, and twin blasters.
  - **Enemies**: Su-57 Felon stealth fighters with evasive flight logic, missile locks, and counter-measures.
- **Dynamic Ricochet Parry Mechanic**:
  - Lock-on alert warns when an enemy missile is approaching.
  - Triggering parry reflects enemy missiles back at the attacker with bonus streak damage!
- **Detailed 3D Battle Arena**:
  - Multi-tile coastal city and skyscraper canyons.
  - Surrounding pine forest mountain perimeter and vast open ocean.
- **Arcade Combat HUD**:
  - Tactical 360° circular mini-radar displaying player orientation and enemy positions.
  - HUD diamond target brackets showing range and azimuth to bogies.
  - Hull, afterburner boost, and parry cooldown bars.
- **Audio & Visual FX**:
  - Dynamic combat sound effects (cannon shots, missile launches, lock-on alarms, parry sonic booms, and explosions).
  - Wingtip condensation trails and afterburner flame particles.

---

## 🕹️ Controls

| Action | Primary Key | Secondary Key |
| :--- | :--- | :--- |
| **Pitch Down / Up** | `W` / `S` | `Down` / `Up` Arrow |
| **Turn Left / Right (Bank)** | `A` / `D` | `Left` / `Right` Arrow |
| **Afterburner (Boost)** | `Shift` | - |
| **Air Brake / Slow** | `Ctrl` | - |
| **Twin Blasters (Fire)** | `F` | Left Mouse Click |
| **Ricochet Missile Parry** | `Spacebar` | - |
| **Launch Sidewinder Missile**| `E` | Right Mouse Click |
| **Pause / Menu** | `Escape` | - |

---

## 🚀 Getting Started

### Prerequisites

- [Godot Engine 4.x](https://godotengine.org/download) (Standard 64-bit)
- [Git LFS](https://git-lfs.github.com/) (Required for cloning 3D model assets)

### Cloning with Git LFS

Make sure Git LFS is installed before cloning:

```bash
git lfs install
git clone https://github.com/gpreethish08/sky-fighter-ricochet.git
cd sky-fighter-ricochet
```

### Running in Godot

1. Launch Godot Engine.
2. Click **Import** and select the `godot_flight_game/project.godot` file.
3. Open the project and press **F5** (or click the Play icon in the top right) to launch!

### Running the Web Version

Open `flight.html` directly in any modern web browser with WebGL support.

---

## 📁 Repository Structure

```text
├── godot_flight_game/          # Godot 4 project directory
│   ├── asserts/                # 3D models (GLB), textures, and materials
│   ├── audio/                  # Combat and UI sound effects
│   ├── scenes/                 # Main game & player scenes (.tscn)
│   ├── scripts/                # GDScript logic (flight, radar, AI, HUD)
│   ├── export_presets.cfg      # Godot build presets
│   └── project.godot           # Godot project configuration
├── flight.html                 # Standalone browser/WebGL flight game
├── .gitignore                  # Clean Godot & build ignores
└── README.md                   # Project documentation
```

---

## 📜 License

This project is licensed under the MIT License.
