# Spokn justfile

# Default recipe
default:
    @just --list

# Build the app in debug mode
build:
    xcodebuild -project Spokn.xcodeproj \
        -scheme Spokn \
        -configuration Debug \
        -derivedDataPath build \
        build

# Build the app in release mode
build-release:
    xcodebuild -project Spokn.xcodeproj \
        -scheme Spokn \
        -configuration Release \
        -derivedDataPath build \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build

# Run tests
test:
    xcodebuild -project Spokn.xcodeproj \
        -scheme Spokn \
        -configuration Debug \
        -derivedDataPath build \
        test

# Clean build artifacts
clean:
    rm -rf build
    rm -rf *.dmg

# Get current version from git tags (or 0.0.0 if none)
@current-version:
    git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0"

# Interactive release - prompts for release type
release:
    #!/usr/bin/env bash
    set -euo pipefail

    current=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
    current=${current#v}
    IFS='.' read -r major minor patch <<< "$current"

    next_major="$((major + 1)).0.0"
    next_minor="${major}.$((minor + 1)).0"
    next_patch="${major}.${minor}.$((patch + 1))"

    echo ""
    echo "Current version: v${current}"
    echo ""
    echo "Select release type:"
    echo "  1) patch  → v${next_patch}"
    echo "  2) minor  → v${next_minor}"
    echo "  3) major  → v${next_major}"
    echo "  q) quit"
    echo ""
    read -p "Choice [1/2/3/q]: " choice

    case $choice in
        1|patch|p)
            new_version="$next_patch"
            ;;
        2|minor|m)
            new_version="$next_minor"
            ;;
        3|major|M)
            new_version="$next_major"
            ;;
        q|Q)
            echo "Aborted."
            exit 0
            ;;
        *)
            echo "Invalid choice. Aborted."
            exit 1
            ;;
    esac

    echo ""
    read -p "Create release v${new_version}? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    just clean
    just _do-release "$new_version"

# Internal: perform the release
_do-release version:
    #!/usr/bin/env bash
    set -euo pipefail
    version="{{version}}"
    echo "Creating release v${version}..."

    # Update version in Xcode project
    just _set-version "$version"

    # Build with new version
    just build-release

    # Create DMG
    just _create-dmg "$version"

    # Commit version bump
    git add Spokn.xcodeproj/project.pbxproj
    git commit -m "Bump version to ${version}"

    # Create and push git tag
    git tag -a "v${version}" -m "Release v${version}"
    git push origin main
    git push origin "v${version}"

    echo ""
    echo "Release v${version} created!"
    echo "DMG: Spokn-${version}.dmg"
    echo "Tag: v${version} pushed to origin"

# Internal: set version in Xcode project
_set-version version:
    #!/usr/bin/env bash
    set -euo pipefail
    version="{{version}}"

    # Update MARKETING_VERSION (display version like 1.2.3)
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${version};/g" Spokn.xcodeproj/project.pbxproj

    # Update CURRENT_PROJECT_VERSION (build number - use version without dots)
    build_number=$(echo "$version" | tr -d '.')
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${build_number};/g" Spokn.xcodeproj/project.pbxproj

    echo "Updated version to ${version} (build ${build_number})"

# Internal: create DMG
_create-dmg version:
    #!/usr/bin/env bash
    set -euo pipefail
    version="{{version}}"
    app_path="build/Build/Products/Release/Spokn.app"
    dmg_name="Spokn-${version}.dmg"

    if [ ! -d "$app_path" ]; then
        echo "Error: App not found at $app_path"
        echo "Run 'just build-release' first"
        exit 1
    fi

    echo "Creating DMG..."

    # Create temporary directory for DMG contents
    tmp_dir=$(mktemp -d)
    cp -R "$app_path" "$tmp_dir/"
    ln -s /Applications "$tmp_dir/Applications"

    # Create DMG
    hdiutil create -volname "Spokn" \
        -srcfolder "$tmp_dir" \
        -ov -format UDZO \
        "$dmg_name"

    # Cleanup
    rm -rf "$tmp_dir"

    echo "Created: $dmg_name"

# Create DMG without releasing (for testing)
dmg: build-release
    just _create-dmg "dev"

# Reset app preferences
reset-prefs:
    defaults delete com.niklasheer.spokn hasLaunchedBefore || true

# Reset accessibility permissions
reset-accessibility:
    tccutil reset Accessibility com.niklasheer.spokn
