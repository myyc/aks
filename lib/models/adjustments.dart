import 'dart:convert';

/// Base class for all image adjustments
abstract class Adjustment {
  final String type;
  
  Adjustment(this.type);
  
  /// Convert to JSON map
  Map<String, dynamic> toJson();
  
  /// Create from JSON map
  factory Adjustment.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'white_balance':
        return WhiteBalanceAdjustment.fromJson(json);
      case 'exposure':
        return ExposureAdjustment.fromJson(json);
      case 'contrast':
        return ContrastAdjustment.fromJson(json);
      case 'highlights_shadows':
        return HighlightsShadowsAdjustment.fromJson(json);
      case 'saturation_vibrance':
        return SaturationVibranceAdjustment.fromJson(json);
      case 'blacks_whites':
        return BlacksWhitesAdjustment.fromJson(json);
      case 'tone_curve':
        return ToneCurveAdjustment.fromJson(json);
      default:
        throw Exception('Unknown adjustment type: ${json['type']}');
    }
  }
  
  /// Create a copy with modified values
  Adjustment copyWith();
  
  /// Reset to default values
  Adjustment reset();
}

/// White balance adjustment
class WhiteBalanceAdjustment extends Adjustment {
  final double temperature; // 2000K to 10000K (Kelvin), default 5500K (daylight)
  final double tint;        // -150 to 150 (Green-Magenta axis)
  
  WhiteBalanceAdjustment({
    this.temperature = 5500.0, // Daylight default
    this.tint = 0.0,
  }) : super('white_balance');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'temperature': temperature,
    'tint': tint,
  };
  
  factory WhiteBalanceAdjustment.fromJson(Map<String, dynamic> json) {
    return WhiteBalanceAdjustment(
      temperature: (json['temperature'] ?? 5500.0).toDouble(),
      tint: (json['tint'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  WhiteBalanceAdjustment copyWith({
    double? temperature,
    double? tint,
  }) {
    return WhiteBalanceAdjustment(
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
    );
  }
  
  @override
  WhiteBalanceAdjustment reset() {
    return WhiteBalanceAdjustment(); // Returns to 5500K, tint 0
  }
}

/// Exposure adjustment
class ExposureAdjustment extends Adjustment {
  final double value; // -5.0 to +5.0 EV (Exposure Value/stops)
  
  ExposureAdjustment({
    this.value = 0.0,
  }) : super('exposure');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value,
  };
  
  factory ExposureAdjustment.fromJson(Map<String, dynamic> json) {
    return ExposureAdjustment(
      value: (json['value'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  ExposureAdjustment copyWith({double? value}) {
    return ExposureAdjustment(value: value ?? this.value);
  }
  
  @override
  ExposureAdjustment reset() {
    return ExposureAdjustment();
  }
}

/// Contrast adjustment
class ContrastAdjustment extends Adjustment {
  final double value; // -100 to +100 (percentage)
  
  ContrastAdjustment({
    this.value = 0.0,
  }) : super('contrast');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value,
  };
  
  factory ContrastAdjustment.fromJson(Map<String, dynamic> json) {
    return ContrastAdjustment(
      value: (json['value'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  ContrastAdjustment copyWith({double? value}) {
    return ContrastAdjustment(value: value ?? this.value);
  }
  
  @override
  ContrastAdjustment reset() {
    return ContrastAdjustment();
  }
}

/// Highlights and shadows adjustment
class HighlightsShadowsAdjustment extends Adjustment {
  final double highlights; // -100 to +100 (percentage, negative = darken, positive = brighten)
  final double shadows;    // -100 to +100 (percentage, negative = darken, positive = brighten)
  
  HighlightsShadowsAdjustment({
    this.highlights = 0.0,
    this.shadows = 0.0,
  }) : super('highlights_shadows');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'highlights': highlights,
    'shadows': shadows,
  };
  
  factory HighlightsShadowsAdjustment.fromJson(Map<String, dynamic> json) {
    return HighlightsShadowsAdjustment(
      highlights: (json['highlights'] ?? 0.0).toDouble(),
      shadows: (json['shadows'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  HighlightsShadowsAdjustment copyWith({
    double? highlights,
    double? shadows,
  }) {
    return HighlightsShadowsAdjustment(
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
    );
  }
  
  @override
  HighlightsShadowsAdjustment reset() {
    return HighlightsShadowsAdjustment();
  }
}

/// Saturation and vibrance adjustment
class SaturationVibranceAdjustment extends Adjustment {
  final double saturation; // -100 to +100 (percentage, -100 = grayscale, +100 = max saturation)
  final double vibrance;   // -100 to +100 (percentage, smart saturation that protects skin tones)
  
  SaturationVibranceAdjustment({
    this.saturation = 0.0,
    this.vibrance = 0.0,
  }) : super('saturation_vibrance');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'saturation': saturation,
    'vibrance': vibrance,
  };
  
  factory SaturationVibranceAdjustment.fromJson(Map<String, dynamic> json) {
    return SaturationVibranceAdjustment(
      saturation: (json['saturation'] ?? 0.0).toDouble(),
      vibrance: (json['vibrance'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  SaturationVibranceAdjustment copyWith({
    double? saturation,
    double? vibrance,
  }) {
    return SaturationVibranceAdjustment(
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
    );
  }
  
  @override
  SaturationVibranceAdjustment reset() {
    return SaturationVibranceAdjustment();
  }
}

/// Tone curve adjustment
class ToneCurveAdjustment extends Adjustment {
  final List<CurvePoint> rgbCurve;
  final List<CurvePoint> redCurve;
  final List<CurvePoint> greenCurve;
  final List<CurvePoint> blueCurve;
  
  ToneCurveAdjustment({
    List<CurvePoint>? rgbCurve,
    List<CurvePoint>? redCurve,
    List<CurvePoint>? greenCurve,
    List<CurvePoint>? blueCurve,
  }) : rgbCurve = rgbCurve ?? [CurvePoint(0, 0), CurvePoint(255, 255)],
       redCurve = redCurve ?? [CurvePoint(0, 0), CurvePoint(255, 255)],
       greenCurve = greenCurve ?? [CurvePoint(0, 0), CurvePoint(255, 255)],
       blueCurve = blueCurve ?? [CurvePoint(0, 0), CurvePoint(255, 255)],
       super('tone_curve');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'rgb_curve': rgbCurve.map((p) => p.toJson()).toList(),
    'red_curve': redCurve.map((p) => p.toJson()).toList(),
    'green_curve': greenCurve.map((p) => p.toJson()).toList(),
    'blue_curve': blueCurve.map((p) => p.toJson()).toList(),
  };
  
  factory ToneCurveAdjustment.fromJson(Map<String, dynamic> json) {
    return ToneCurveAdjustment(
      rgbCurve: (json['rgb_curve'] as List?)
          ?.map((p) => CurvePoint.fromJson(p))
          .toList(),
      redCurve: (json['red_curve'] as List?)
          ?.map((p) => CurvePoint.fromJson(p))
          .toList(),
      greenCurve: (json['green_curve'] as List?)
          ?.map((p) => CurvePoint.fromJson(p))
          .toList(),
      blueCurve: (json['blue_curve'] as List?)
          ?.map((p) => CurvePoint.fromJson(p))
          .toList(),
    );
  }
  
  @override
  ToneCurveAdjustment copyWith({
    List<CurvePoint>? rgbCurve,
    List<CurvePoint>? redCurve,
    List<CurvePoint>? greenCurve,
    List<CurvePoint>? blueCurve,
  }) {
    return ToneCurveAdjustment(
      rgbCurve: rgbCurve ?? this.rgbCurve,
      redCurve: redCurve ?? this.redCurve,
      greenCurve: greenCurve ?? this.greenCurve,
      blueCurve: blueCurve ?? this.blueCurve,
    );
  }
  
  @override
  ToneCurveAdjustment reset() {
    return ToneCurveAdjustment();
  }
  
  /// Check if curves are at default (no adjustment)
  bool get isDefault {
    return _isDefaultCurve(rgbCurve) &&
           _isDefaultCurve(redCurve) &&
           _isDefaultCurve(greenCurve) &&
           _isDefaultCurve(blueCurve);
  }
  
  bool _isDefaultCurve(List<CurvePoint> curve) {
    return curve.length == 2 &&
           curve[0].x == 0 && curve[0].y == 0 &&
           curve[1].x == 255 && curve[1].y == 255;
  }
}

/// A point on a tone curve
class CurvePoint {
  final double x; // Input value (0-255)
  final double y; // Output value (0-255)
  
  const CurvePoint(this.x, this.y);
  
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  
  factory CurvePoint.fromJson(Map<String, dynamic> json) {
    return CurvePoint(
      (json['x'] ?? 0).toDouble(),
      (json['y'] ?? 0).toDouble(),
    );
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurvePoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;
  
  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// Blacks and whites point adjustment
class BlacksWhitesAdjustment extends Adjustment {
  final double blacks; // -100 to +100 (lifts/crushes blacks)
  final double whites; // -100 to +100 (extends/clips whites)
  
  BlacksWhitesAdjustment({
    this.blacks = 0.0,
    this.whites = 0.0,
  }) : super('blacks_whites');
  
  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'blacks': blacks,
    'whites': whites,
  };
  
  factory BlacksWhitesAdjustment.fromJson(Map<String, dynamic> json) {
    return BlacksWhitesAdjustment(
      blacks: (json['blacks'] ?? 0.0).toDouble(),
      whites: (json['whites'] ?? 0.0).toDouble(),
    );
  }
  
  @override
  BlacksWhitesAdjustment copyWith({
    double? blacks,
    double? whites,
  }) {
    return BlacksWhitesAdjustment(
      blacks: blacks ?? this.blacks,
      whites: whites ?? this.whites,
    );
  }
  
  @override
  BlacksWhitesAdjustment reset() {
    return BlacksWhitesAdjustment();
  }
}