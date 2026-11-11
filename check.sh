#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
swiftc -swift-version 6 -target arm64-apple-macosx14.0 $(find Core -name '*.swift' -print) Checks/main.swift -o .build/DiskSpaceChecks
.build/DiskSpaceChecks
