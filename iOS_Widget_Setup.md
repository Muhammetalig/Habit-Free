# iOS Widget Kurulum Talimatları

iOS'ta widget'ların görünmesi için Xcode'da manuel olarak widget extension eklenmesi gerekiyor.

## Adımlar:

1. **Xcode'da projeyi açın**:
   ```
   open ios/Runner.xcworkspace
   ```

2. **Widget Extension Ekle**:
   - Xcode'da Runner projesine sağ tıklayın
   - "Add Target" > "Widget Extension" seçin
   - Product Name: `SavingsWidget`
   - Bundle Identifier: `com.tasdemir.habitfree.SavingsWidget`
   - "Include Configuration Intent" kapalı bırakın
   - "Finish" butonuna tıklayın

3. **Widget dosyalarını değiştirin**:
   - Oluşturulan `SavingsWidget.swift` dosyasını silin
   - `ios/SavingsWidget/` klasöründeki dosyaları Xcode'daki SavingsWidget target'ına sürükleyip bırakın

4. **App Groups ekleyin**:
   - Runner target'ını seçin
   - "Signing & Capabilities" sekmesine gidin
   - "+" butonuna tıklayıp "App Groups" ekleyin
   - `group.com.tasdemir.habitfree` ekleyin
   - SavingsWidget target'ı için de aynı işlemi yapın

5. **Build Settings**:
   - SavingsWidget target'ında "iOS Deployment Target"ı 14.0 yapın

6. **Widget'ı test edin**:
   - Projeyi build edin ve cihaza yükleyin
   - iOS widget gallery'sinde "Bağımlılık Tasarruf" widget'ını arayın

## Sorun Giderme:

- Widget görünmüyorsa cihazı yeniden başlatın
- App Groups ayarlarının her iki target'ta da aynı olduğundan emin olun
- Bundle identifier'ların doğru olduğundan emin olun
