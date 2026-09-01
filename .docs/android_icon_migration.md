# Android 图标迁移到统一生成方案

## 背景

之前的图标方案存在以下问题：

1. 手动维护 `luntan_launcher` 和 Flutter 默认 `ic_launcher` 两套资源
2. `AndroidManifest.xml` 中 `icon` 和 `roundIcon` 不一致
3. Adaptive Icon 前景层视觉中心偏上约 6-7%
4. Android 12+ Splash 单独引用前景资源，容易出现尺寸不一致
5. 没有自动化生成流程，每次调整图标需要手动更新多个文件

## 新方案

统一使用 `flutter_launcher_icons` 自动生成所有图标资源：

### 1. 配置 `pubspec.yaml`

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.2

flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/branding/app_icon_source.png"
  adaptive_icon_background: "#FBEAEC"
  adaptive_icon_foreground: "assets/branding/app_icon_source.png"
  min_sdk_android: 21
  remove_alpha_ios: true
```

### 2. 生成图标

```powershell
flutter pub get
dart run flutter_launcher_icons
```

这会自动生成：

- `mipmap-*/ic_launcher.png` - 各密度的图标
- `drawable-*/ic_launcher_foreground.png` - 各密度的前景层
- `mipmap-anydpi-v26/ic_launcher.xml` - Adaptive Icon 定义
- `values/colors.xml` - 背景色定义

### 3. 统一引用

- `AndroidManifest.xml`: 统一使用 `@mipmap/ic_launcher`
- `values-v31/styles.xml`: Splash 使用 `@drawable/ic_launcher_foreground`
- `values-night-v31/styles.xml`: 夜间模式 Splash 同样使用统一前景层

### 4. 删除旧资源

- `mipmap-*/luntan_launcher.png`
- `mipmap-anydpi-v26/luntan_launcher.xml`
- `drawable-nodpi/luntan_launcher_foreground.png`

## 验证清单

构建后必须验证：

```powershell
# 1. 清理并重新构建
flutter clean
flutter build apk --debug

# 2. 检查 APK 内容
# APK 中只应该有 ic_launcher，不应该有 luntan_launcher

# 3. 真机测试
adb devices -l
adb uninstall com.luntan.luntan
adb install build/app/outputs/flutter-apk/app-debug.apk

# 必须卸载后重装，避免 Launcher 缓存旧图标
```

## 当前状态

- ✅ 配置文件已更新
- ✅ 图标已重新生成
- ✅ Manifest 已统一
- ✅ Splash 配置已统一
- ✅ 测试已通过
- ⏳ 待真机验证

## 下一步优化

当前方案直接使用完整插画作为前景层，这不是 Adaptive Icon 的最佳实践。理想方案：

1. **准备两个资产文件**：
   - `app_icon_legacy.png` - 完整 1024×1024 插画（用于 Android < 8）
   - `app_icon_foreground.png` - 透明底，只保留人物+心形牌，视觉中心约 Y=55%

2. **更新配置**：
   ```yaml
   image_path: "assets/branding/app_icon_legacy.png"
   adaptive_icon_foreground: "assets/branding/app_icon_foreground.png"
   ```

3. **好处**：
   - 前景主体不会因为外围装饰而被缩小
   - 视觉中心可以精确控制
   - 各 OEM Launcher 裁切效果更一致
