import 'package:flutter/widgets.dart';

/// App-wide navigator key so code outside the widget tree (push notification tap handling)
/// can navigate without needing a BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
