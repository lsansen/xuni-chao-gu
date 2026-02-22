import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart' as pull;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 股票数据模型
class Stock {
  final String code;
  final String name;
  final double currentPrice;
  final double change;
  final double changePercent;
  List<double> historicalPrices;
  List<String> historicalDates;

  Stock({
    required this.code,
    required this.name,
    required this.currentPrice,
    required this.change,
    required this.changePercent,
    required this.historicalPrices,
    required this.historicalDates,
  });
}

// 持仓模型
class PortfolioItem {
  final String stockCode;
  final int quantity;
  final double averagePrice;

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

  static PortfolioItem fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      stockCode: json['stockCode'],
      quantity: json['quantity'],
      averagePrice: json['averagePrice'],
    );
  }
}

// 卖出记录模型
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

  static SellRecord fromJson(Map<String, dynamic> json) {
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

// Tushare API 服务
class TushareApi {
  static const String baseUrl = 'https://api.tushare.pro';
  static const String token = '替换成你自己的Tushare Token';

  final Dio _dio = Dio(BaseOptions(
    headers: {
      'Content-Type': 'application/json',
    },
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  // 获取股票近30天日线数据
  Future<Stock> getStockData(String code, {String period = 'daily'}) async {
    try {
      final response = await _dio.post(
        baseUrl,
        data: {
          'api_name': period == 'daily' ? 'daily' : 'daily',
          'token': token,
          'params': {
            'ts_code': code,
            'start_date': _getDaysAgo(period),
            'end_date': _getToday(),
          },
          'fields': 'trade_date,close,change,pct_chg',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['code'] == 0) {
          final List<dynamic> items = data['data']['items'];
          if (items.isEmpty) {
            throw Exception('无数据');
          }

          items.sort((a, b) => a[0].compareTo(b[0]));

          final List<double> prices = items.map<double>((item) => item[1].toDouble()).toList();
          final List<String> dates = items.map<String>((item) => item[0].toString()).toList();

          final latest = items.last;
          return Stock(
            code: code,
            name: _getStockName(code),
            currentPrice: latest[1].toDouble(),
            change: latest[2]?.toDouble() ?? 0,
            changePercent: latest[3]?.toDouble() ?? 0,
            historicalPrices: prices,
            historicalDates: dates,
          );
        } else {
          throw Exception('API错误: ${data['msg']}');
        }
      } else {
        throw Exception('请求失败: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // 获取30天前的日期
  String _getDaysAgo(String period) {
    int days = period == 'daily' ? 30 : (period == 'weekly' ? 90 : 270);
    final date = DateTime.now().subtract(Duration(days: days));
    return DateFormat('yyyyMMdd').format(date);
  }

  // 获取今天的日期
  String _getToday() {
    return DateFormat('yyyyMMdd').format(DateTime.now());
  }

  // 根据股票代码获取名称
  String _getStockName(String code) {
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

// 股市交易时间提示组件
class TradingTimeBanner extends StatefulWidget {
  const TradingTimeBanner({super.key});

  @override
  State<TradingTimeBanner> createState() => _TradingTimeBannerState();
}

class _TradingTimeBannerState extends State<TradingTimeBanner> {
  bool _expanded = false;
  String _statusText = '';
  Color _statusColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _updateTradingStatus();
  }

  void _updateTradingStatus() {
    final now = DateTime.now();
    final weekday = now.weekday;

    // 判断是否为交易日（周一至周五）
    if (weekday >= 6) {
      setState(() {
        _statusText = '今日股市休市，下一个交易日：${_getNextTradingDay(now)}';
        _statusColor = Colors.red;
      });
      return;
    }

    final hour = now.hour;
    final minute = now.minute;

    // 判断交易时间段
    if (hour < 9 || (hour == 9 && minute < 30)) {
      setState(() {
        _statusText = '当前为股市休市时间，下次开盘：09:30';
        _statusColor = Colors.orange;
      });
    } else if ((hour == 11 && minute > 30) || (hour >= 12 && hour < 13)) {
      setState(() {
        _statusText = '当前为股市休市时间，下次开盘：13:00';
        _statusColor = Colors.orange;
      });
    } else if (hour >= 15) {
      setState(() {
        _statusText = '当前为股市休市时间，下次开盘：${_getNextTradingDay(now)} 09:30';
        _statusColor = Colors.orange;
      });
    } else {
      setState(() {
        _statusText = '当前为股市交易时间：9:30-11:30/13:00-15:00';
        _statusColor = Colors.green;
      });
    }
  }

  String _getNextTradingDay(DateTime now) {
    var nextDay = now.add(const Duration(days: 1));
    while (nextDay.weekday >= 6) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return '${nextDay.year}年${nextDay.month}月${nextDay.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        color: _statusColor.withOpacity(0.1),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _statusColor == Colors.green ? Icons.check_circle : (_statusColor == Colors.orange ? Icons.access_time : Icons.cancel),
                  color: _statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusText,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: _statusColor,
                ),
              ],
            ),
            if (_expanded)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '股市交易规则说明：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('• 交易时间：周一至周五 9:30-11:30、13:00-15:00'),
                    Text('• 休市时间：周六、周日及法定节假日'),
                    Text('• 开盘时间：9:30，收盘时间：15:00'),
                    Text('• 午间休市：11:30-13:00'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 持仓详情页面
class PortfolioDetailPage extends StatefulWidget {
  final PortfolioItem portfolioItem;
  final StockBasic stockBasic;
  final Function onBuy;
  final Function onSell;

  const PortfolioDetailPage({
    super.key,
    required this.portfolioItem,
    required this.stockBasic,
    required this.onBuy,
    required this.onSell,
  });

  @override
  State<PortfolioDetailPage> createState() => _PortfolioDetailPageState();
}

class _PortfolioDetailPageState extends State<PortfolioDetailPage> {
  Stock? _stock;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final api = TushareApi();
      final stock = await api.getStockData(widget.portfolioItem.stockCode);
      if (mounted) {
        setState(() {
          _stock = stock;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '数据加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.stockBasic.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.stockBasic.name)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadStockData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_stock == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.stockBasic.name)),
        body: const Center(child: Text('暂无数据')),
      );
    }

    final stock = _stock!;
    final profit = (stock.currentPrice - widget.portfolioItem.averagePrice) * widget.portfolioItem.quantity;
    final profitRate = (stock.currentPrice - widget.portfolioItem.averagePrice) / widget.portfolioItem.averagePrice * 100;

    return Scaffold(
      appBar: AppBar(title: Text(widget.stockBasic.name)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 基础信息
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.stockBasic.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.stockBasic.code,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '最新价: ${stock.currentPrice.toStringAsFixed(2)}元',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: stock.changePercent >= 0 ? Colors.red : Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${stock.changePercent >= 0 ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 持仓信息
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '持仓信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('持有数量', '${widget.portfolioItem.quantity}股'),
                  _buildInfoRow('成本价', '${widget.portfolioItem.averagePrice.toStringAsFixed(2)}元'),
                  _buildInfoRow('最新价', '${stock.currentPrice.toStringAsFixed(2)}元'),
                  _buildInfoRow(
                    '浮动盈亏',
                    '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)}元',
                    profit >= 0 ? Colors.red : Colors.green,
                  ),
                  _buildInfoRow(
                    '盈利率',
                    '${profitRate >= 0 ? '+' : ''}${profitRate.toStringAsFixed(2)}%',
                    profitRate >= 0 ? Colors.red : Colors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: () => widget.onBuy(widget.stockBasic),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('买入', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: () => widget.onSell(widget.stockBasic),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('卖出', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// K线页面
class KLinePage extends StatefulWidget {
  final Stock stock;

  const KLinePage({super.key, required this.stock});

  @override
  State<KLinePage> createState() => _KLinePageState();
}

class _KLinePageState extends State<KLinePage> {
  String _period = 'daily';
  bool _isLoading = false;
  String _errorMessage = '';
  List<FlSpot> _spots = [];
  List<FlSpot> _ma5Spots = [];
  List<FlSpot> _ma10Spots = [];
  List<FlSpot> _ma20Spots = [];

  @override
  void initState() {
    super.initState();
    _calculateMA();
  }

  void _calculateMA() {
    final prices = widget.stock.historicalPrices;
    _spots = prices.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value);
    }).toList();

    // 计算MA5
    _ma5Spots = [];
    for (int i = 0; i < prices.length; i++) {
      if (i >= 4) {
        double sum = 0;
        for (int j = 0; j < 5; j++) {
          sum += prices[i - j];
        }
        _ma5Spots.add(FlSpot(i.toDouble(), sum / 5));
      } else {
        _ma5Spots.add(FlSpot(i.toDouble(), prices[i]));
      }
    }

    // 计算MA10
    _ma10Spots = [];
    for (int i = 0; i < prices.length; i++) {
      if (i >= 9) {
        double sum = 0;
        for (int j = 0; j < 10; j++) {
          sum += prices[i - j];
        }
        _ma10Spots.add(FlSpot(i.toDouble(), sum / 10));
      } else {
        _ma10Spots.add(FlSpot(i.toDouble(), prices[i]));
      }
    }

    // 计算MA20
    _ma20Spots = [];
    for (int i = 0; i < prices.length; i++) {
      if (i >= 19) {
        double sum = 0;
        for (int j = 0; j < 20; j++) {
          sum += prices[i - j];
        }
        _ma20Spots.add(FlSpot(i.toDouble(), sum / 20));
      } else {
        _ma20Spots.add(FlSpot(i.toDouble(), prices[i]));
      }
    }
  }

  Future<void> _changePeriod(String period) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _period = period;
    });
    try {
      final api = TushareApi();
      final stock = await api.getStockData(widget.stock.code, period: period);
      if (mounted) {
        setState(() {
          widget.stock.historicalPrices = stock.historicalPrices;
          widget.stock.historicalDates = stock.historicalDates;
          _calculateMA();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'K线数据加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stock.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _changePeriod(_period),
          ),
        ],
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
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // K线切换栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          _buildPeriodButton('日线', 'daily'),
                          const SizedBox(width: 8),
                          _buildPeriodButton('周线', 'weekly'),
                          const SizedBox(width: 8),
                          _buildPeriodButton('月线', 'monthly'),
                        ],
                      ),
                    ),
                    // K线主图
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              drawHorizontalLine: true,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: Colors.grey[300],
                                  strokeWidth: 1,
                                );
                              },
                              getDrawingVerticalLine: (value) {
                                return FlLine(
                                  color: Colors.grey[300],
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 60,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toStringAsFixed(2),
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index >= 0 && index < widget.stock.historicalDates.length) {
                                      return Text(
                                        widget.stock.historicalDates[index].substring(4),
                                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: true),
                            lineBarsData: [
                              // MA20均线
                              LineChartBarData(
                                spots: _ma20Spots,
                                isCurved: true,
                                color: Colors.purple,
                                barWidth: 1,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                              // MA10均线
                              LineChartBarData(
                                spots: _ma10Spots,
                                isCurved: true,
                                color: Colors.yellow,
                                barWidth: 1,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                              // MA5均线
                              LineChartBarData(
                                spots: _ma5Spots,
                                isCurved: true,
                                color: Colors.white,
                                barWidth: 1,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                              // K线
                              LineChartBarData(
                                spots: _spots,
                                isCurved: true,
                                color: Colors.blue,
                                barWidth: 2,
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              enabled: true,
                              touchTooltipData: LineTouchTooltipData(
                                tooltipBgColor: Colors.white,
                                tooltipRoundedRadius: 8,
                                getTooltipItems: (touchedSpots) {
                                  if (touchedSpots.isEmpty) return [];
                                  final index = touchedSpots[0].x.toInt();
                                  if (index >= 0 && index < widget.stock.historicalDates.length) {
                                    return [
                                      LineTooltipItem(
                                        widget.stock.historicalDates[index].substring(4),
                                        const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      LineTooltipItem(
                                        '${widget.stock.historicalPrices[index].toStringAsFixed(2)}元',
                                        const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ];
                                  }
                                  return [];
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPeriodButton(String label, String period) {
    final isSelected = _period == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changePeriod(period),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// 主页面
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TushareApi _tushareApi = TushareApi();
  late SharedPreferences _prefs;

  // 资金数据
  final double _initialFunds = 500000.0;
  double _availableFunds = 500000.0;
  double _totalAssets = 500000.0;
  double _profitRate = 0.0;
  double _unlockedLimit = 500000.0;

  // 股票数据
  List<StockBasic> _allStocks = [];
  List<StockBasic> _filteredStocks = [];
  List<Stock> _stocks = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // 持仓数据
  List<PortfolioItem> _portfolio = [];
  List<SellRecord> _sellRecords = [];

  // 行业分类
  Industry? _selectedIndustry;
  final pull.RefreshController _refreshController = pull.RefreshController();

  // 自动刷新定时器
  Timer? _refreshTimer;
  bool _isAutoRefreshEnabled = true;

  @override
  void initState() {
    super.initState();
    _initSharedPreferences();
    _loadStockData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    final interval = _isTradingTime() ? const Duration(seconds: 30) : const Duration(minutes: 5);
    _refreshTimer = Timer.periodic(interval, (timer) {
      if (_isAutoRefreshEnabled && mounted) {
        _refreshStockData();
      }
    });
  }

  bool _isTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    if (weekday >= 6) return false;
    
    final hour = now.hour;
    final minute = now.minute;
    
    if ((hour == 9 && minute >= 30) && hour < 11) return true;
    if (hour == 11 && minute <= 30) return true;
    if (hour >= 13 && hour < 15) return true;
    
    return false;
  }

  Future<void> _refreshStockData() async {
    try {
      for (final item in _portfolio) {
        try {
          await _tushareApi.getStockData(item.stockCode);
        } catch (e) {
          print('刷新股票 ${item.stockCode} 失败: $e');
        }
      }
      _calculateTotalAssets();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('自动刷新失败: $e');
    }
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _availableFunds = _prefs.getDouble('availableFunds') ?? _initialFunds;
    final portfolioJson = _prefs.getString('portfolio');
    if (portfolioJson != null) {
      final List<dynamic> list = jsonDecode(portfolioJson);
      _portfolio = list.map((item) => PortfolioItem.fromJson(item as Map<String, dynamic>)).toList();
    }
    final sellRecordsJson = _prefs.getString('sellRecords');
    if (sellRecordsJson != null) {
      final List<dynamic> list = jsonDecode(sellRecordsJson);
      _sellRecords = list.map((item) => SellRecord.fromJson(item as Map<String, dynamic>)).toList();
    }
    _calculateTotalAssets();
    _checkUnlockLimit();
    setState(() {});
  }

  Future<void> _loadStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      // 加载所有行业股票
      _allStocks = [];
      for (final industry in TushareApi._industries) {
        _allStocks.addAll(industry.stocks);
      }
      _selectedIndustry = TushareApi._industries[0];
      _filteredStocks = _selectedIndustry!.stocks;
      setState(() {});
    } catch (e) {
      setState(() {
        _errorMessage = '数据加载失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _buyStock(StockBasic stockBasic) async {
    try {
      final stock = await _tushareApi.getStockData(stockBasic.code);
      final buyQuantity = 100;
      final cost = stock.currentPrice * buyQuantity;

      if (_availableFunds < cost) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('资金不足')),
          );
        }
        return;
      }

      if (_totalAssets > _unlockedLimit) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('超过额度限制')),
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
          SnackBar(content: Text('成功买入${stock.name}100股，花费${_formatFunds(cost)}元')),
        );
      }

      _calculateTotalAssets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('买入失败: $e')),
        );
      }
    }
  }

  Future<void> _sellStock(StockBasic stockBasic) async {
    try {
      final stock = await _tushareApi.getStockData(stockBasic.code);
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
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final quantity = int.tryParse(quantityController.text) ?? 0;
                Navigator.pop(context, quantity);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );

      if (result == null || result == 0) return;

      final sellQuantity = result;
      if (sellQuantity > maxQuantity) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('卖出数量不能超过持有数量')),
          );
        }
        return;
      }

      final amount = stock.currentPrice * sellQuantity;

      // 更新持仓
      if (sellQuantity == maxQuantity) {
        _portfolio.removeAt(index);
      } else {
        _portfolio[index] = PortfolioItem(
          stockCode: stock.code,
          quantity: maxQuantity - sellQuantity,
          averagePrice: portfolioItem.averagePrice,
        );
      }

      // 更新资金
      _availableFunds += amount;

      // 添加卖出记录
      final sellRecord = SellRecord(
        stockCode: stock.code,
        stockName: stock.name,
        quantity: sellQuantity,
        price: stock.currentPrice,
        amount: amount,
        time: DateTime.now(),
      );
      _sellRecords.insert(0, sellRecord);
      if (_sellRecords.length > 10) {
        _sellRecords.removeLast();
      }

      await _prefs.setDouble('availableFunds', _availableFunds);
      await _prefs.setString('portfolio', jsonEncode(_portfolio));
      await _prefs.setString('sellRecords', jsonEncode(_sellRecords));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功卖出${stock.name}$sellQuantity股，到账${_formatFunds(amount)}元')),
        );
      }

      _calculateTotalAssets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('卖出失败: $e')),
        );
      }
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

    if (newLimit > _unlockedLimit) {
      _unlockedLimit = newLimit;
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

  Widget _buildFundsPanel() {
    return Container(
      color: Colors.lightBlue[50],
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '总资产: ${_formatFunds(_totalAssets)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Icon(
                    Icons.autorenew,
                    size: 16,
                    color: _isAutoRefreshEnabled ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isAutoRefreshEnabled ? '自动刷新中' : '自动刷新已关闭',
                    style: TextStyle(
                      fontSize: 14,
                      color: _isAutoRefreshEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '已解锁额度: ${_formatFunds(_unlockedLimit)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('可用资金: ${_formatFunds(_availableFunds)}'),
              Text(
                '盈利率: ${_profitRate.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: _profitRate >= 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: min(_profitRate / 30, 1.0),
            backgroundColor: Colors.grey[200],
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          Text('解锁进度: ${_profitRate.toStringAsFixed(2)}% / 30%（解锁500万）'),
        ],
      ),
    );
  }

  Widget _buildPortfolioSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '我的模拟持仓',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SellRecordsPage(sellRecords: _sellRecords),
                    ),
                  );
                },
                child: const Text('卖出记录'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_portfolio.isEmpty)
            const Text('暂无持仓，长按股票买入')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _portfolio.length,
              itemBuilder: (context, index) {
                final item = _portfolio[index];
                final stockBasic = _allStocks.firstWhere(
                  (s) => s.code == item.stockCode,
                  orElse: () => StockBasic(
                    code: item.stockCode,
                    name: item.stockCode,
                    industry: '',
                  ),
                );
                return FutureBuilder<Stock>(
                  future: _tushareApi.getStockData(item.stockCode),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ListTile(
                        title: Text(stockBasic.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('持有数量: ${item.quantity}股'),
                            Text('成本价: ${item.averagePrice.toStringAsFixed(2)}元'),
                            Text('数据加载失败', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ],
                        ),
                        trailing: const Icon(Icons.error, color: Colors.red),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PortfolioDetailPage(
                                portfolioItem: item,
                                stockBasic: stockBasic,
                                onBuy: _buyStock,
                                onSell: _sellStock,
                              ),
                            ),
                          );
                        },
                      );
                    }
                    
                    if (snapshot.hasData) {
                      final stock = snapshot.data!;
                      final profit = (stock.currentPrice - item.averagePrice) * item.quantity;
                      final profitRate = (stock.currentPrice - item.averagePrice) / item.averagePrice * 100;

                      return ListTile(
                        title: Text(stockBasic.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('持有数量: ${item.quantity}股'),
                            Text('成本价: ${item.averagePrice.toStringAsFixed(2)}元'),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '最新价: ${stock.currentPrice.toStringAsFixed(2)}元',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '盈亏: ${profit.toStringAsFixed(2)}元',
                              style: TextStyle(
                                color: profit >= 0 ? Colors.red : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '盈利率: ${profitRate.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: profitRate >= 0 ? Colors.red : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PortfolioDetailPage(
                                portfolioItem: item,
                                stockBasic: stockBasic,
                                onBuy: _buyStock,
                                onSell: _sellStock,
                              ),
                            ),
                          );
                        },
                        onLongPress: () => _buyStock(stockBasic),
                      );
                    }
                    
                    return const ListTile(
                      title: Text('加载中...'),
                      subtitle: const Text('正在获取股票数据'),
                      trailing: const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIndustrySection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '行业分类',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          // 行业分类按钮
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TushareApi._industries.map((industry) {
                final isSelected = _selectedIndustry?.code == industry.code;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndustry = industry;
                        _filteredStocks = industry.stocks;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        industry.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // 股票列表
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage.isNotEmpty)
            Text(_errorMessage, style: const TextStyle(color: Colors.red))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredStocks.length,
              itemBuilder: (context, index) {
                final stockBasic = _filteredStocks[index];
                return FutureBuilder<Stock>(
                  future: _tushareApi.getStockData(stockBasic.code),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ListTile(
                        title: Text(stockBasic.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('代码: ${stockBasic.code}'),
                            if (stockBasic.industry.isNotEmpty) Text('行业: ${stockBasic.industry}'),
                            Text('数据加载失败', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ],
                        ),
                        trailing: const Icon(Icons.error, color: Colors.red),
                        onTap: () {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('数据加载失败: ${snapshot.error}')),
                            );
                          }
                        },
                        onLongPress: () => _buyStock(stockBasic),
                      );
                    }
                    
                    final trailingWidget = snapshot.hasData
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${snapshot.data!.currentPrice.toStringAsFixed(2)}元',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: snapshot.data!.changePercent >= 0 ? Colors.red : Colors.green,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${snapshot.data!.changePercent >= 0 ? '+' : ''}${snapshot.data!.changePercent.toStringAsFixed(2)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : SizedBox(
                            width: 60,
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                    
                    return ListTile(
                      title: Text(stockBasic.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('代码: ${stockBasic.code}'),
                          if (stockBasic.industry.isNotEmpty) Text('行业: ${stockBasic.industry}'),
                        ],
                      ),
                      trailing: trailingWidget,
                      onTap: () async {
                        try {
                          final stock = snapshot.data ?? await _tushareApi.getStockData(stockBasic.code);
                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => KLinePage(stock: stock),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('加载失败: $e')),
                            );
                          }
                        }
                      },
                      onLongPress: () => _buyStock(stockBasic),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模拟炒股'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: _isAutoRefreshEnabled ? Colors.blue : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _isAutoRefreshEnabled = !_isAutoRefreshEnabled;
                if (_isAutoRefreshEnabled) {
                  _startAutoRefresh();
                } else {
                  _refreshTimer?.cancel();
                }
              });
            },
            tooltip: _isAutoRefreshEnabled ? '自动刷新已开启' : '自动刷新已关闭',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: StockSearchDelegate(_allStocks, _buyStock),
              );
            },
          ),
        ],
      ),
      body: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        enablePullUp: false,
        onRefresh: () async {
          await _loadStockData();
        },
        child: ListView(
          children: [
            const TradingTimeBanner(),
            _buildFundsPanel(),
            _buildPortfolioSection(),
            _buildIndustrySection(),
          ],
        ),
      ),
    );
  }
}

// 股票搜索代理
class StockSearchDelegate extends SearchDelegate<StockBasic> {
  final List<StockBasic> stocks;
  final Function(StockBasic) onStockSelected;

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

  @override
  Widget buildResults(BuildContext context) {
    final results = stocks.where((stock) {
      return stock.name.contains(query) || stock.code.contains(query);
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final stock = results[index];
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
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = stocks.where((stock) {
      return stock.name.contains(query) || stock.code.contains(query);
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final stock = results[index];
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
