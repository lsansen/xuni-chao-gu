import 'dart:convert';

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
