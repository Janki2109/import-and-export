class HSCode {
  final String code;
  final String description;
  final String chapter;
  final double basicCustomsDutyPercent;
  final double igstPercent;

  HSCode({
    required this.code,
    required this.description,
    required this.chapter,
    required this.basicCustomsDutyPercent,
    required this.igstPercent,
  });

  factory HSCode.fromJson(Map<String, dynamic> json) => HSCode(
        code: json['code'],
        description: json['description'],
        chapter: json['chapter'],
        basicCustomsDutyPercent: (json['basic_customs_duty_percent'] as num).toDouble(),
        igstPercent: (json['igst_percent'] as num).toDouble(),
      );
}

class GSTRate {
  final String category;
  final double ratePercent;
  final String? description;

  GSTRate({required this.category, required this.ratePercent, this.description});

  factory GSTRate.fromJson(Map<String, dynamic> json) => GSTRate(
        category: json['category'],
        ratePercent: (json['rate_percent'] as num).toDouble(),
        description: json['description'],
      );
}

class Country {
  final String id;
  final String name;
  final String iso2;
  final String region;
  final bool isRestricted;
  final String? notes;

  Country({
    required this.id,
    required this.name,
    required this.iso2,
    required this.region,
    required this.isRestricted,
    this.notes,
  });

  factory Country.fromJson(Map<String, dynamic> json) => Country(
        id: json['id'],
        name: json['name'],
        iso2: json['iso2'],
        region: json['region'],
        isRestricted: json['is_restricted'] ?? false,
        notes: json['notes'],
      );
}

class TradePolicy {
  final String policyType;
  final String? hsChapter;
  final String title;
  final String description;

  TradePolicy({required this.policyType, this.hsChapter, required this.title, required this.description});

  factory TradePolicy.fromJson(Map<String, dynamic> json) => TradePolicy(
        policyType: json['policy_type'],
        hsChapter: json['hs_chapter'],
        title: json['title'],
        description: json['description'],
      );
}

class DutyBreakdown {
  final double assessableValue;
  final double basicCustomsDuty;
  final double socialWelfareSurcharge;
  final double igst;
  final double totalDutyPayable;
  final double totalLandedValue;

  DutyBreakdown({
    required this.assessableValue,
    required this.basicCustomsDuty,
    required this.socialWelfareSurcharge,
    required this.igst,
    required this.totalDutyPayable,
    required this.totalLandedValue,
  });

  factory DutyBreakdown.fromJson(Map<String, dynamic> json) => DutyBreakdown(
        assessableValue: (json['assessable_value'] as num).toDouble(),
        basicCustomsDuty: (json['basic_customs_duty'] as num).toDouble(),
        socialWelfareSurcharge: (json['social_welfare_surcharge'] as num).toDouble(),
        igst: (json['igst'] as num).toDouble(),
        totalDutyPayable: (json['total_duty_payable'] as num).toDouble(),
        totalLandedValue: (json['total_landed_value'] as num).toDouble(),
      );
}

class FreightEstimate {
  final String mode;
  final double chargeableWeightKg;
  final double ratePerKg;
  final double baseHandlingFee;
  final double estimatedFreight;

  FreightEstimate({
    required this.mode,
    required this.chargeableWeightKg,
    required this.ratePerKg,
    required this.baseHandlingFee,
    required this.estimatedFreight,
  });

  factory FreightEstimate.fromJson(Map<String, dynamic> json) => FreightEstimate(
        mode: json['mode'],
        chargeableWeightKg: (json['chargeable_weight_kg'] as num).toDouble(),
        ratePerKg: (json['rate_per_kg'] as num).toDouble(),
        baseHandlingFee: (json['base_handling_fee'] as num).toDouble(),
        estimatedFreight: (json['estimated_freight'] as num).toDouble(),
      );
}

class LandedCostBreakdown {
  final double fobValue;
  final double freight;
  final double insurance;
  final double cifValue;
  final double totalDuty;
  final double otherCharges;
  final double totalLandedCost;

  LandedCostBreakdown({
    required this.fobValue,
    required this.freight,
    required this.insurance,
    required this.cifValue,
    required this.totalDuty,
    required this.otherCharges,
    required this.totalLandedCost,
  });

  factory LandedCostBreakdown.fromJson(Map<String, dynamic> json) => LandedCostBreakdown(
        fobValue: (json['fob_value'] as num).toDouble(),
        freight: (json['freight'] as num).toDouble(),
        insurance: (json['insurance'] as num).toDouble(),
        cifValue: (json['cif_value'] as num).toDouble(),
        totalDuty: (json['total_duty'] as num).toDouble(),
        otherCharges: (json['other_charges'] as num).toDouble(),
        totalLandedCost: (json['total_landed_cost'] as num).toDouble(),
      );
}

class AIProductMatch {
  final String hsCode;
  final String description;
  final String confidence;
  final String reason;

  AIProductMatch({required this.hsCode, required this.description, required this.confidence, required this.reason});

  factory AIProductMatch.fromJson(Map<String, dynamic> json) => AIProductMatch(
        hsCode: json['hs_code'] ?? '',
        description: json['description'] ?? '',
        confidence: json['confidence'] ?? '',
        reason: json['reason'] ?? '',
      );
}
