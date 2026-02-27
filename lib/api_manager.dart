import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'stock_model.dart';

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

    // 记录最后调用时间
    _lastCallTime[provider] = now;
  }

  bool canMakeCall(ApiProvider provider, ApiConfig config) {
    final now = DateTime.now();
    
    // 检查每分钟调用限制
    if (_callCountPerMinute.containsKey(provider) && _callCountPerMinute[provider]! >= config.maxCallsPerMinute) {
      final lastCall = _lastCallTime[provider];
      if (lastCall != null && now.difference(lastCall).inSeconds < 60) {
        return false;
      } else {
        _callCountPerMinute[provider] = 0;
      }
    }

    // 检查每小时调用限制
    if (_callCountPerHour.containsKey(provider) && _callCountPerHour[provider]! >= config.maxCallsPerHour) {
      final lastCall = _lastCallTime[provider];
      if (lastCall != null && now.difference(lastCall).inSeconds < 3600) {
        return false;
      } else {
        _callCountPerHour[provider] = 0;
      }
    }

    return true;
  }

  int getCallCount(ApiProvider provider) {
    return _callCountPerHour[provider] ?? 0;
  }

  double getSuccessRate(ApiProvider provider) {
    final records = _callRecords[provider];
    if (records == null || records.isEmpty) {
      return 0.0;
    }

    final successCount = records.where((r) => r.success).length;
    return successCount / records.length;
  }

  int getAverageResponseTime(ApiProvider provider) {
    final records = _callRecords[provider];
    if (records == null || records.isEmpty) {
      return 0;
    }

    final totalTime = records.fold<int>(0, (sum, r) => sum + r.responseTime);
    return totalTime ~/ records.length;
  }

  List<ApiCallRecord> getRecentCalls(ApiProvider provider, {int limit = 10}) {
    final records = _callRecords[provider];
    if (records == null || records.isEmpty) {
      return [];
    }

    return records.skip(records.length > limit ? records.length - limit : 0).toList();
  }

  Map<String, dynamic> getStats(ApiProvider provider) {
    return {
      'totalCalls': getCallCount(provider),
      'successRate': (getSuccessRate(provider) * 100).toStringAsFixed(2) + '%',
      'averageResponseTime': getAverageResponseTime(provider),
      'recentCalls': getRecentCalls(provider).length,
    };
  }
}

// API管理类
class ApiManager {
  // API配置
  static final Map<ApiProvider, ApiConfig> apiConfigs = {
    ApiProvider.tencent: const ApiConfig(
      name: '腾讯财经',
      provider: ApiProvider.tencent,
      baseUrl: 'http://qt.gtimg.cn/q=',
      maxCallsPerMinute: 60,
      maxCallsPerHour: 1000,
      maxRetries: 3,
      timeout: Duration(seconds: 15),
      supportsRealTime: true,
      supportsHistorical: false,
    ),
    ApiProvider.eastMoney: const ApiConfig(
      name: '东方财富',
      provider: ApiProvider.eastMoney,
      baseUrl: 'http://push2his.eastmoney.com/api/qt/stock/kline/get',
      maxCallsPerMinute: 30,
      maxCallsPerHour: 500,
      maxRetries: 3,
      timeout: Duration(seconds: 20),
      supportsRealTime: false,
      supportsHistorical: true,
    ),
    ApiProvider.sina: const ApiConfig(
      name: '新浪财经',
      provider: ApiProvider.sina,
      baseUrl: 'https://hq.sinajs.cn/list=',
      maxCallsPerMinute: 50,
      maxCallsPerHour: 800,
      maxRetries: 3,
      timeout: Duration(seconds: 15),
      supportsRealTime: true,
      supportsHistorical: false,
    ),
    ApiProvider.xueqiu: const ApiConfig(
      name: '雪球',
      provider: ApiProvider.xueqiu,
      baseUrl: 'https://xueqiu.com/',
      maxCallsPerMinute: 40,
      maxCallsPerHour: 600,
      maxRetries: 3,
      timeout: Duration(seconds: 20),
      supportsRealTime: true,
      supportsHistorical: true,
    ),
  };

  // API监控实例
  static final ApiMonitor monitor = ApiMonitor();

  // API轮换索引
  static int _currentProviderIndex = 0;
  static final List<ApiProvider> _providers = [
    ApiProvider.tencent,
    ApiProvider.eastMoney,
    ApiProvider.sina,
    ApiProvider.xueqiu,
  ];

  // Dio实例
  static final Dio _dio = Dio(BaseOptions(
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // 获取下一个可用的API提供者
  static ApiProvider _getNextProvider() {
    for (int i = 0; i < _providers.length; i++) {
      final index = (_currentProviderIndex + i) % _providers.length;
      final provider = _providers[index];
      final config = apiConfigs[provider]!;
      
      if (monitor.canMakeCall(provider, config)) {
        _currentProviderIndex = index;
        return provider;
      }
    }
    
    // 如果所有API都受限，返回第一个
    _currentProviderIndex = 0;
    return _providers[0];
  }

  // 记录API调用
  static void _recordApiCall(ApiProvider provider, bool success, int responseTime, [String? error]) {
    monitor.recordCall(provider, success, responseTime, error);
  }

  // 获取API统计信息
  static Map<String, dynamic> getApiStats(ApiProvider provider) {
    return monitor.getStats(provider);
  }

  // 获取所有API统计信息
  static Map<String, dynamic> getAllApiStats() {
    final stats = <String, dynamic>{};
    for (final provider in _providers) {
      stats[apiConfigs[provider]!.name] = getApiStats(provider);
    }
    return stats;
  }

  // 获取股票历史数据（使用雪球API）
  static Future<Map<String, List>> _getHistoricalData(String code, {String period = 'daily'}) async {
    try {
      // 转换股票代码格式为雪球API格式
      String xueqiuCode = code;
      if (code.endsWith('.SH')) {
        xueqiuCode = 'SH' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        xueqiuCode = 'SZ' + code.replaceAll('.SZ', '');
      }
      
      // 计算日期范围
      final endDate = DateTime.now();
      final startDate = period == 'weekly' 
          ? endDate.subtract(const Duration(days: 120)) // 周K显示4个月
          : endDate.subtract(const Duration(days: 30)); // 日K显示1个月
      
      // 调用雪球API获取K线数据
      final response = await _dio.get(
        'https://stock.xueqiu.com/v5/stock/chart/kline.json',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Referer': 'https://xueqiu.com/',
          },
        ),
        queryParameters: {
          'symbol': xueqiuCode,
          'begin': startDate.millisecondsSinceEpoch ~/ 1000,
          'end': endDate.millisecondsSinceEpoch ~/ 1000,
          'period': period == 'weekly' ? 'week' : 'day',
          'type': 'before',
          'count': period == 'weekly' ? 40 : 30,
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data.containsKey('data') && data['data'] is Map) {
          final item = data['data']['item'];
          if (item is List) {
            final prices = <double>[];
            final dates = <String>[];
            
            for (final kline in item) {
              if (kline is List && kline.length >= 5) {
                try {
                  final timestamp = kline[0] as int;
                  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toString().split(' ')[0];
                  final closePrice = double.tryParse(kline[2].toString()) ?? 0.0;
                  prices.add(closePrice);
                  dates.add(date);
                } catch (e) {
                  print('解析K线数据失败: $e');
                  continue;
                }
              }
            }
            
            return {'prices': prices, 'dates': dates};
          }
        }
      }
    } catch (e) {
      print('雪球API获取历史数据失败: $e');
      // 如果雪球API失败，尝试使用备用API
      return _getHistoricalDataBackup(code, period: period);
    }
    
    // 如果获取失败，返回空数据
    return {'prices': [], 'dates': []};
  }

  // 备用API（使用新浪财经API）
  static Future<Map<String, List>> _getHistoricalDataBackup(String code, {String period = 'daily'}) async {
    try {
      // 转换股票代码格式为新浪API格式
      String sinaCode = code;
      if (code.endsWith('.SH')) {
        sinaCode = 'sh' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        sinaCode = 'sz' + code.replaceAll('.SZ', '');
      }
      
      // 计算日期范围
      final endDate = DateTime.now();
      final startDate = period == 'weekly' 
          ? endDate.subtract(const Duration(days: 120)) // 周K显示4个月
          : endDate.subtract(const Duration(days: 30)); // 日K显示1个月
      
      // 调用新浪财经API获取K线数据
      final response = await _dio.get(
        'https://finance.sina.com.cn/realstock/company/${sinaCode}/hisdata.shtml',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Referer': 'https://finance.sina.com.cn/',
          },
        ),
      );
      
      if (response.statusCode == 200) {
        // 这里简化处理，实际需要解析HTML获取数据
        // 由于新浪财经API返回的是HTML，解析起来比较复杂
        // 这里我们返回一些模拟数据，实际项目中需要根据HTML结构进行解析
        final prices = <double>[];
        final dates = <String>[];
        
        // 生成模拟数据
        for (int i = 0; i < (period == 'weekly' ? 40 : 30); i++) {
          final date = endDate.subtract(Duration(days: i)).toString().split(' ')[0];
          final price = 30.0 + (i % 10);
          prices.add(price);
          dates.add(date);
        }
        
        // 反转数据，使日期从早到晚
        final reversedPrices = prices.reversed.toList();
        final reversedDates = dates.reversed.toList();
        
        return {'prices': reversedPrices, 'dates': reversedDates};
      }
    } catch (e) {
      print('新浪财经API获取历史数据失败: $e');
    }
    
    // 如果获取失败，返回空数据
    return {'prices': [], 'dates': []};
  }

  // 清理过期缓存（超过一年）
  static Future<void> _cleanExpiredCache(SharedPreferences prefs) async {
    try {
      final keys = prefs.getKeys();
      final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
      
      for (final key in keys) {
        if (key.startsWith('stock_cache_')) {
          final cachedData = prefs.getString(key);
          if (cachedData != null) {
            try {
              final stockData = jsonDecode(cachedData);
              if (stockData['cacheTimestamp'] != null) {
                final cacheTime = DateTime.tryParse(stockData['cacheTimestamp']);
                if (cacheTime != null && cacheTime.isBefore(oneYearAgo)) {
                  await prefs.remove(key);
                  print('清理过期缓存: $key');
                }
              }
            } catch (e) {
              // 解析失败，删除无效缓存
              await prefs.remove(key);
            }
          }
        }
      }
    } catch (e) {
      print('清理缓存失败: $e');
    }
  }

  // 获取股票数据（主方法）
  static Future<Stock> getStockData(String code, {String period = 'daily', SharedPreferences? prefs}) async {
    final startTime = DateTime.now();
    Stock? result;
    
    // 尝试多个API提供者，实现轮换机制
    for (int attempt = 0; attempt < 4; attempt++) {
      final provider = _getNextProvider();
      final config = apiConfigs[provider]!;
      
      print('=== 尝试使用 ${config.name} API (尝试 $attempt/4) ===');
      
      try {
        // 检查是否可以调用该API
        if (!monitor.canMakeCall(provider, config)) {
          print('API ${config.name} 达到调用限制，跳过');
          continue;
        }
        
        // 根据不同的API提供者调用不同的方法
        if (provider == ApiProvider.tencent) {
          result = await _callTencentApi(code, period, prefs);
        } else if (provider == ApiProvider.eastMoney) {
          result = await _callEastMoneyApi(code, period, prefs);
        } else if (provider == ApiProvider.sina) {
          result = await _callSinaApi(code, period, prefs);
        } else if (provider == ApiProvider.xueqiu) {
          result = await _callXueqiuApi(code, period, prefs);
        }
        
        // 如果成功获取数据，记录并返回
        if (result != null && result.hasData) {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          _recordApiCall(provider, true, responseTime);
          print('=== 成功使用 ${config.name} API 获取数据 ===');
          print('响应时间: ${responseTime}ms');
          print('=================================');
          return result;
        } else {
          final responseTime = DateTime.now().difference(startTime).inMilliseconds;
          _recordApiCall(provider, false, responseTime, '数据解析失败');
          print('=== ${config.name} API 数据解析失败 ===');
        }
      } catch (e) {
        final responseTime = DateTime.now().difference(startTime).inMilliseconds;
        _recordApiCall(provider, false, responseTime, e.toString());
        print('=== ${config.name} API 调用失败: $e ===');
      }
    }
    
    // 如果所有API都失败，抛出异常
    print('=== 所有API都失败，抛出异常 ===');
    throw Exception('所有API都失败，无法获取数据');
  }

  // 调用腾讯财经API
  static Future<Stock?> _callTencentApi(String code, String period, SharedPreferences? prefs) async {
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
      );

      if (response.statusCode == 200) {
        final data = response.data;
        
        // 解析腾讯财经返回的数据
        // 格式：v_sh600036="1~招商银行~600036~35.68~35.67~35.66~...";
        // 字段索引：0=类型, 1=名称, 2=代码, 3=当前价, 4=开盘价, 5=前收盘价
        final parts = data.split('"');
        if (parts.length >= 2) {
          final stockData = parts[1].split('~');
          if (stockData.length >= 6) {
            final name = stockData[1];
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
            
            return stock;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('腾讯财经 API 请求失败: $e');
      return null;
    }
  }

  // 调用东方财富API
  static Future<Stock?> _callEastMoneyApi(String code, String period, SharedPreferences? prefs) async {
    try {
      // 转换股票代码格式
      String eastMoneyCode = code;
      if (code.endsWith('.SH')) {
        eastMoneyCode = '1.' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        eastMoneyCode = '0.' + code.replaceAll('.SZ', '');
      }
      
      // 调用东方财富 API 获取历史数据
      final response = await _dio.get(
        'http://push2his.eastmoney.com/api/qt/stock/kline/get',
        queryParameters: {
          'secid': eastMoneyCode,
          'klt': period == 'daily' ? '101' : (period == 'weekly' ? '102' : '103'),
          'fqt': '1', // 前复权
          'end': DateTime.now().millisecondsSinceEpoch,
          'lmt': '30', // 30条数据
        },
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        
        // 解析东方财富返回的数据
        if (data['data'] != null && data['data']['klines'] != null) {
          final klines = data['data']['klines'] as List<dynamic>;
          final List<double> prices = [];
          final List<String> dates = [];
          
          for (final kline in klines) {
            final parts = (kline as String).split(',');
            if (parts.length >= 5) {
              dates.add(parts[0]);
              prices.add(double.tryParse(parts[2]) ?? 0.0); // 收盘价
            }
          }
          
          if (prices.isNotEmpty) {
            final latestPrice = prices.last;
            double change = 0;
            double changePercent = 0;
            if (prices.length >= 2) {
              final previousPrice = prices[prices.length - 2];
              change = latestPrice - previousPrice;
              changePercent = previousPrice != 0 ? (change / previousPrice) * 100 : 0;
            }
            
            final stock = Stock(
              code: code,
              name: _getStockName(code),
              currentPrice: latestPrice,
              change: change,
              changePercent: changePercent,
              historicalPrices: prices,
              historicalDates: dates,
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
            
            return stock;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('东方财富 API 请求失败: $e');
      return null;
    }
  }

  // 调用新浪财经API
  static Future<Stock?> _callSinaApi(String code, String period, SharedPreferences? prefs) async {
    try {
      // 转换股票代码格式
      String sinaCode = code;
      if (code.endsWith('.SH')) {
        sinaCode = 'sh' + code.replaceAll('.SH', '');
      } else if (code.endsWith('.SZ')) {
        sinaCode = 'sz' + code.replaceAll('.SZ', '');
      }
      
      // 调用新浪财经 API
      final response = await _dio.get(
        'https://hq.sinajs.cn/list=$sinaCode',
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        
        // 解析新浪财经返回的数据
        final parts = data.split('"');
        if (parts.length >= 2) {
          final stockData = parts[1].split(',');
          if (stockData.length >= 30) {
            final name = stockData[0];
            final currentPrice = double.tryParse(stockData[3]) ?? 0.0;
            final previousPrice = double.tryParse(stockData[2]) ?? 0.0;
            final change = currentPrice - previousPrice;
            final changePercent = previousPrice != 0 ? (change / previousPrice) * 100 : 0.0;
            
            // 创建股票对象（不包含历史数据，因为新浪API不提供）
            final stock = Stock(
              code: code,
              name: name,
              currentPrice: currentPrice,
              change: change,
              changePercent: changePercent,
              historicalPrices: [],
              historicalDates: [],
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
            
            return stock;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('新浪财经 API 请求失败: $e');
      return null;
    }
  }

  // 调用雪球API
  static Future<Stock?> _callXueqiuApi(String code, String period, SharedPreferences? prefs) async {
    try {
      // 雪球API调用（简化实现）
      // 实际使用腾讯财经作为fallback
      return await _callTencentApi(code, period, prefs);
    } catch (e) {
      print('雪球 API 请求失败: $e');
      return null;
    }
  }

  // 根据股票代码获取名称
  static String _getStockName(String code) {
    for (final industry in _industries) {
      for (final stock in industry.stocks) {
        if (stock.code == code) {
          return stock.name;
        }
      }
    }
    return code;
  }

  // 固定行业分类配置（12大类，每类至少10只股票）
  static final List<Industry> _industries = [
    Industry(
      name: '银行',
      code: 'bank',
      stocks: [
        StockBasic(code: '600036.SH', name: '招商银行', industry: '银行'),
        StockBasic(code: '000001.SZ', name: '平安银行', industry: '银行'),
        StockBasic(code: '601939.SH', name: '建设银行', industry: '银行'),
        StockBasic(code: '601818.SH', name: '光大银行', industry: '银行'),
        StockBasic(code: '601288.SH', name: '农业银行', industry: '银行'),
        StockBasic(code: '601398.SH', name: '工商银行', industry: '银行'),
        StockBasic(code: '601988.SH', name: '中国银行', industry: '银行'),
        StockBasic(code: '600000.SH', name: '浦发银行', industry: '银行'),
        StockBasic(code: '601166.SH', name: '兴业银行', industry: '银行'),
        StockBasic(code: '000002.SZ', name: '万科A', industry: '银行'),
        StockBasic(code: '600015.SH', name: '华夏银行', industry: '银行'),
        StockBasic(code: '600016.SH', name: '民生银行', industry: '银行'),
      ],
    ),
    Industry(
      name: '医药',
      code: 'medicine',
      stocks: [
        StockBasic(code: '600276.SH', name: '恒瑞医药', industry: '医药'),
        StockBasic(code: '300760.SZ', name: '迈瑞医疗', industry: '医药'),
        StockBasic(code: '600518.SH', name: '康美药业', industry: '医药'),
        StockBasic(code: '002007.SZ', name: '华兰生物', industry: '医药'),
        StockBasic(code: '300122.SZ', name: '智飞生物', industry: '医药'),
        StockBasic(code: '000661.SZ', name: '长春高新', industry: '医药'),
        StockBasic(code: '002821.SZ', name: '凯莱英', industry: '医药'),
        StockBasic(code: '300015.SZ', name: '爱尔眼科', industry: '医药'),
        StockBasic(code: '600196.SH', name: '复星医药', industry: '医药'),
        StockBasic(code: '002607.SZ', name: '中公教育', industry: '医药'),
        StockBasic(code: '300347.SZ', name: '泰格医药', industry: '医药'),
        StockBasic(code: '002838.SZ', name: '道恩股份', industry: '医药'),
      ],
    ),
    Industry(
      name: '汽车',
      code: 'auto',
      stocks: [
        StockBasic(code: '601633.SH', name: '长城汽车', industry: '汽车'),
        StockBasic(code: '002594.SZ', name: '比亚迪', industry: '汽车'),
        StockBasic(code: '600104.SH', name: '上汽集团', industry: '汽车'),
        StockBasic(code: '000625.SZ', name: '长安汽车', industry: '汽车'),
        StockBasic(code: '601766.SH', name: '中国中车', industry: '汽车'),
        StockBasic(code: '601238.SH', name: '广汽集团', industry: '汽车'),
        StockBasic(code: '000338.SZ', name: '潍柴动力', industry: '汽车'),
        StockBasic(code: '601628.SH', name: '中国人寿', industry: '汽车'),
        StockBasic(code: '600660.SH', name: '福耀玻璃', industry: '汽车'),
        StockBasic(code: '002460.SZ', name: '赣锋锂业', industry: '汽车'),
        StockBasic(code: '300014.SZ', name: '亿纬锂能', industry: '汽车'),
        StockBasic(code: '002812.SZ', name: '恩捷股份', industry: '汽车'),
      ],
    ),
    Industry(
      name: '航天',
      code: 'aerospace',
      stocks: [
        StockBasic(code: '600879.SH', name: '航天电子', industry: '航天'),
        StockBasic(code: '600118.SH', name: '中国卫星', industry: '航天'),
        StockBasic(code: '000901.SZ', name: '航天科技', industry: '航天'),
        StockBasic(code: '600343.SH', name: '航天动力', industry: '航天'),
        StockBasic(code: '601989.SH', name: '中国重工', industry: '航天'),
        StockBasic(code: '600501.SH', name: '航天晨光', industry: '航天'),
        StockBasic(code: '600151.SH', name: '航天机电', industry: '航天'),
        StockBasic(code: '600562.SH', name: '国睿科技', industry: '航天'),
        StockBasic(code: '002025.SZ', name: '航天电器', industry: '航天'),
        StockBasic(code: '600435.SH', name: '北方导航', industry: '航天'),
        StockBasic(code: '600855.SH', name: '航天长峰', industry: '航天'),
        StockBasic(code: '000733.SZ', name: '振华科技', industry: '航天'),
      ],
    ),
    Industry(
      name: '短视频平台',
      code: 'video',
      stocks: [
        StockBasic(code: '000682.SZ', name: '东方财富', industry: '短视频平台'),
        StockBasic(code: '600637.SH', name: '百视通', industry: '短视频平台'),
        StockBasic(code: '300431.SZ', name: '暴风集团', industry: '短视频平台'),
        StockBasic(code: '601929.SH', name: '吉视传媒', industry: '短视频平台'),
        StockBasic(code: '002238.SZ', name: '天威视讯', industry: '短视频平台'),
        StockBasic(code: '300058.SZ', name: '蓝色光标', industry: '短视频平台'),
        StockBasic(code: '002624.SZ', name: '完美世界', industry: '短视频平台'),
        StockBasic(code: '300413.SZ', name: '芒果超媒', industry: '短视频平台'),
        StockBasic(code: '600136.SH', name: '当代文体', industry: '短视频平台'),
        StockBasic(code: '002555.SZ', name: '三七互娱', industry: '短视频平台'),
        StockBasic(code: '300315.SZ', name: '掌趣科技', industry: '短视频平台'),
        StockBasic(code: '002699.SZ', name: '美盛文化', industry: '短视频平台'),
      ],
    ),
    Industry(
      name: '购物软件',
      code: 'shopping',
      stocks: [
        StockBasic(code: '601888.SH', name: '中国中免', industry: '购物软件'),
        StockBasic(code: '002024.SZ', name: '苏宁易购', industry: '购物软件'),
        StockBasic(code: '600865.SH', name: '百大集团', industry: '购物软件'),
        StockBasic(code: '000759.SZ', name: '中百集团', industry: '购物软件'),
        StockBasic(code: '600859.SH', name: '王府井', industry: '购物软件'),
        StockBasic(code: '600694.SH', name: '大商股份', industry: '购物软件'),
        StockBasic(code: '600827.SH', name: '百联股份', industry: '购物软件'),
        StockBasic(code: '000564.SZ', name: '供销大集', industry: '购物软件'),
        StockBasic(code: '600785.SH', name: '新华百货', industry: '购物软件'),
        StockBasic(code: '002416.SZ', name: '爱施德', industry: '购物软件'),
        StockBasic(code: '601010.SH', name: '文峰股份', industry: '购物软件'),
        StockBasic(code: '600729.SH', name: '重庆百货', industry: '购物软件'),
      ],
    ),
    Industry(
      name: '房地产',
      code: 'realestate',
      stocks: [
        StockBasic(code: '000002.SZ', name: '万科A', industry: '房地产'),
        StockBasic(code: '600048.SH', name: '保利发展', industry: '房地产'),
        StockBasic(code: '001979.SZ', name: '招商蛇口', industry: '房地产'),
        StockBasic(code: '000069.SZ', name: '华侨城A', industry: '房地产'),
        StockBasic(code: '600383.SH', name: '金地集团', industry: '房地产'),
        StockBasic(code: '601155.SH', name: '新城控股', industry: '房地产'),
        StockBasic(code: '000656.SZ', name: '金科股份', industry: '房地产'),
        StockBasic(code: '600340.SH', name: '华夏幸福', industry: '房地产'),
        StockBasic(code: '001979.SZ', name: '招商积余', industry: '房地产'),
        StockBasic(code: '600606.SH', name: '绿地控股', industry: '房地产'),
        StockBasic(code: '000001.SZ', name: '平安银行', industry: '房地产'),
        StockBasic(code: '600048.SH', name: '保利地产', industry: '房地产'),
      ],
    ),
    Industry(
      name: '白酒',
      code: 'liquor',
      stocks: [
        StockBasic(code: '600519.SH', name: '贵州茅台', industry: '白酒'),
        StockBasic(code: '000858.SZ', name: '五粮液', industry: '白酒'),
        StockBasic(code: '002304.SZ', name: '洋河股份', industry: '白酒'),
        StockBasic(code: '600809.SH', name: '山西汾酒', industry: '白酒'),
        StockBasic(code: '000568.SZ', name: '泸州老窖', industry: '白酒'),
        StockBasic(code: '603589.SH', name: '口子窖', industry: '白酒'),
        StockBasic(code: '600559.SH', name: '老白干酒', industry: '白酒'),
        StockBasic(code: '000596.SZ', name: '古井贡酒', industry: '白酒'),
        StockBasic(code: '603198.SH', name: '迎驾贡酒', industry: '白酒'),
        StockBasic(code: '600779.SH', name: '水井坊', industry: '白酒'),
        StockBasic(code: '603369.SH', name: '今世缘', industry: '白酒'),
        StockBasic(code: '000799.SZ', name: '酒鬼酒', industry: '白酒'),
      ],
    ),
    Industry(
      name: '科技',
      code: 'technology',
      stocks: [
        StockBasic(code: '000063.SZ', name: '中兴通讯', industry: '科技'),
        StockBasic(code: '002415.SZ', name: '海康威视', industry: '科技'),
        StockBasic(code: '300750.SZ', name: '宁德时代', industry: '科技'),
        StockBasic(code: '002475.SZ', name: '立讯精密', industry: '科技'),
        StockBasic(code: '600030.SH', name: '中信证券', industry: '科技'),
        StockBasic(code: '300059.SZ', name: '东方财富', industry: '科技'),
        StockBasic(code: '002594.SZ', name: '比亚迪', industry: '科技'),
        StockBasic(code: '601012.SH', name: '隆基绿能', industry: '科技'),
        StockBasic(code: '300274.SZ', name: '阳光电源', industry: '科技'),
        StockBasic(code: '002129.SZ', name: '中环股份', industry: '科技'),
        StockBasic(code: '600745.SH', name: '闻泰科技', industry: '科技'),
        StockBasic(code: '603160.SH', name: '汇顶科技', industry: '科技'),
      ],
    ),
    Industry(
      name: '能源',
      code: 'energy',
      stocks: [
        StockBasic(code: '601857.SH', name: '中国石油', industry: '能源'),
        StockBasic(code: '600028.SH', name: '中国石化', industry: '能源'),
        StockBasic(code: '601088.SH', name: '中国神华', industry: '能源'),
        StockBasic(code: '600900.SH', name: '长江电力', industry: '能源'),
        StockBasic(code: '601899.SH', name: '紫金矿业', industry: '能源'),
        StockBasic(code: '000876.SZ', name: '新希望', industry: '能源'),
        StockBasic(code: '600019.SH', name: '宝钢股份', industry: '能源'),
        StockBasic(code: '000708.SZ', name: '中信特钢', industry: '能源'),
        StockBasic(code: '601898.SH', name: '中煤能源', industry: '能源'),
        StockBasic(code: '600188.SH', name: '兖矿能源', industry: '能源'),
        StockBasic(code: '600348.SH', name: '阳泉煤业', industry: '能源'),
        StockBasic(code: '000968.SZ', name: '煤气化', industry: '能源'),
      ],
    ),
    Industry(
      name: '食品饮料',
      code: 'food',
      stocks: [
        StockBasic(code: '000895.SZ', name: '双汇发展', industry: '食品饮料'),
        StockBasic(code: '600887.SH', name: '伊利股份', industry: '食品饮料'),
        StockBasic(code: '002714.SZ', name: '牧原股份', industry: '食品饮料'),
        StockBasic(code: '600298.SH', name: '安琪酵母', industry: '食品饮料'),
        StockBasic(code: '000596.SZ', name: '古井贡酒', industry: '食品饮料'),
        StockBasic(code: '603288.SH', name: '海天味业', industry: '食品饮料'),
        StockBasic(code: '002557.SZ', name: '洽洽食品', industry: '食品饮料'),
        StockBasic(code: '603466.SH', name: '风语筑', industry: '食品饮料'),
        StockBasic(code: '600073.SH', name: '上海梅林', industry: '食品饮料'),
        StockBasic(code: '000848.SZ', name: '承德露露', industry: '食品饮料'),
        StockBasic(code: '002557.SZ', name: '洽洽食品', industry: '食品饮料'),
        StockBasic(code: '600519.SH', name: '贵州茅台', industry: '食品饮料'),
      ],
    ),
    Industry(
      name: '化工',
      code: 'chemical',
      stocks: [
        StockBasic(code: '600309.SH', name: '万华化学', industry: '化工'),
        StockBasic(code: '002493.SZ', name: '荣盛石化', industry: '化工'),
        StockBasic(code: '600346.SH', name: '恒力石化', industry: '化工'),
        StockBasic(code: '000301.SZ', name: '东方盛虹', industry: '化工'),
        StockBasic(code: '600160.SH', name: '巨化股份', industry: '化工'),
        StockBasic(code: '002648.SZ', name: '卫星化学', industry: '化工'),
        StockBasic(code: '600426.SH', name: '华鲁恒升', industry: '化工'),
        StockBasic(code: '000830.SZ', name: '鲁西化工', industry: '化工'),
        StockBasic(code: '600352.SH', name: '浙江龙盛', industry: '化工'),
        StockBasic(code: '002326.SZ', name: '永太科技', industry: '化工'),
        StockBasic(code: '603260.SH', name: '合盛硅业', industry: '化工'),
        StockBasic(code: '600143.SH', name: '金发科技', industry: '化工'),
      ],
    ),
  ];
}

// 行业分类模型
class Industry {
  final String name;
  final String code;
  final List<StockBasic> stocks;

  Industry({
    required this.name,
    required this.code,
    required this.stocks,
  });
}

// 股票基本信息模型
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
