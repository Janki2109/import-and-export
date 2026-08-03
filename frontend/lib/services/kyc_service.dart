import '../core/network/api_client.dart';

class KYCService {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> getMyStatus() async {
    final res = await _client.get('/kyc/me');
    return res.data['data'];
  }

  Future<void> submit({
    String? panNumber,
    String? gstNumber,
    String? iecCode,
    String? businessLicense,
    String? panDocUrl,
    String? gstDocUrl,
    String? iecDocUrl,
    String? addressDocUrl,
    String? bankAccountHolderName,
    String? bankAccountNumber,
    String? bankIfsc,
  }) async {
    await _client.post('/kyc/submit', data: {
      'pan_number': panNumber,
      'gst_number': gstNumber,
      'iec_code': iecCode,
      'business_license': businessLicense,
      'pan_doc_url': panDocUrl,
      'gst_doc_url': gstDocUrl,
      'iec_doc_url': iecDocUrl,
      'address_doc_url': addressDocUrl,
      'bank_account_holder_name': bankAccountHolderName,
      'bank_account_number': bankAccountNumber,
      'bank_ifsc': bankIfsc,
    });
  }
}
