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
   - 选择"Build Android APK"工作流
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

## 注意事项

### Web端CORS问题
由于浏览器安全限制，Web端访问Tushare API可能遇到CORS错误。解决方案：
1. 使用Android/iOS原生应用（推荐）
2. 配置API代理服务器
3. 使用支持CORS的API服务

### 数据说明
- 股票基本信息：硬编码在应用中
- 股票价格数据：来自Tushare API
- 历史数据：近30天日线数据

## 许可证

MIT License