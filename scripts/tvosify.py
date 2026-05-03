#!/usr/bin/env python3
"""
Patches GN-generated Ninja build files to target tvOS instead of iOS.

WebRTC's GN build system does not natively support target_os="tvos".
We work around that by generating with target_os="ios" and then rewriting
every .ninja file to reference the tvOS SDK, deployment-target flags,
clang target triples, Swift library paths, and clang runtime libraries.

Usage:
    python3 tvosify.py <build_dir> <environment>

    build_dir:   GN output directory (e.g. out/tvos-arm64-device)
    environment: "device" or "simulator"
"""

import os
import re
import subprocess
import sys
from pathlib import Path


def xcrun_sdk_path(sdk: str) -> str:
    return subprocess.check_output(
        ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True
    ).strip()


def collect_ninja_files(build_dir: Path) -> list[Path]:
    return sorted(build_dir.rglob("*.ninja"))


def build_replacements(environment: str) -> list[tuple[re.Pattern, str]]:
    """Return a list of (compiled_regex, replacement) pairs."""

    is_device = environment == "device"

    # SDK sysroot paths
    tvos_sdk = xcrun_sdk_path("appletvos" if is_device else "appletvsimulator")
    ios_device_sdk = xcrun_sdk_path("iphoneos")
    ios_sim_sdk = xcrun_sdk_path("iphonesimulator")

    # Deployment-target flags
    tvos_min = "-mtvos-version-min=15.0"
    tvos_sim_min = "-mtvos-simulator-version-min=15.0"
    min_flag = tvos_min if is_device else tvos_sim_min

    # Swift library directories
    swift_from = "iphoneos" if is_device else "iphonesimulator"
    swift_to = "appletvos" if is_device else "appletvsimulator"

    # Clang runtime library  (libclang_rt.ios.a -> libclang_rt.tvos.a)
    rt_from = "libclang_rt.ios.a"
    rt_to = "libclang_rt.tvos.a"
    rt_sim_from = "libclang_rt.iossim.a"
    rt_sim_to = "libclang_rt.tvossim.a"

    rules: list[tuple[re.Pattern, str]] = []

    # 1. SDK sysroot  (plain string, escape for regex)
    rules.append((re.compile(re.escape(ios_device_sdk)), tvos_sdk))
    rules.append((re.compile(re.escape(ios_sim_sdk)), tvos_sdk))

    # 2. Deployment-target min-version flags
    rules.append((re.compile(r"-miphoneos-version-min=[\d.]+"), min_flag))
    rules.append((re.compile(r"-mios-simulator-version-min=[\d.]+"), min_flag))

    # 3. Clang target triple  (order matters: match -simulator suffix first)
    rules.append((
        re.compile(r"-target\s+(arm64|x86_64)-apple-ios([\d.]+)-simulator"),
        r"-target \1-apple-tvos\2-simulator",
    ))
    rules.append((
        re.compile(r"-target\s+(arm64|x86_64)-apple-ios([\d.]+)"),
        r"-target \1-apple-tvos\2",
    ))

    # 4. Swift library search paths
    rules.append((
        re.compile(rf"/swift/{re.escape(swift_from)}\b"),
        f"/swift/{swift_to}",
    ))

    # 5. Clang compiler-rt library  (platform mismatch is a linker error)
    rules.append((re.compile(re.escape(rt_sim_from)), rt_sim_to))
    rules.append((re.compile(re.escape(rt_from)), rt_to))

    return rules


def patch_file(path: Path, rules: list[tuple[re.Pattern, str]]) -> bool:
    """Apply all regex replacements to a single file. Returns True if changed."""
    original = path.read_text(encoding="utf-8", errors="surrogateescape")
    content = original
    for pattern, replacement in rules:
        content = pattern.sub(replacement, content)
    if content != original:
        path.write_text(content, encoding="utf-8", errors="surrogateescape")
        return True
    return False


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: tvosify.py <build_dir> <environment>")
        sys.exit(1)

    build_dir = Path(sys.argv[1])
    environment = sys.argv[2]

    if environment not in ("device", "simulator"):
        print(f"Error: environment must be 'device' or 'simulator', got '{environment}'")
        sys.exit(1)
    if not build_dir.is_dir():
        print(f"Error: build directory does not exist: {build_dir}")
        sys.exit(1)

    rules = build_replacements(environment)

    # Log what we resolved
    print(f"tvosify: Patching '{build_dir}' for tvOS {environment}")
    for pattern, repl in rules:
        print(f"  {pattern.pattern}  →  {repl}")

    ninja_files = collect_ninja_files(build_dir)
    changed = 0
    for nf in ninja_files:
        if patch_file(nf, rules):
            changed += 1

    print(f"tvosify: Patched {changed}/{len(ninja_files)} ninja files.")


if __name__ == "__main__":
    main()
