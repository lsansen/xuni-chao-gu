# 虚拟炒股 - Flutter应用

一个基于Flutter开发的股票模拟交易应用，支持Web和Android平台。

## 功能特性

- 12个行业类别，144只股票
- 实时数据更新（交易时间30秒，非交易时间5分钟）
- K线图表显示
- 持仓管理和交易功能
- 股票搜索功能
- 自动刷新开关
- 资金管理和解锁系统

## 隐私安全提醒

### API密钥配置

在使用本应用之前，您需要配置以下API密钥：

1. **Tushare API密钥**
   - 位置：`lib/main.dart` 文件中的 `TushareApi` 类
   - 替换为您的Tushare API密钥：
     ```dart
     static const String token = 'YOUR_TUSHARE_API_TOKEN';
     ```

2. **雪球API Token**
   - 位置：`lib/main.dart` 文件中的 `fetchXueqiuKLineData` 方法
   - 替换为您的雪球API token：
     ```dart
     'Cookie': 'xq_a_token=YOUR_XUEQIU_TOKEN',
     ```

### 环境变量配置

- **Java环境变量**：确保Java 21已正确安装并配置环境变量
  - 参考：`run_app.ps1` 文件中的配置

## 环境配置

### Java环境配置（Android构建需要）

1. **安装Java 21**
   - 下载地址：https://www.oracle.com/java/technologies/downloads/
   - 安装后配置环境变量

2. **配置环境变量**
   - Windows：
     ```powershell
     $env:JAVA_HOME = "D:\java\java21"
     $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
     ```
   - Linux/macOS：
     ```bash
     export JAVA_HOME="/path/to/java21"
     export PATH="$JAVA_HOME/bin:$PATH"
     ```

3. **验证Java版本**
   ```bash
   java -version
   ```

## 项目结构

```
.
├── .github/           # GitHub Actions配置
├── android/           # Android平台代码
├── ios/               # iOS平台代码
├── lib/               # Flutter主代码
│   ├── main.dart      # 应用入口
│   └── api_manager.dart # API管理
├── web/               # Web平台代码
├── build/             # 构建输出目录
├── .gitignore         # Git忽略文件配置
├── README.md          # 项目说明文档
├── run_app.ps1        # 运行脚本
└── pubspec.yaml       # 项目依赖配置
```

## 构建APK

### 方法1：使用GitHub Actions（推荐）

1. **推送代码到GitHub**
   ```bash
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/your-username/xuni-chao-gu.git
   git push -u origin main
   ```

2. **自动构建**
   - 推送后，GitHub Actions会自动构建APK
   - 在Actions标签页查看构建进度
   - 构建完成后下载APK文件

3. **手动触发构建**
   - 访问仓库的Actions页面
   - 选择"Flutter CI"工作流
   - 点击"Run workflow"手动触发

### 方法2：使用Codemagic

1. **访问Codemagic**
   - 网址：https://codemagic.io
   - 使用GitHub账号登录

2. **导入项目**
   - 导入GitHub仓库
   - 选择Flutter项目
   - 配置Android构建

3. **构建APK**
   - 点击构建按钮
   - 下载生成的APK文件

### 方法3：本地构建（需要Android SDK）

1. **安装Android Studio**
   - 下载：https://developer.android.com/studio
   - 安装后会自动配置Android SDK

2. **构建APK**
   ```bash
   flutter build apk --release
   ```

3. **APK位置**
   - `build/app/outputs/flutter-apk/app-release.apk`

## Web应用

### 本地运行
```bash
flutter run -d chrome
```

### 构建Web应用
```bash
flutter build web --release
```

### 本地测试Web应用
```bash
cd build/web
python -m http.server 8080
```

访问：http://localhost:8080

## 部署

### Web部署
- Vercel：https://vercel.com
- GitHub Pages：在仓库设置中启用
- Netlify：https://netlify.com

### Android部署
- 直接安装APK文件
- 或发布到Google Play Store

## 技术栈

- Flutter 3.41.2
- Dart 3.11.0
- Tushare API（股票数据）
- fl_chart（K线图表）
- Dio（网络请求）

## 运行前的准备工作

1. **安装Flutter**
   - 下载地址：https://docs.flutter.dev/get-started/install
   - 按照官方文档安装并配置

2. **克隆项目**
   ```bash
   git clone https://github.com/your-username/xuni-chao-gu.git
   cd xuni-chao-gu
   ```

3. **安装依赖**
   ```bash
   flutter pub get
   ```

4. **配置API密钥**
   - 按照"隐私安全提醒"部分的说明配置API密钥

5. **运行应用**
   - Web端：`flutter run -d chrome`
   - Android端：连接设备后运行 `flutter run`

## 常见问题及解决方案

### 1. 构建失败：Java版本不兼容

**解决方案**：
- 确保安装了Java 21
- 正确配置JAVA_HOME环境变量
- 使用 `run_app.ps1` 脚本运行应用

### 2. Web端CORS错误

**解决方案**：
- 使用Android/iOS原生应用（推荐）
- 配置API代理服务器
- 使用支持CORS的API服务

### 3. API调用频率限制

**解决方案**：
- 应用已内置API调用频率控制
- 避免频繁刷新数据
- 考虑升级Tushare API套餐

### 4. GitHub Actions构建失败

**解决方案**：
- 确保 `actions/upload-artifact` 版本为v4
- 检查API密钥配置
- 查看GitHub Actions日志获取详细错误信息

## 数据说明

- 股票基本信息：硬编码在应用中
- 股票价格数据：来自Tushare API
- 历史数据：近30天日线数据

## 许可证

MIT License
