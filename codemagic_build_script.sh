#!/usr/bin/env bash
set -Eeuo pipefail
set -x

# ---- Proje kökü ----
APP_DIR="${CM_BUILD_DIR:-$PWD}/bagimliss"
cd "$APP_DIR"

# ---- Flutter bağımlılıkları ----
flutter --version
flutter clean
flutter pub get

# ---- iOS Pod/target ayarları (min iOS 14) ----
cd ios

# Podfile yaz (güncel, Flutter uyumlu)
cat > Podfile <<'RUBY'
platform :ios, '14.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. Run flutter pub get first."
  end
  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup if respond_to?(:flutter_ios_podfile_setup)

target 'Runner' do
  use_frameworks! :linkage => :static
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
    flutter_additional_ios_build_settings(t)
  end
end
RUBY

# pbxproj içinde sadece iOS deployment target'ı güvenli şekilde güncelle
PBX="Runner.xcodeproj/project.pbxproj"
if [[ -f "$PBX" ]]; then
  # Sadece iOS 12.0 ve 13.0 varsa 14.0 yap (güvenli)
  /usr/bin/sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 1[23]\.0;/IPHONEOS_DEPLOYMENT_TARGET = 14.0;/g' "$PBX" || true
  echo "✅ iOS deployment target güncellendi"
else
  echo "⚠️  pbxproj dosyası bulunamadı"
fi

# Pod'ları temiz kur
rm -rf Pods Podfile.lock
pod install --repo-update

# ---- IPA üret ----
cd ..

# Build adı sabit/etiketten gelebilir
BUILD_NAME="${CM_TAG:-1.0.0}"

# Build numarası her zaman daha büyük olsun (UTC timestamp)
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"

echo "ℹ️  Build Name: $BUILD_NAME"
echo "ℹ️  Build Number: $BUILD_NUMBER"

# Flutter kendi version management'ını kullanarak derle
flutter build ipa --release \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

echo "✅ IPA hazır: $(ls -1 build/ios/ipa | tr -d '\r')"
echo "ℹ️  Version: $BUILD_NAME  |  Build: $BUILD_NUMBER"
