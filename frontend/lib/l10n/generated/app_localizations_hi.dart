// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'वन भारत एक्सपोर्ट-इम्पोर्ट';

  @override
  String get splashTagline => 'वैश्विक व्यापार से जुड़ रहे हैं...';

  @override
  String get splashSubtitle => 'सुरक्षित • सत्यापित • अंतरराष्ट्रीय';

  @override
  String get selectLanguageTitle => 'अपनी भाषा चुनें';

  @override
  String get selectLanguageSubtitle =>
      'जारी रखने के लिए अपनी पसंदीदा भाषा चुनें';

  @override
  String get continueButton => 'जारी रखें';

  @override
  String languagesSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चयनित',
      zero: 'कोई भाषा चयनित नहीं',
    );
    return '$_temp0';
  }

  @override
  String get ok => 'ठीक है';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get save => 'सहेजें';

  @override
  String get retry => 'पुनः प्रयास करें';

  @override
  String get skip => 'छोड़ें';

  @override
  String get next => 'आगे';

  @override
  String get previous => 'पिछला';

  @override
  String get done => 'पूर्ण';

  @override
  String get close => 'बंद करें';

  @override
  String get submit => 'सबमिट करें';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get back => 'वापस';

  @override
  String get search => 'खोजें';

  @override
  String get filter => 'फ़िल्टर';

  @override
  String get upload => 'अपलोड करें';

  @override
  String get download => 'डाउनलोड करें';

  @override
  String get viewAll => 'सभी देखें';

  @override
  String get seeAll => 'सभी देखें';

  @override
  String get edit => 'संपादित करें';

  @override
  String get delete => 'हटाएं';

  @override
  String get logout => 'लॉगआउट';

  @override
  String get login => 'लॉगिन';

  @override
  String get register => 'पंजीकरण करें';

  @override
  String get loading => 'लोड हो रहा है...';

  @override
  String get noDataFound => 'कोई डेटा नहीं मिला';

  @override
  String get errorOccurred => 'एक त्रुटि हुई';

  @override
  String get success => 'सफल';

  @override
  String get pending => 'लंबित';

  @override
  String get approved => 'स्वीकृत';

  @override
  String get rejected => 'अस्वीकृत';

  @override
  String get completed => 'पूर्ण';

  @override
  String get navDashboard => 'डैशबोर्ड';

  @override
  String get navRfq => 'आरएफक्यू';

  @override
  String get navQuotation => 'कोटेशन';

  @override
  String get navOrders => 'ऑर्डर';

  @override
  String get navShipment => 'शिपमेंट';

  @override
  String get navCompliance => 'अनुपालन';

  @override
  String get navNegotiation => 'बातचीत';

  @override
  String get navWallet => 'वॉलेट';

  @override
  String get navEscrow => 'एस्क्रो';

  @override
  String get navNotifications => 'सूचनाएं';

  @override
  String get navSettings => 'सेटिंग्स';

  @override
  String get navProfile => 'प्रोफ़ाइल';

  @override
  String get navChat => 'संदेश';

  @override
  String get loginTitle => 'वापसी पर स्वागत है';

  @override
  String get loginSubtitle =>
      'अपनी वैश्विक व्यापार यात्रा जारी रखने के लिए लॉगिन करें।';

  @override
  String get emailLabel => 'ईमेल';

  @override
  String get passwordLabel => 'पासवर्ड';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get dontHaveAccount => 'खाता नहीं है?';

  @override
  String get createAccount => 'खाता बनाएं';

  @override
  String get loginButton => 'लॉगिन';

  @override
  String get fieldRequired => 'यह फ़ील्ड आवश्यक है';

  @override
  String get invalidEmail => 'एक मान्य ईमेल पता दर्ज करें';

  @override
  String get passwordTooShort => 'पासवर्ड कम से कम 6 अक्षर का होना चाहिए';

  @override
  String get networkError => 'नेटवर्क त्रुटि। कृपया पुनः प्रयास करें।';

  @override
  String get somethingWentWrong => 'कुछ गलत हो गया। कृपया पुनः प्रयास करें।';

  @override
  String get roleImporter => 'आयातक';

  @override
  String get roleExporter => 'निर्यातक';

  @override
  String get roleLogistics => 'लॉजिस्टिक्स पार्टनर';

  @override
  String get roleAdmin => 'एडमिन';
}
