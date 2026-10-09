# Blender 5.2.2 on M1 GitHub Actions (macOS 26)

Open **Actions → Blender 5.2.2 M1 render validation** or push modifications to `blender/`.
The workflow installs the official Blender 5.2.2 Apple Silicon DMG into a temporary runner directory.

A small generated scene is saved as `m1_probe.blend` and rendered at 640×360 with:
- Cycles CPU (must succeed, confirms usable Blender and headless background render)
- Cycles Metal GPU (best-effort: exact backend and devices recorded; Metal on a VM may be unsupported)
- EEVEE (best-effort: checks graphics context support on the macOS hosted VM)

The job summary summarizes output images. The `blender-5-2-2-m1-render` Actions artifact contains PNGs, logs and machine-readable JSON with Blender version, render timings and device details.

A green Actions job does **not** imply GPU success: check the dedicated per-engine JSON and screenshots. CPU failure makes the job fail; unsupported Metal and EEVEE are reported rather than masking CPU capability.

This test intentionally uses only the standard `macos-26` M1 GitHub-hosted runner.
