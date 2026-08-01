// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'One Bharat Export-Import';

  @override
  String get splashTagline => 'Connecting Global Trade...';

  @override
  String get splashSubtitle => 'Secure • Verified • International';

  @override
  String get selectLanguageTitle => 'Choose Your Language';

  @override
  String get selectLanguageSubtitle =>
      'Select your preferred language to continue';

  @override
  String get continueButton => 'Continue';

  @override
  String languagesSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      zero: 'No language selected',
    );
    return '$_temp0';
  }

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get retry => 'Retry';

  @override
  String get skip => 'Skip';

  @override
  String get next => 'Next';

  @override
  String get previous => 'Previous';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get submit => 'Submit';

  @override
  String get confirm => 'Confirm';

  @override
  String get back => 'Back';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get upload => 'Upload';

  @override
  String get download => 'Download';

  @override
  String get viewAll => 'View All';

  @override
  String get seeAll => 'See All';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get logout => 'Logout';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get loading => 'Loading...';

  @override
  String get noDataFound => 'No data found';

  @override
  String get errorOccurred => 'An error occurred';

  @override
  String get success => 'Success';

  @override
  String get pending => 'Pending';

  @override
  String get approved => 'Approved';

  @override
  String get rejected => 'Rejected';

  @override
  String get completed => 'Completed';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navRfq => 'RFQ';

  @override
  String get navQuotation => 'Quotation';

  @override
  String get navOrders => 'Orders';

  @override
  String get navShipment => 'Shipment';

  @override
  String get navCompliance => 'Compliance';

  @override
  String get navNegotiation => 'Negotiation';

  @override
  String get navWallet => 'Wallet';

  @override
  String get navEscrow => 'Escrow';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navSettings => 'Settings';

  @override
  String get navProfile => 'Profile';

  @override
  String get navChat => 'Messages';

  @override
  String get loginTitle => 'Welcome Back';

  @override
  String get loginSubtitle => 'Login to continue your global trade journey.';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get dontHaveAccount => 'Don\'t have an account?';

  @override
  String get createAccount => 'Create Account';

  @override
  String get loginButton => 'Login';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get invalidEmail => 'Enter a valid email address';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get networkError => 'Network error. Please try again.';

  @override
  String get somethingWentWrong => 'Something went wrong. Please try again.';

  @override
  String get roleImporter => 'Importer';

  @override
  String get roleExporter => 'Exporter';

  @override
  String get roleLogistics => 'Logistics Partner';

  @override
  String get roleAdmin => 'Admin';
}
