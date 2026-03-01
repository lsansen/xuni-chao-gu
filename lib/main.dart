import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gbk_codec/gbk_codec.dart';

// API提供者枚举
enum ApiProvider {
  tencent,
  eastMoney,
  sina,
  xueqiu,
}

// API配置类
class ApiConfig {
  final String name;
  final ApiProvider provider;
  final String baseUrl;
  final int maxCallsPerMinute;
  final int maxCallsPerHour;
  final int maxRetries;
  final Duration timeout;
  final bool supportsRealTime;
  final bool supportsHistorical;

  const ApiConfig({
    required this.name,
    required this.provider,
    required this.baseUrl,
    this.maxCallsPerMinute = 60,
    this.maxCallsPerHour = 1000,
    this.maxRetries = 3,
    this.timeout = const Duration(seconds: 15),
    this.supportsRealTime = true,
    this.supportsHistorical = false,
  });
}

// API调用记录类
class ApiCallRecord {
  final ApiProvider provider;
  final DateTime timestamp;
  final bool success;
  final int responseTime;
  final String? error;

  ApiCallRecord({
    required this.provider,
    required this.timestamp,
    required this.success,
    required this.responseTime,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'responseTime': responseTime,
      'error': error,
    };
  }
}

// API监控类
class ApiMonitor {
  final Map<ApiProvider, List<ApiCallRecord>> _callRecords = {};
  final Map<ApiProvider, int> _callCountPerMinute = {};
  final Map<ApiProvider, int> _callCountPerHour = {};
  final Map<ApiProvider, DateTime> _lastCallTime = {};

  void recordCall(ApiProvider provider, bool success, int responseTime, [String? error]) {
    final now = DateTime.now();
    
    // 记录调用
    if (!_callRecords.containsKey(provider)) {
      _callRecords[provider] = [];
    }
    _callRecords[provider]!.add(ApiCallRecord(
      provider: provider,
      timestamp: now,
      success: success,
      responseTime: responseTime,
      error: error,
    ));

    // 只保留最近100条记录
    if (_callRecords[provider]!.length > 100) {
      _callRecords[provider]!.removeAt(0);
    }

    // 更新调用计数
    _updateCallCounts(provider, now);
  }

  void _updateCallCounts(ApiProvider provider, DateTime now) {
    // 每分钟调用计数
    if (!_callCountPerMinute.containsKey(provider)) {
      _callCountPerMinute[provider] = 0;
    }
    _callCountPerMinute[provider] = _callCountPerMinute[provider]! + 1;

    // 每小时调用计数
    if (!_callCountPerHour.containsKey(provider)) {
      _callCountPerHour[provider] = 0;
    }
    _callCountPerHour[provider] = _callCountPerHour[provider]! + 1;

    _lastCallTime[provider] = now;
  }

  bool canMakeCall(ApiProvider provider, ApiConfig config) {
    final now = DateTime.now();
    
    // 检查每分钟限制
    if (_callCountPerMinute.containsKey(provider)) {
      final lastCall = _lastCallTime[provider];
      if (lastCall != null && now.difference(lastCall).inMinutes < 1) {
        if (_callCountPerMinute[provider]! >= config.maxCallsPerMinute) {
          return false;
        }
      } else {
        _callCountPerMinute[provider] = 0;
      }
    }

    // 检查每小时限制
    if (_callCountPerHour.containsKey(provider)) {
      final lastCall = _lastCallTime[provider];
      if (lastCall != null && now.difference(lastCall).inHours < 1) {
        if (_callCountPerHour[provider]! >= config.maxCallsPerHour) {
          return false;
        }
      } else {
        _callCountPerHour[provider] = 0;
      }
    }

    return true;
  }

  List<ApiCallRecord> getRecentCalls(ApiProvider provider, int count) {
    if (!_callRecords.containsKey(provider)) {
      return [];
    }
    final records = _callRecords[provider]!;
    if (records.length <= count) {
      return List.from(records);
    }
    return records.sublist(records.length - count);
  }

  double getSuccessRate(ApiProvider provider) {
    if (!_callRecords.containsKey(provider) || _callRecords[provider]!.isEmpty) {
      return 1.0;
    }
    final records = _callRecords[provider]!;
    final successCount = records.where((r) => r.success).length;
    return successCount / records.length;
  }
}

// 股票数据模型
class Stock {
  final String code;
  final String name;
  final double currentPrice;
  final double change;
  final double changePercent;
  List<double> historicalPrices;
  List<String> historicalDates;
  bool hasData;
  String? cacheTimestamp;

  Stock({
    required this.code,
    required this.name,
    required this.currentPrice,
    required this.change,
    required this.changePercent,
    required this.historicalPrices,
    required this.historicalDates,
    this.hasData = false,
    this.cacheTimestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'currentPrice': currentPrice,
      'change': change,
      'changePercent': changePercent,
      'historicalPrices': historicalPrices,
      'historicalDates': historicalDates,
      'hasData': hasData,
      'cacheTimestamp': cacheTimestamp,
    };
  }

  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      code: json['code'],
      name: json['name'],
      currentPrice: json['currentPrice'],
      change: json['change'],
      changePercent: json['changePercent'],
      historicalPrices: List<double>.from(json['historicalPrices']),
      historicalDates: List<String>.from(json['historicalDates']),
      hasData: json['hasData'],
      cacheTimestamp: json['cacheTimestamp'],
    );
  }
}

// 股票基本信息
class StockBasic {
  final String code;
  final String name;
  final String industry;

  StockBasic({
    required this.code,
    required this.name,
    required this.industry,
  });
}

// 行业分类
class Industry {
  final String name;
  final List<StockBasic> stocks;

  Industry({
    required this.name,
    required this.stocks,
  });
}

// 持仓项
class PortfolioItem {
  final String stockCode;
  int quantity;
  double averagePrice;

  PortfolioItem({
    required this.stockCode,
    required this.quantity,
    required this.averagePrice,
  });

  Map<String, dynamic> toJson() {
    return {
      'stockCode': stockCode,
      'quantity': quantity,
      'averagePrice': averagePrice,
    };
  }

  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      stockCode: json['stockCode'],
      quantity: json['quantity'],
      averagePrice: json['averagePrice'],
    );
  }
}

// 卖出记录
class SellRecord {
  final String stockCode;
  final String stockName;
  final int quantity;
  final double price;
  final double amount;
  final DateTime time;

  SellRecord({
    required this.stockCode,
    required this.stockName,
    required this.quantity,
    required this.price,
    required this.amount,
    required this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'stockCode': stockCode,
      'stockName': stockName,
      'quantity': quantity,
      'price': price,
      'amount': amount,
      'time': time.toIso8601String(),
    };
  }

  factory SellRecord.fromJson(Map<String, dynamic> json) {
    return SellRecord(
      stockCode: json['stockCode'],
      stockName: json['stockName'],
      quantity: json['quantity'],
      price: json['price'],
      amount: json['amount'],
      time: DateTime.parse(json['time']),
    );
  }
}

// API管理类
class TushareApi {
  static const String token = 'YOUR_TUSHARE_TOKEN'; // 请替换为您的Tushare token
  
  final Dio _dio = Dio();
  final ApiMonitor _monitor = ApiMonitor();
  final Map<String, Stock> _cache = {};
  final Duration _cacheValidity = const Duration(minutes: 5);
  
  // API配置
  final Map<ApiProvider, ApiConfig> _configs = {
    ApiProvider.tencent: const ApiConfig(
      name: '腾讯财经',
      provider: ApiProvider.tencent,
      baseUrl: 'http://qt.gtimg.cn',
      maxCallsPerMinute: 60,
      maxCallsPerHour: 1000,
    ),
    ApiProvider.eastMoney: const ApiConfig(
      name: '东方财富',
      provider: ApiProvider.eastMoney,
      baseUrl: 'https://push2.eastmoney.com',
      maxCallsPerMinute: 30,
      maxCallsPerHour: 500,
    ),
    ApiProvider.sina: const ApiConfig(
      name: '新浪财经',
      provider: ApiProvider.sina,
      baseUrl: 'https://hq.sinajs.cn',
      maxCallsPerMinute: 40,
      maxCallsPerHour: 800,
    ),
    ApiProvider.xueqiu: const ApiConfig(
      name: '雪球',
      provider: ApiProvider.xueqiu,
      baseUrl: 'https://stock.xueqiu.com',
      maxCallsPerMinute: 20,
      maxCallsPerHour: 300,
      supportsHistorical: true,
    ),
  };

  final List<Industry> _industries = [
    Industry(name: '金融', stocks: [
      StockBasic(code: '600036.SH', name: '招商银行', industry: '金融'),
      StockBasic(code: '601398.SH', name: '工商银行', industry: '金融'),
      StockBasic(code: '601288.SH', name: '农业银行', industry: '金融'),
      StockBasic(code: '601988.SH', name: '中国银行', industry: '金融'),
      StockBasic(code: '601318.SH', name: '中国平安', industry: '金融'),
      StockBasic(code: '600030.SH', name: '中信证券', industry: '金融'),
      StockBasic(code: '601166.SH', name: '兴业银行', industry: '金融'),
      StockBasic(code: '600016.SH', name: '民生银行', industry: '金融'),
    ]),
    Industry(name: '科技', stocks: [
      StockBasic(code: '000725.SZ', name: '京东方A', industry: '科技'),
      StockBasic(code: '002415.SZ', name: '海康威视', industry: '科技'),
      StockBasic(code: '603501.SH', name: '韦尔股份', industry: '科技'),
      StockBasic(code: '688981.SH', name: '中芯国际', industry: '科技'),
      StockBasic(code: '603288.SH', name: '海天味业', industry: '科技'),
      StockBasic(code: '600519.SH', name: '贵州茅台', industry: '科技'),
      StockBasic(code: '000858.SZ', name: '五粮液', industry: '科技'),
      StockBasic(code: '002594.SZ', name: '比亚迪', industry: '科技'),
    ]),
    Industry(name: '医药', stocks: [
      StockBasic(code: '600276.SH', name: '恒瑞医药', industry: '医药'),
      StockBasic(code: '000538.SZ', name: '云南白药', industry: '医药'),
      StockBasic(code: '603259.SH', name: '药明康德', industry: '医药'),
      StockBasic(code: '300760.SZ', name: '迈瑞医疗', industry: '医药'),
      StockBasic(code: '600436.SH', name: '片仔癀', industry: '医药'),
      StockBasic(code: '000963.SZ', name: '华东医药', industry: '医药'),
      StockBasic(code: '600196.SH', name: '复星医药', industry: '医药'),
      StockBasic(code: '300122.SZ', name: '智飞生物', industry: '医药'),
    ]),
    Industry(name: '消费', stocks: [
      StockBasic(code: '000333.SZ', name: '美的集团', industry: '消费'),
      StockBasic(code: '000651.SZ', name: '格力电器', industry: '消费'),
      StockBasic(code: '600887.SH', name: '伊利股份', industry: '消费'),
      StockBasic(code: '002304.SZ', name: '洋河股份', industry: '消费'),
      StockBasic(code: '600690.SH', name: '海尔智家', industry: '消费'),
      StockBasic(code: '000568.SZ', name: '泸州老窖', industry: '消费'),
      StockBasic(code: '603288.SH', name: '海天味业', industry: '消费'),
      StockBasic(code: '600132.SH', name: '重庆啤酒', industry: '消费'),
    ]),
    Industry(name: '新能源', stocks: [
      StockBasic(code: '300750.SZ', name: '宁德时代', industry: '新能源'),
      StockBasic(code: '601012.SH', name: '隆基绿能', industry: '新能源'),
      StockBasic(code: '002594.SZ', name: '比亚迪', industry: '新能源'),
      StockBasic(code: '601669.SH', name: '中国电建', industry: '新能源'),
      StockBasic(code: '600438.SH', name: '通威股份', industry: '新能源'),
      StockBasic(code: '002460.SZ', name: '赣锋锂业', industry: '新能源'),
      StockBasic(code: '603659.SH', name: '璞泰来', industry: '新能源'),
      StockBasic(code: '300014.SZ', name: '亿纬锂能', industry: '新能源'),
    ]),
  ];

  List<Industry> get industries => _industries;
  List<StockBasic> get allStocks => _industries.expand((i) => i.stocks).toList();

  // 检查缓存是否有效
  bool _isCacheValid(String code) {
    if (!_cache.containsKey(code)) return false;
    final cached = _cache[code]!;
    if (cached.cacheTimestamp == null) return false;
    final cacheTime = DateTime.parse(cached.cacheTimestamp!);
    return DateTime.now().difference(cacheTime) < _cacheValidity;
  }

  // 清理过期缓存（内存缓存）
  void _cleanExpiredMemoryCache() {
    final now = DateTime.now();
    _cache.removeWhere((code, stock) {
      if (stock.cacheTimestamp == null) return true;
      final cacheTime = DateTime.parse(stock.cacheTimestamp!);
      return now.difference(cacheTime) > const Duration(days: 365);
    });
  }

  // 获取股票近30天日线数据
  Future<Stock> getStockData(String code, {String period = 'daily', SharedPreferences? prefs}) async {
    try {
      // 转换股票代码格式为腾讯财经 API 格式
      String tencentCode = code;
      if (code.endsWith('.SH')) {
        tencentCode = 'sh' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        tencentCode = 'sz' + code.replaceAll('.SZ', '');
      } else if (code.endsWith('.HK')) {
        tencentCode = 'hk' + code.replaceAll('.HK', '');
      }
      
      // 调用腾讯财经 API
      final response = await _dio.get(
        'http://qt.gtimg.cn/q=$tencentCode',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Encoding': 'gzip, deflate',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
        ),
      );

      if (response.statusCode == 200) {
        // 使用GBK解码响应数据
        final bytes = response.data as List<int>;
        final data = gbk_bytes.decode(bytes);
        
        // 调试输出 API 响应
        print('=== Tencent API Response for $code ===');
        print('Response data: $data');
        print('=================================');
        
        // 解析腾讯财经返回的数据
        // 格式：v_sh600036="1~招商银行~600036~35.68~35.67~35.66~...";
        // 字段索引：0=类型, 1=名称, 2=代码, 3=当前价, 4=开盘价, 5=前收盘价
        final parts = data.split('"');
        if (parts.length >= 2) {
          final stockData = parts[1].split('~');
          if (stockData.length >= 6) {
            String name = stockData[1];
            // 如果名称仍然为空或乱码，使用行业分类中的股票名称
            if (name.isEmpty || name.length < 2) {
              // 如果名称为空或太短，使用行业分类中的股票名称
              for (final industry in _industries) {
                final stockBasic = industry.stocks.firstWhere(
                  (s) => s.code == code,
                  orElse: () => StockBasic(code: code, name: code, industry: ''),
                );
                if (stockBasic.name != code) {
                  name = stockBasic.name;
                  break;
                }
              }
            }
            final currentPrice = double.tryParse(stockData[3]) ?? 0.0;
            // 从第6个字段获取前收盘价（索引5）
            final previousPrice = double.tryParse(stockData[5]) ?? 0.0;
            final change = currentPrice - previousPrice;
            final changePercent = previousPrice != 0 ? (change / previousPrice) * 100 : 0.0;
            
            // 尝试获取历史数据（使用雪球API）
            final historicalData = await _getHistoricalData(code, period: period);
            
            // 创建股票对象
            final stock = Stock(
              code: code,
              name: name,
              currentPrice: currentPrice,
              change: change,
              changePercent: changePercent,
              historicalPrices: (historicalData['prices'] as List<dynamic>).map((e) => e as double).toList(),
              historicalDates: (historicalData['dates'] as List<dynamic>).map((e) => e as String).toList(),
              hasData: true,
              cacheTimestamp: DateTime.now().toIso8601String(),
            );
            
            // 保存到缓存
            if (prefs != null) {
              final cacheKey = 'stock_cache_$code';
              await prefs.setString(cacheKey, jsonEncode(stock.toJson()));
              
              // 清理过期缓存（超过一年）
              await _cleanExpiredCache(prefs);
            }
            
            // 输出真实数据信息
            print('=== Real Data for $code ===');
            print('Name: $name');
            print('Current Price: ${currentPrice.toStringAsFixed(2)}');
            print('Previous Price: ${previousPrice.toStringAsFixed(2)}');
            print('Change: ${change.toStringAsFixed(2)}');
            print('Change Percent: ${changePercent.toStringAsFixed(2)}%');
            print('=================================');
            
            return stock;
          }
        }
      }
      
      // 如果腾讯 API 失败，抛出异常
      throw Exception('腾讯API数据获取失败');
    } catch (e) {
      print('腾讯 API 请求失败: $e');
      
      // 尝试从缓存获取
      if (prefs != null) {
        final cacheKey = 'stock_cache_$code';
        final cachedData = prefs.getString(cacheKey);
        if (cachedData != null) {
          try {
            final stock = Stock.fromJson(jsonDecode(cachedData));
            print('使用缓存数据: $code');
            return stock;
          } catch (e) {
            print('缓存数据解析失败: $e');
          }
        }
      }
      
      // 返回空数据对象
      return Stock(
        code: code,
        name: code,
        currentPrice: 0,
        change: 0,
        changePercent: 0,
        historicalPrices: const [],
        historicalDates: const [],
        hasData: false,
      );
    }
  }
  
  // 获取历史数据
  Future<Map<String, List<dynamic>>> _getHistoricalData(String code, {String period = 'daily'}) async {
    try {
      // 使用腾讯财经API获取历史数据
      String tencentCode = code;
      if (code.endsWith('.SH')) {
        tencentCode = 'sh' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        tencentCode = 'sz' + code.replaceAll('.SZ', '');
      } else if (code.endsWith('.HK')) {
        tencentCode = 'hk' + code.replaceAll('.HK', '');
      }
      
      // 获取近30天数据
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 30));
      
      // 使用腾讯财经的日K线API
      final response = await _dio.get(
        'http://web.ifzq.gtimg.cn/appstock/finance/day/$tencentCode',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['data'] != null && data['data'][tencentCode] != null) {
          final dayData = data['data'][tencentCode]['day'] as List<dynamic>;
          
          // 解析日K线数据
          final prices = <double>[];
          final dates = <String>[];
          
          for (final day in dayData) {
            if (day is List && day.length >= 2) {
              final dateStr = day[0] as String;
              final closePrice = double.tryParse(day[2].toString()) ?? 0.0;
              
              prices.add(closePrice);
              dates.add(dateStr);
            }
          }
          
          // 如果获取到数据，返回
          if (prices.isNotEmpty) {
            return {
              'prices': prices,
              'dates': dates,
            };
          }
        }
      }
      
      // 如果腾讯API失败，返回模拟数据
      return _generateMockHistoricalData(code);
    } catch (e) {
      print('获取历史数据失败: $e');
      return _generateMockHistoricalData(code);
    }
  }
  
  // 生成模拟历史数据
  Map<String, List<dynamic>> _generateMockHistoricalData(String code) {
    final random = Random(code.hashCode);
    final prices = <double>[];
    final dates = <String>[];
    
    double basePrice = 10.0 + random.nextDouble() * 90.0;
    final now = DateTime.now();
    
    for (int i = 30; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final change = (random.nextDouble() - 0.5) * 0.1;
      basePrice = basePrice * (1 + change);
      
      prices.add(basePrice);
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }
    
    return {
      'prices': prices,
      'dates': dates,
    };
  }

  // 清理过期缓存
  Future<void> _cleanExpiredCache(SharedPreferences prefs) async {
    try {
      final keys = prefs.getKeys();
      final now = DateTime.now();
      
      for (final key in keys) {
        if (key.startsWith('stock_cache_')) {
          final cachedData = prefs.getString(key);
          if (cachedData != null) {
            try {
              final stock = Stock.fromJson(jsonDecode(cachedData));
              if (stock.cacheTimestamp != null) {
                final cacheTime = DateTime.parse(stock.cacheTimestamp!);
                if (now.difference(cacheTime) > const Duration(days: 365)) {
                  await prefs.remove(key);
                }
              }
            } catch (e) {
              print('清理缓存失败: $e');
            }
          }
        }
      }
    } catch (e) {
      print('清理缓存失败: $e');
    }
  }
}

// 主页
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TushareApi _tushareApi = TushareApi();
  late SharedPreferences _prefs;
  
  double _availableFunds = 500000.0;
  double _totalAssets = 500000.0;
  double _initialFunds = 500000.0;
  double _profitRate = 0.0;
  double _unlockedLimit = 500000.0;
  
  List<PortfolioItem> _portfolio = [];
  List<SellRecord> _sellRecords = [];
  List<Stock> _stocks = [];
  
  bool _isLoading = true;
  String _errorMessage = '';
  int _selectedIndustryIndex = 0;
  
  RefreshController _refreshController = RefreshController(initialRefresh: false);

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      // 加载资金数据
      _availableFunds = _prefs.getDouble('availableFunds') ?? 500000.0;
      _initialFunds = _prefs.getDouble('initialFunds') ?? 500000.0;
      _unlockedLimit = _prefs.getDouble('unlockedLimit') ?? 500000.0;
      
      // 确保额度不会低于初始额度 50 万
      if (_unlockedLimit < 500000.0) {
        _unlockedLimit = 500000.0;
        _prefs.setDouble('unlockedLimit', _unlockedLimit);
      }
      
      // 加载持仓数据
      final portfolioJson = _prefs.getString('portfolio');
      if (portfolioJson != null) {
        final portfolioList = jsonDecode(portfolioJson) as List<dynamic>;
        _portfolio = portfolioList.map((e) => PortfolioItem.fromJson(e)).toList();
      }
      
      // 加载卖出记录
      final sellRecordsJson = _prefs.getString('sellRecords');
      if (sellRecordsJson != null) {
        final sellRecordsList = jsonDecode(sellRecordsJson) as List<dynamic>;
        _sellRecords = sellRecordsList.map((e) => SellRecord.fromJson(e)).toList();
      }
      
      // 加载股票数据
      await _loadStocks();
      
      // 计算总资产
      _calculateTotalAssets();
      
      // 检查额度解锁
      _checkUnlockLimit();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '初始化失败: $e';
      });
    }
  }

  Future<void> _loadStocks() async {
    try {
      final stocks = <Stock>[];
      
      for (final industry in _tushareApi.industries) {
        for (final stockBasic in industry.stocks) {
          try {
            final stock = await _tushareApi.getStockData(stockBasic.code, prefs: _prefs);
            stocks.add(stock);
          } catch (e) {
            print('加载股票数据失败: ${stockBasic.code}, 错误: $e');
            // 添加一个空数据对象
            stocks.add(Stock(
              code: stockBasic.code,
              name: stockBasic.name,
              currentPrice: 0,
              change: 0,
              changePercent: 0,
              historicalPrices: const [],
              historicalDates: const [],
              hasData: false,
            ));
          }
        }
      }
      
      setState(() {
        _stocks = stocks;
      });
    } catch (e) {
      print('加载股票列表失败: $e');
    }
  }

  void _calculateTotalAssets() {
    double portfolioValue = 0.0;
    for (final item in _portfolio) {
      final stock = _stocks.firstWhere(
        (s) => s.code == item.stockCode,
        orElse: () => Stock(
          code: item.stockCode,
          name: '',
          currentPrice: 0,
          change: 0,
          changePercent: 0,
          historicalPrices: const [],
          historicalDates: const [],
        ),
      );
      portfolioValue += stock.currentPrice * item.quantity;
    }
    _totalAssets = _availableFunds + portfolioValue;
    _profitRate = (_totalAssets - _initialFunds) / _initialFunds * 100;
  }

  void _checkUnlockLimit() {
    double newLimit = 500000.0;
    if (_totalAssets >= 650000.0) {
      newLimit = 5000000.0;
    } else if (_totalAssets >= 600000.0) {
      newLimit = 2000000.0;
    } else if (_totalAssets >= 550000.0) {
      newLimit = 1000000.0;
    }

    // 确保额度不会低于初始额度 50 万
    if (newLimit < 500000.0) {
      newLimit = 500000.0;
    }

    if (newLimit > _unlockedLimit) {
      _unlockedLimit = newLimit;
      _prefs.setDouble('unlockedLimit', _unlockedLimit);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('额度升级成功！当前最高可使用${_formatFunds(newLimit)}元')),
        );
      }
    }
  }

  String _formatFunds(double funds) {
    if (funds >= 10000) {
      return '${(funds / 10000).toStringAsFixed(2)}万';
    } else {
      return funds.toStringAsFixed(2);
    }
  }

  Future<void> _buyStock(StockBasic stockBasic) async {
    try {
      final stock = await _tushareApi.getStockData(stockBasic.code, prefs: _prefs);
      
      if (!stock.hasData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无行情数据，无法交易')),
          );
        }
        return;
      }
      
      final TextEditingController quantityController = TextEditingController(text: '100');
      final maxBuyable = (_availableFunds / stock.currentPrice).floor() ~/ 100 * 100;
      
      final result = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('买入${stock.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('股票代码: ${stock.code}'),
              Text('当前价格: ${stock.currentPrice.toStringAsFixed(2)}元'),
              Text('可用资金: ${_formatFunds(_availableFunds)}'),
              Text('最大可买: $maxBuyable股'),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '买入数量（必须是100的整数倍）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final quantity = int.tryParse(quantityController.text) ?? 0;
                if (quantity <= 0 || quantity % 100 != 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('买入数量必须是100的整数倍')),
                  );
                  return;
                }
                Navigator.pop(context, quantity);
              },
              child: const Text('确认买入'),
            ),
          ],
        ),
      );

      if (result == null || result <= 0) return;
      
      final buyQuantity = result;
      final cost = stock.currentPrice * buyQuantity;

      if (_availableFunds < cost) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('资金不足')),
          );
        }
        return;
      }

      // 计算当前持仓市值（不包括可用资金）
      double currentPortfolioValue = 0.0;
      for (final item in _portfolio) {
        final stockData = _stocks.firstWhere(
          (s) => s.code == item.stockCode,
          orElse: () => Stock(
            code: item.stockCode,
            name: '',
            currentPrice: 0,
            change: 0,
            changePercent: 0,
            historicalPrices: const [],
            historicalDates: const [],
          ),
        );
        currentPortfolioValue += stockData.currentPrice * item.quantity;
      }
      
      // 检查持仓市值 + 新购买成本是否超过额度
      final newPortfolioValue = currentPortfolioValue + cost;
      if (newPortfolioValue > _unlockedLimit) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('超过额度限制，当前持仓已使用 ${_formatFunds(currentPortfolioValue)}，额度: ${_formatFunds(_unlockedLimit)}')),
          );
        }
        return;
      }

      final index = _portfolio.indexWhere((item) => item.stockCode == stock.code);
      if (index != -1) {
        final existing = _portfolio[index];
        final newQuantity = existing.quantity + buyQuantity;
        final newAveragePrice = (existing.averagePrice * existing.quantity + cost) / newQuantity;
        _portfolio[index] = PortfolioItem(
          stockCode: stock.code,
          quantity: newQuantity,
          averagePrice: newAveragePrice,
        );
      } else {
        _portfolio.add(PortfolioItem(
          stockCode: stock.code,
          quantity: buyQuantity,
          averagePrice: stock.currentPrice,
        ));
      }

      _availableFunds -= cost;

      await _prefs.setDouble('availableFunds', _availableFunds);
      await _prefs.setString('portfolio', jsonEncode(_portfolio));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功买入${stock.name}${buyQuantity}股，花费${_formatFunds(cost)}元')),
        );
      }

      _calculateTotalAssets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络连接失败，无法执行交易')),
        );
      }
    }
  }

  Future<void> _sellStock(StockBasic stockBasic) async {
    try {
      final stock = await _tushareApi.getStockData(stockBasic.code, prefs: _prefs);
      
      if (!stock.hasData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无行情数据，无法交易')),
          );
        }
        return;
      }
      
      final index = _portfolio.indexWhere((item) => item.stockCode == stock.code);
      if (index == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未持有该股票')),
          );
        }
        return;
      }

      final portfolioItem = _portfolio[index];
      final maxQuantity = portfolioItem.quantity;

      final TextEditingController quantityController = TextEditingController(text: maxQuantity.toString());

      final result = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('卖出${stock.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('持有数量: $maxQuantity股'),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '卖出数量',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final quantity = int.tryParse(quantityController.text) ?? 0;
                if (quantity <= 0 || quantity > maxQuantity) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('卖出数量无效')),
                  );
                  return;
                }
                Navigator.pop(context, quantity);
              },
              child: const Text('确认卖出'),
            ),
          ],
        ),
      );

      if (result == null || result <= 0) return;

      final sellQuantity = result;
      final revenue = stock.currentPrice * sellQuantity;

      if (portfolioItem.quantity == sellQuantity) {
        _portfolio.removeAt(index);
      } else {
        _portfolio[index] = PortfolioItem(
          stockCode: stock.code,
          quantity: portfolioItem.quantity - sellQuantity,
          averagePrice: portfolioItem.averagePrice,
        );
      }

      _availableFunds += revenue;

      _sellRecords.add(SellRecord(
        stockCode: stock.code,
        stockName: stock.name,
        quantity: sellQuantity,
        price: stock.currentPrice,
        amount: revenue,
        time: DateTime.now(),
      ));

      await _prefs.setDouble('availableFunds', _availableFunds);
      await _prefs.setString('portfolio', jsonEncode(_portfolio));
      await _prefs.setString('sellRecords', jsonEncode(_sellRecords));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功卖出${stock.name}${sellQuantity}股，收入${_formatFunds(revenue)}元')),
        );
      }

      _calculateTotalAssets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络连接失败，无法执行交易')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tushareApi.industries.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('模拟炒股'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showSearch(
                  context: context,
                  delegate: StockSearchDelegate(_tushareApi.allStocks, _buyStock),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SellRecordsPage(sellRecords: _sellRecords),
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: '持仓'),
              ..._tushareApi.industries.map((industry) => Tab(text: industry.name)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _initializeData,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _buildFundsPanel(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildPortfolioTab(),
                            ..._tushareApi.industries.map((industry) => _buildIndustryTab(industry)),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildFundsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFundItem('总资产', _totalAssets),
              _buildFundItem('可用资金', _availableFunds),
              _buildFundItem('持仓盈亏', _totalAssets - _initialFunds),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '收益率: ${_profitRate.toStringAsFixed(2)}% | 已解锁额度: ${_formatFunds(_unlockedLimit)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFundItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          _formatFunds(value),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildPortfolioTab() {
    return SmartRefresher(
      controller: _refreshController,
      onRefresh: () async {
        await _loadStocks();
        _calculateTotalAssets();
        _refreshController.refreshCompleted();
      },
      child: _portfolio.isEmpty
          ? const Center(child: Text('暂无持仓，点击右上角搜索股票'))
          : ListView.builder(
              itemCount: _portfolio.length,
              itemBuilder: (context, index) {
                final item = _portfolio[index];
                final stock = _stocks.firstWhere(
                  (s) => s.code == item.stockCode,
                  orElse: () => Stock(
                    code: item.stockCode,
                    name: item.stockCode,
                    currentPrice: 0,
                    change: 0,
                    changePercent: 0,
                    historicalPrices: const [],
                    historicalDates: const [],
                  ),
                );
                
                final currentValue = stock.currentPrice * item.quantity;
                final cost = item.averagePrice * item.quantity;
                final profit = currentValue - cost;
                final profitRate = cost != 0 ? (profit / cost) * 100 : 0.0;
                
                return ListTile(
                  title: Text(stock.name),
                  subtitle: Text('${stock.code} | 持仓: ${item.quantity}股 | 成本: ${item.averagePrice.toStringAsFixed(2)}元'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${stock.currentPrice.toStringAsFixed(2)}元'),
                      Text(
                        '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)}元 (${profitRate.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          color: profit >= 0 ? Colors.red : Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: Text('${stock.name} (${stock.code})'),
                            subtitle: Text('当前价格: ${stock.currentPrice.toStringAsFixed(2)}元'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.show_chart),
                            title: const Text('查看详情'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StockDetailPage(stock: stock),
                                ),
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.sell),
                            title: const Text('卖出'),
                            onTap: () {
                              Navigator.pop(context);
                              _sellStock(StockBasic(
                                code: stock.code,
                                name: stock.name,
                                industry: '',
                              ));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildIndustryTab(Industry industry) {
    final industryStocks = _stocks.where((stock) {
      return industry.stocks.any((basic) => basic.code == stock.code);
    }).toList();

    return ListView.builder(
      itemCount: industryStocks.length,
      itemBuilder: (context, index) {
        final stock = industryStocks[index];
        final isInPortfolio = _portfolio.any((item) => item.stockCode == stock.code);
        
        return ListTile(
          title: Text(stock.name),
          subtitle: Text('${stock.code} | ${stock.industry}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${stock.currentPrice.toStringAsFixed(2)}元'),
              Text(
                '${stock.change >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: stock.changePercent >= 0 ? Colors.red : Colors.green,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          onTap: () {
            showModalBottomSheet(
              context: context,
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text('${stock.name} (${stock.code})'),
                    subtitle: Text('当前价格: ${stock.currentPrice.toStringAsFixed(2)}元'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.show_chart),
                    title: const Text('查看详情'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StockDetailPage(stock: stock),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_shopping_cart),
                    title: const Text('买入'),
                    onTap: () {
                      Navigator.pop(context);
                      _buyStock(StockBasic(
                        code: stock.code,
                        name: stock.name,
                        industry: industry.name,
                      ));
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// 股票详情页面
class StockDetailPage extends StatefulWidget {
  final Stock stock;

  const StockDetailPage({super.key, required this.stock});

  @override
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  String _period = 'daily';
  bool _isLoading = false;
  String _errorMessage = '';
  late Stock _stock;
  final TushareApi _api = TushareApi();

  @override
  void initState() {
    super.initState();
    _stock = widget.stock;
    _loadStockData();
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final stock = await _api.getStockData(widget.stock.code, period: _period);
      setState(() {
        _stock = stock;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载数据失败: $e';
      });
    }
  }

  void _changePeriod(String period) {
    setState(() {
      _period = period;
    });
    _loadStockData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stock.name} (${widget.stock.code})'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _changePeriod(_period),
                        child: const Text('点击重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 顶部信息栏
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.blue[50],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.stock.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.stock.code,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${widget.stock.currentPrice.toStringAsFixed(2)}元',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: widget.stock.changePercent >= 0 ? Colors.red : Colors.green,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${widget.stock.changePercent >= 0 ? '+' : ''}${widget.stock.changePercent.toStringAsFixed(2)}%',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // 周期选择器
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('日线'),
                            selected: _period == 'daily',
                            onSelected: (selected) {
                              if (selected) _changePeriod('daily');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('周线'),
                            selected: _period == 'weekly',
                            onSelected: (selected) {
                              if (selected) _changePeriod('weekly');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('月线'),
                            selected: _period == 'monthly',
                            onSelected: (selected) {
                              if (selected) _changePeriod('monthly');
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // 股票信息
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '基本信息',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow('股票代码', widget.stock.code),
                            _buildInfoRow('股票名称', widget.stock.name),
                            _buildInfoRow('当前价格', '${widget.stock.currentPrice.toStringAsFixed(2)}元'),
                            _buildInfoRow('涨跌额', '${widget.stock.change >= 0 ? '+' : ''}${widget.stock.change.toStringAsFixed(2)}元'),
                            _buildInfoRow('涨跌幅', '${widget.stock.changePercent >= 0 ? '+' : ''}${widget.stock.changePercent.toStringAsFixed(2)}%'),
                            const SizedBox(height: 24),
                            Text(
                              '历史价格走势',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: widget.stock.historicalPrices.isEmpty
                                  ? const Center(child: Text('暂无历史数据'))
                                  : ListView.builder(
                                      itemCount: widget.stock.historicalDates.length,
                                      itemBuilder: (context, index) {
                                        return ListTile(
                                          dense: true,
                                          title: Text(widget.stock.historicalDates[index]),
                                          trailing: Text('${widget.stock.historicalPrices[index].toStringAsFixed(2)}元'),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// 股票搜索代理
class StockSearchDelegate extends SearchDelegate<StockBasic> {
  final List<StockBasic> stocks;
  final Function(StockBasic) onStockSelected;
  final TushareApi api = TushareApi();

  StockSearchDelegate(this.stocks, this.onStockSelected);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, StockBasic(code: '', name: '', industry: ''));
      },
    );
  }

  Future<StockBasic?> _searchStockByCode(String code) async {
    try {
      final stock = await api.getStockData(code);
      if (stock.hasData) {
        return StockBasic(
          code: stock.code,
          name: stock.name,
          industry: '自定义',
        );
      }
    } catch (e) {
      print('搜索股票失败: $e');
    }
    return null;
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<StockBasic>>(
      future: _searchStocks(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('搜索失败: ${snapshot.error}'));
        }

        final results = snapshot.data ?? [];
        final uniqueResults = _removeDuplicates(results);

        if (uniqueResults.isEmpty) {
          return const Center(child: Text('未找到相关股票'));
        }

        return ListView.builder(
          itemCount: uniqueResults.length,
          itemBuilder: (context, index) {
            final stock = uniqueResults[index];
            return ListTile(
              title: Text(stock.name),
              subtitle: Text('${stock.code} - ${stock.industry}'),
              onTap: () {
                onStockSelected(stock);
                close(context, stock);
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return FutureBuilder<List<StockBasic>>(
      future: _searchStocks(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && query.isNotEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('搜索失败: ${snapshot.error}'));
        }

        final results = snapshot.data ?? [];
        final uniqueResults = _removeDuplicates(results);

        if (uniqueResults.isEmpty && query.isNotEmpty) {
          return const Center(child: Text('未找到相关股票，请输入正确的股票代码（如：600036.SH）'));
        }

        return ListView.builder(
          itemCount: uniqueResults.length,
          itemBuilder: (context, index) {
            final stock = uniqueResults[index];
            return ListTile(
              title: Text(stock.name),
              subtitle: Text('${stock.code} - ${stock.industry}'),
              onTap: () {
                onStockSelected(stock);
                close(context, stock);
              },
            );
          },
        );
      },
    );
  }

  Future<List<StockBasic>> _searchStocks(String query) async {
    if (query.isEmpty) return [];

    final results = <StockBasic>[];

    // 1. 首先从本地列表中搜索匹配的股票（支持中文名称搜索）
    final localResults = stocks.where((stock) {
      return stock.name.contains(query) || stock.code.contains(query);
    }).toList();
    results.addAll(localResults);

    // 2. 如果查询是股票代码（长度>=6），从API获取详细信息
    if (query.length >= 6) {
      final stock = await _searchStockByCode(query);
      if (stock != null) {
        // 检查是否已在本地结果中
        if (!results.any((s) => s.code == stock.code)) {
          results.add(stock);
        }
      }
    }

    return results;
  }

  List<StockBasic> _removeDuplicates(List<StockBasic> stocks) {
    final seen = <String>{};
    final unique = <StockBasic>[];
    for (final stock in stocks) {
      if (!seen.contains(stock.code)) {
        seen.add(stock.code);
        unique.add(stock);
      }
    }
    return unique;
  }
}

// 卖出记录页面
class SellRecordsPage extends StatelessWidget {
  final List<SellRecord> sellRecords;

  const SellRecordsPage({super.key, required this.sellRecords});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('卖出记录'),
      ),
      body: sellRecords.isEmpty
          ? const Center(child: Text('暂无卖出记录'))
          : ListView.builder(
              itemCount: sellRecords.length,
              itemBuilder: (context, index) {
                final record = sellRecords[index];
                return ListTile(
                  title: Text(record.stockName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('卖出数量: ${record.quantity}股'),
                      Text('卖出价格: ${record.price.toStringAsFixed(2)}元'),
                      Text('到账金额: ${record.amount.toStringAsFixed(2)}元'),
                      Text(
                        '时间: ${DateFormat('yyyy-MM-dd HH:mm').format(record.time)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  trailing: Text(
                    '${record.amount.toStringAsFixed(2)}元',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '模拟炒股',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}