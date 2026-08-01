import 'package:flutter_test/flutter_test.dart';
import 'package:onebharat_app/core/theme/app_theme.dart';

void main() {
  group('statusLabel', () {
    test('converts snake_case to Title Case', () {
      expect(statusLabel('payment_held'), 'Payment Held');
      expect(statusLabel('delivered'), 'Delivered');
      expect(statusLabel('in_transit'), 'In Transit');
    });

    test('handles a single-word status', () {
      expect(statusLabel('open'), 'Open');
    });
  });

  group('statusColor', () {
    test('maps known statuses to distinct colors', () {
      expect(statusColor('payment_released'), AppColors.success);
      expect(statusColor('disputed'), AppColors.error);
      expect(statusColor('payment_held'), AppColors.heldBlue);
    });

    test('falls back to textSecondary for unknown statuses', () {
      expect(statusColor('some_unrecognized_status'), AppColors.textSecondary);
    });
  });
}
