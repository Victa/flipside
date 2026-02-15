#!/bin/zsh

# FlipSide Build Script
# Build your iOS app without opening Xcode

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project configuration
PROJECT_NAME="FlipSide"
SCHEME="FlipSide"
PROJECT_FILE="FlipSide.xcodeproj"
DERIVED_DATA_PATH="./build"

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to display usage
usage() {
    cat << EOF
Usage: ./build.sh [command] [options]

Commands:
    run             Build and launch app in simulator (default)
    logs            Stream real-time logs from the app
    simulator       Build for iOS Simulator (without launching)
    device          Build for iOS Device
    clean           Clean build artifacts
    test            Run tests
    perf            Run performance budget tests
    archive         Create an archive (for App Store/TestFlight)
    help            Show this help message

Options:
    -c, --configuration  Build configuration (Debug or Release, default: Debug)
    -s, --simulator      Simulator name (e.g., "iPhone 17 Pro") - uses generic if not specified
    -d, --destination    Custom destination string (advanced)
    -v, --verbose        Enable verbose output

Examples:
    ./build.sh                              # Build and launch app in simulator
    ./build.sh run                          # Build and launch app in simulator
    ./build.sh logs                         # Stream real-time logs from app
    ./build.sh run -s "iPhone 17 Pro"       # Launch on specific iPhone 17 Pro
    ./build.sh simulator                    # Build only (don't launch)
    ./build.sh simulator -c Release         # Build for simulator (Release)
    ./build.sh device                       # Build for device
    ./build.sh clean                        # Clean build artifacts
    ./build.sh test                         # Run tests
    ./build.sh perf                         # Run performance budget tests
    ./build.sh archive                      # Create release archive

EOF
}

# Parse command line arguments
COMMAND="${1:-run}"
CONFIGURATION="Debug"
SIMULATOR_NAME="Any iOS Simulator Device"
USE_GENERIC_SIMULATOR=true
DESTINATION=""
VERBOSE=""

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -s|--simulator)
            SIMULATOR_NAME="$2"
            USE_GENERIC_SIMULATOR=false
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-verbose"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default destination if not specified
if [ -z "$DESTINATION" ]; then
    if [ "$USE_GENERIC_SIMULATOR" = true ]; then
        DESTINATION="generic/platform=iOS Simulator"
    else
        DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
    fi
fi

# Function to find or boot simulator
get_simulator_udid() {
    local sim_name="$1"
    local udid=""
    
    if [ "$sim_name" = "Any iOS Simulator Device" ]; then
        # Get any available iOS simulator, prefer booted ones
        udid=$(xcrun simctl list devices | grep -m 1 "iPhone.*Booted" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
        
        if [ -z "$udid" ]; then
            # No booted simulator, get the first available iPhone
            udid=$(xcrun simctl list devices available | grep -m 1 "iPhone" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
        fi
    else
        # Look for specific simulator by name
        udid=$(xcrun simctl list devices | grep "$sim_name" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    fi
    
    echo "$udid"
}

# xcodebuild test requires a concrete simulator destination.
resolve_test_destination() {
    local destination="$1"

    if [ "$destination" = "generic/platform=iOS Simulator" ]; then
        echo "platform=iOS Simulator,name=iPhone 17 Pro"
    else
        echo "$destination"
    fi
}

# Main script logic
case $COMMAND in
    run)
        print_info "Building and launching $PROJECT_NAME on iOS Simulator ($CONFIGURATION)..."
        
        # Build first
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -sdk iphonesimulator \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            build \
            $VERBOSE
        
        if [ $? -ne 0 ]; then
            print_error "Build failed!"
            exit 1
        fi
        
        print_success "Build completed!"
        
        # Find the built app
        APP_PATH=$(find "$DERIVED_DATA_PATH" -name "*.app" -path "*/Build/Products/*" | head -1)
        
        if [ -z "$APP_PATH" ]; then
            print_error "Could not find built app in $DERIVED_DATA_PATH"
            exit 1
        fi
        
        print_info "App location: $APP_PATH"
        
        # Get simulator UDID
        SIMULATOR_UDID=$(get_simulator_udid "$SIMULATOR_NAME")
        
        if [ -z "$SIMULATOR_UDID" ]; then
            print_error "Could not find simulator. Please open Xcode and install a simulator."
            exit 1
        fi
        
        print_info "Using simulator: $SIMULATOR_UDID"
        
        # Boot simulator if not already booted
        SIMULATOR_STATE=$(xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -o "Booted\|Shutdown")
        
        if [ "$SIMULATOR_STATE" != "Booted" ]; then
            print_info "Booting simulator..."
            xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
            sleep 2
        fi
        
        # Open Simulator app
        open -a Simulator
        
        # Install the app
        print_info "Installing app on simulator..."
        xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
        
        # Get bundle identifier using PlistBuddy
        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null)
        
        if [ -z "$BUNDLE_ID" ]; then
            print_error "Could not read bundle identifier from Info.plist"
            exit 1
        fi
        
        # Launch the app
        print_info "Launching app..."
        xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
        
        print_success "App launched successfully! 🚀"
        print_info "Bundle ID: $BUNDLE_ID"
        ;;
    
    simulator)
        print_info "Building $PROJECT_NAME for iOS Simulator ($CONFIGURATION)..."
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -sdk iphonesimulator \
            -destination "$DESTINATION" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            clean build \
            $VERBOSE
        
        print_success "Build completed successfully!"
        print_info "Build artifacts: $DERIVED_DATA_PATH"
        ;;
    
    device)
        print_info "Building $PROJECT_NAME for iOS Device ($CONFIGURATION)..."
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -destination "generic/platform=iOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            clean build \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            $VERBOSE
        
        print_success "Build completed successfully!"
        print_warning "Note: Code signing is disabled. For distribution, use 'archive' command."
        ;;
    
    clean)
        print_info "Cleaning build artifacts..."
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            clean \
            $VERBOSE
        
        if [ -d "$DERIVED_DATA_PATH" ]; then
            rm -rf "$DERIVED_DATA_PATH"
            print_info "Removed derived data: $DERIVED_DATA_PATH"
        fi
        
        print_success "Clean completed successfully!"
        ;;
    
    test)
        print_info "Running tests for $PROJECT_NAME..."
        TEST_DESTINATION=$(resolve_test_destination "$DESTINATION")
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -destination "$TEST_DESTINATION" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            test \
            $VERBOSE
        
        print_success "Tests completed successfully!"
        ;;

    perf)
        print_info "Running performance budget tests for $PROJECT_NAME..."
        TEST_DESTINATION=$(resolve_test_destination "$DESTINATION")
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -destination "$TEST_DESTINATION" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            test \
            -only-testing:FlipSideTests \
            $VERBOSE

        print_success "Performance budget tests completed successfully!"
        ;;
    
    archive)
        print_info "Creating archive for $PROJECT_NAME (Release)..."
        ARCHIVE_PATH="./build/FlipSide.xcarchive"
        
        xcodebuild \
            -project "$PROJECT_FILE" \
            -scheme "$SCHEME" \
            -configuration Release \
            -archivePath "$ARCHIVE_PATH" \
            archive \
            $VERBOSE
        
        print_success "Archive created successfully!"
        print_info "Archive location: $ARCHIVE_PATH"
        print_info "To export the archive, use Xcode or xcodebuild -exportArchive"
        ;;
    
    logs)
        print_info "Streaming logs from $PROJECT_NAME..."
        print_warning "Press Ctrl+C to stop"
        echo ""
        
        # Get the simulator UDID
        SIMULATOR_UDID=$(get_simulator_udid "$SIMULATOR_NAME")
        
        if [ -z "$SIMULATOR_UDID" ]; then
            print_error "No simulator found. Please run './build.sh run' first to start the app."
            exit 1
        fi
        
        # Check if simulator is booted
        SIMULATOR_STATE=$(xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -o "Booted\|Shutdown" || echo "Shutdown")
        
        if [ "$SIMULATOR_STATE" != "Booted" ]; then
            print_error "Simulator is not running. Please run './build.sh run' first."
            exit 1
        fi
        
        print_info "Simulator: $SIMULATOR_UDID"
        print_info "Showing logs with level: debug"
        echo ""
        
        # Stream logs with color output
        # Using 'unbuffer' if available for better streaming, otherwise direct
        if command -v unbuffer &> /dev/null; then
            unbuffer xcrun simctl spawn "$SIMULATOR_UDID" log stream \
                --predicate 'processImagePath contains "FlipSide"' \
                --style compact \
                --level debug \
                --color always
        else
            xcrun simctl spawn "$SIMULATOR_UDID" log stream \
                --predicate 'processImagePath contains "FlipSide"' \
                --style compact \
                --level debug \
                --color auto
        fi
        ;;
    
    help|--help|-h)
        usage
        exit 0
        ;;
    
    *)
        print_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
