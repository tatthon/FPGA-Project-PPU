# Moving Forest Background (VGA / Tiny Tapeout)

A Verilog-based **side-scrolling forest scene** for a 640 × 480 VGA display. The design uses a tile map and an RGB222 tile atlas to draw the background, with a small pixel-art character overlaid as a moving sprite.

## Features

- VGA output: **640 × 480**, nominal **60 Hz** with a **25.175 MHz** pixel clock.
- World background: **1280 × 480 pixels** (80 × 30 tiles).
- Each tile is **16 × 16 pixels**; atlas has **256 tiles**.
- Color format: **RGB222**, 2 bits per channel (6 bits per pixel).
- Horizontal scrolling follows the character before it reaches the screen edge. Two active-high inputs also control the camera manually.
- Camera stops at the left and right world boundaries.
- A 32 × 48 RGB222 character uses an independent tile atlas and walks left or right with controller 1 of the Gamepad PMOD.

## Controls

| Input | Function |
| --- | --- |
| `ui_in[0] = 1`, `ui_in[1] = 0` | Move camera left (scene shifts right) |
| `ui_in[0] = 0`, `ui_in[1] = 1` | Move camera right (scene shifts left) |
| Neither or both camera inputs asserted | No manual camera movement |
| Gamepad D-pad Left or Right | Walk in the pressed direction |
| Neither or both D-pad directions pressed | Stand still |
| `rst_n = 0` | Reset camera and character position |

The [default Gamepad PMOD pinout](https://github.com/psychogenic/gamepad-pmod#default-tt-configuration) uses `ui_in[4]` for latch, `ui_in[5]` for clock, and `ui_in[6]` for data.

The character walks 4 pixels per frame. The camera starts following when the character reaches x=304 while walking right or x=160 while walking left. When the camera reaches the world boundary at offset 0 or 640, the character can walk the remaining distance to the screen edge at x=0 or x=608. The manual camera inputs scroll by 1 pixel per frame while the D-pad is neutral or both directions are held. The leg pose changes every four walking frames. The sprite starts at y=336 so its feet sit directly above the ground at y=384.

## Project structure

```text
.
├── info.yaml
├── README.md
├── src/
│   ├── top_mario.v          # tt_um_vga_example top-level, controls and RGB outputs
│   ├── hsync_generator.v    # VGA counters and synchronization
│   ├── map_rom.v            # 80 × 30 tile-map ROM
│   ├── gamepad_pmod.v       # Serial gamepad interface
│   └── bg_renderer.v        # 256-tile pixel atlas lookup
└── data/
    ├── map2.mem            # 2,400 tile IDs, 8-bit hexadecimal
    ├── mariobg256j.mem     # 65,536 RGB222 pixels, 6-bit hexadecimal
    └── player_tiles.mem   # 512 sprite pixels, 7-bit hexadecimal
```

Use the **latest cloud-corrected** `mariobg256j_cloud_fixed.mem` as `data/mariobg256j.mem` so cloud/tree backgrounds match the sky. Keep `map2.mem` as-is.

## How it works

1. `hvsync_generator` produces screen coordinates `pix_x`, `pix_y`, and VGA sync signals.
2. The top module computes the world X coordinate: `x_scroll = pix_x + scrollOffset`.
3. `map_rom` looks up the tile ID for the world position in `map2.mem`.
4. `bg_renderer` uses the tile ID and local coordinates within the 16 × 16 tile to look up RGB222 from `mariobg256j.mem`.
5. The top module reads the character tile ROM, delays the sprite pixels to match the two-clock background pipeline, and overlays opaque sprite pixels before driving VGA.

The atlas is stored in **tile-major** order. Within each tile, pixels follow row-major order. The renderer computes:

```verilog
pixel_address = {tile[7:4], pixel_y_d1, tile[3:0], pixel_x_d1};
```

Tile ID `00` is an ordinary sky tile, **not transparency**. Blank areas should be filled with the sky tile in `map2.mem`; VGA blanking uses black output.

`player_tiles.mem` contains eight 8 × 8 tiles, with 64 entries per tile in row-major order. Each entry uses bit 6 for opacity and bits 5:0 for RGB222. Tiles 0–1 draw the top row of the character, 2–3 draw the middle row, and 4–5 and 6–7 draw the bottom row for the two poses. The renderer doubles each pixel in both directions, creating 16 × 16 display tiles.

## VGA pinout (Tiny Tapeout)

| Output | Signal | Output | Signal |
| --- | --- | --- | --- |
| `uo_out[0]` | R1 | `uo_out[4]` | R0 |
| `uo_out[1]` | G1 | `uo_out[5]` | G0 |
| `uo_out[2]` | B1 | `uo_out[6]` | B0 |
| `uo_out[3]` | VSync | `uo_out[7]` | HSync |

The top module is `tt_um_vga_example`. `uio_out` and `uio_oe` are tied low; `uio_in` is unused. Use an external compatible VGA output circuit/board — these are digital GPIO signals, not direct VGA analog voltages.

## ROM file paths and simulation

The three ROMs use `$readmemh`:

```verilog
$readmemh("../data/map2.mem", mem);
$readmemh("../data/mariobg256j.mem", mem);
$readmemh("../data/player_tiles.mem", player_tiles);
```

These paths are resolved relative to the **simulator's current working directory**, not automatically relative to the `.v` file. For the layout above, run the simulator from `src/`, or adjust the paths to match your simulation/build tool.

For example, with Icarus Verilog installed:

```bash
cd src
iverilog -g2012 -s tt_um_vga_example -o sim.vvp \
  top_mario.v hsync_generator.v map_rom.v bg_renderer.v gamepad_pmod.v
```

This command only **compiles** the design. To exercise the inputs and inspect VGA timing/image output, run it using an appropriate testbench (not included in this minimal project).

## Tiny Tapeout implementation note

`info.yaml` requests a provisional tile count of `tiles: "1x1"`. The background atlas contains 393,216 bits, the tile map contains 19,200 bits, and the character atlas contains 3,584 bits. Together that is **416,000 ROM bits** before implementation overhead, likely far beyond a 1×1 Tiny Tapeout tile if mapped into standard cells.

**Simulation using `$readmemh` does not prove ASIC synthesizability or area feasibility.** Before a tapeout, check the synthesis flow's treatment of ROM initialization and optimize/reduce the stored image data or choose suitable memory resources.

## Current limitations

- The built-in pixel-art sprite supports horizontal movement only.
- At the right edge, the scene stops; it does not wrap seamlessly.
- Camera and character positions update at frame boundaries.
- RTL was prepared for the described project; **a full simulator and ASIC synthesis verification has not been completed**.

## License

No license is specified in this repository. Add a `LICENSE` file if you plan to distribute the project under an open-source license.
