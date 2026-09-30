# MoleUI Build Script (Native Xcode + Just)

default:
    @just --list

scheme := "MoleUI"
app_name := "Mole UI"

# ============================================
# Development
# ============================================

# Build Debug
build:
    xcodebuild -scheme {{scheme}} \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        build

# Build Release
build-release:
    xcodebuild -scheme {{scheme}} \
        -configuration Release \
        -archivePath build/{{app_name}}.xcarchive \
        archive

# Internal/ad-hoc Release app + zip under dist/ (no notarization)
build-internal:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p dist build/DerivedData
    xcodebuild -scheme {{scheme}} \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "{{justfile_directory()}}/build/DerivedData" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build
    rm -rf "dist/{{app_name}}.app"
    cp -R "build/DerivedData/Build/Products/Release/{{app_name}}.app" "dist/{{app_name}}.app"
    if [ ! -x "dist/{{app_name}}.app/Contents/Resources/mactop/mactop" ] && [ -x Resources/mactop/mactop ]; then
      mkdir -p "dist/{{app_name}}.app/Contents/Resources/mactop"
      cp -f Resources/mactop/mactop "dist/{{app_name}}.app/Contents/Resources/mactop/mactop"
      cp -f Resources/mactop/LICENSE "dist/{{app_name}}.app/Contents/Resources/mactop/" 2>/dev/null || true
    fi
    chmod +x "dist/{{app_name}}.app/Contents/Resources/mactop/mactop" 2>/dev/null || true
    codesign --force --deep --sign - "dist/{{app_name}}.app"
    ditto -c -k --keepParent "dist/{{app_name}}.app" "dist/MoleUI-internal.zip"
    echo "Internal build ready:"
    echo "  dist/{{app_name}}.app"
    echo "  dist/MoleUI-internal.zip"

# Run
run: build
    @open ~/Library/Developer/Xcode/DerivedData/MoleUI-*/Build/Products/Debug/"{{app_name}}.app"

# Clean
clean:
    xcodebuild clean -scheme {{scheme}}
    rm -rf ~/Library/Developer/Xcode/DerivedData/MoleUI-*

# ============================================
# Code Quality
# ============================================

fmt:
    swiftformat MoleUI/

lint:
    swiftlint

# ============================================
# Mole CLI
# ============================================

# Update bundled Mole CLI
update-mole:
    brew upgrade mole || brew install mole
    rm -rf Resources/mole/*
    cp -R /opt/homebrew/Cellar/mole/*/libexec/* Resources/mole/
    cp /opt/homebrew/Cellar/mole/*/bin/mole Resources/mole/
    sed -i '' 's|SCRIPT_DIR=.*|SCRIPT_DIR="$$(cd \\"$$(dirname \\"$${BASH_SOURCE[0]}\\")\\" \&\& pwd)"|' Resources/mole/mole

# Place local mactop arm64 binary for Monitor (gitignored)
update-mactop:
    brew upgrade mactop || brew install mactop
    mkdir -p Resources/mactop
    cp /opt/homebrew/bin/mactop Resources/mactop/mactop
    chmod +x Resources/mactop/mactop
    @file Resources/mactop/mactop

# ============================================
# Release
# ============================================

# Package DMG
package: build-release
    mkdir -p dist
    create-dmg \
        --volname "{{app_name}}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "{{app_name}}.app" 150 185 \
        --app-drop-link 450 185 \
        dist/MoleUI.dmg \
        build/"{{app_name}}".xcarchive/Products/Applications/ || true

sign-and-notarize: package
    codesign --force --deep --timestamp --options runtime \
        --sign "Developer ID Application: Fuyao Qin (646VSJ9K5F)" \
        dist/MoleUI.dmg
    xcrun notarytool submit dist/MoleUI.dmg \
        --keychain-profile "notary-profile" \
        --wait

# ============================================
# CI/CD
# ============================================

ci-build: build
    @echo "CI build done"

ci-release: build-release package sign-and-notarize
    @echo "CI release done"

# Project info
info:
    @echo "Swift: $(swift --version | head -1)"
    @echo "Xcode: $(xcodebuild -version | head -1)"
    @Resources/mole/mole version 2>/dev/null | head -1 || echo "Mole CLI: not found"
