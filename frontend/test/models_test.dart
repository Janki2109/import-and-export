import 'package:flutter_test/flutter_test.dart';
import 'package:onebharat_app/models/order.dart';
import 'package:onebharat_app/models/company.dart';
import 'package:onebharat_app/models/platform.dart';

void main() {
  group('Order.fromJson', () {
    test('parses a complete order payload', () {
      final json = {
        'id': 'o1',
        'order_number': 'OBEI-2026-000123',
        'importer_id': 'imp1',
        'exporter_id': 'exp1',
        'product_name': 'Steel Pipes',
        'hsn_code': '7306.90',
        'quantity': 100,
        'unit': 'units',
        'unit_price': 500.0,
        'currency': 'INR',
        'total_amount': 50000.0,
        'platform_fee_amount': 500.0,
        'exporter_payout_amount': 49360.0,
        'status': 'payment_held',
        'auto_release_days': 7,
        'delivery_address': 'Mumbai Port',
        'notes': null,
        'created_at': '2026-01-15T10:30:00Z',
      };

      final order = Order.fromJson(json);

      expect(order.orderNumber, 'OBEI-2026-000123');
      expect(order.quantity, 100.0);
      expect(order.totalAmount, 50000.0);
      expect(order.status, 'payment_held');
      expect(order.hsnCode, '7306.90');
      expect(order.notes, isNull);
    });

    test('defaults optional numeric fields when absent', () {
      final json = {
        'id': 'o2',
        'order_number': 'OBEI-2026-000124',
        'importer_id': 'imp1',
        'exporter_id': 'exp1',
        'product_name': 'Widgets',
        'hsn_code': null,
        'quantity': 5,
        'unit': 'kg',
        'unit_price': 10.0,
        'total_amount': 50.0,
        'status': 'created',
        'delivery_address': null,
        'notes': null,
        'created_at': '2026-01-15T10:30:00Z',
      };

      final order = Order.fromJson(json);

      expect(order.currency, 'INR'); // default when key absent
      expect(order.platformFeeAmount, 0);
      expect(order.autoReleaseDays, 7); // default
    });
  });

  group('Company.fromJson', () {
    test('parses a full company profile', () {
      final company = Company.fromJson({
        'id': 'c1',
        'company_name': 'ABC Exports',
        'business_type': 'Manufacturer',
        'registration_number': 'REG123',
        'address': '123 Trade St',
        'city': 'Mumbai',
        'country': 'India',
        'website': 'https://abcexports.com',
      });

      expect(company.companyName, 'ABC Exports');
      expect(company.city, 'Mumbai');
      expect(company.website, 'https://abcexports.com');
    });
  });

  group('Dispute.fromJson', () {
    test('parses an open dispute without a resolution yet', () {
      final dispute = Dispute.fromJson({
        'id': 'd1',
        'order_id': 'o1',
        'reason': 'Goods damaged in transit',
        'status': 'open',
        'resolution_notes': null,
        'created_at': '2026-01-20T08:00:00Z',
      });

      expect(dispute.status, 'open');
      expect(dispute.resolutionNotes, isNull);
      expect(dispute.reason, 'Goods damaged in transit');
    });
  });

  group('Membership.fromJson', () {
    test('parses a free-tier membership with no expiry', () {
      final m = Membership.fromJson({'tier': 'free', 'is_featured': false, 'expires_at': null});
      expect(m.tier, 'free');
      expect(m.isFeatured, false);
      expect(m.expiresAt, isNull);
    });

    test('parses an enterprise membership with an expiry date', () {
      final m = Membership.fromJson({
        'tier': 'enterprise',
        'is_featured': true,
        'expires_at': '2026-03-01T00:00:00Z',
      });
      expect(m.tier, 'enterprise');
      expect(m.isFeatured, true);
      expect(m.expiresAt, isNotNull);
    });
  });
}
