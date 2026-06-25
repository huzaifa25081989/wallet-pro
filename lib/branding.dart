import 'package:flutter/foundation.dart';
import 'db.dart';
import 'widgets.dart';

/// Editable, on-device branding/content. Owner (Business tier) can change these
/// from the admin screen; values persist in the settings table.
class Branding extends ChangeNotifier {
  String appName = 'ProFinance';
  String tagline = 'Your money, beautifully managed';
  String currency = 'Rs';
  String devName = 'Muhammad Huzaifa';
  String devQuals = 'ACCA · FMVA · MBA Finance · Banking · Business Studies';
  String devPhone = '92315-3042437';
  String aboutDev =
      'Wallet Pro is designed and built by Muhammad Huzaifa, a finance professional passionate about making personal finance simple, powerful and private.';

  Future<void> load() async {
    appName = await DB.settingGet('b_appName') ?? appName;
    tagline = await DB.settingGet('b_tagline') ?? tagline;
    currency = await DB.settingGet('b_currency') ?? currency;
    devName = await DB.settingGet('b_devName') ?? devName;
    devQuals = await DB.settingGet('b_devQuals') ?? devQuals;
    devPhone = await DB.settingGet('b_devPhone') ?? devPhone;
    aboutDev = await DB.settingGet('b_aboutDev') ?? aboutDev;
    kCur = currency;
    notifyListeners();
  }

  Future<void> save({
    String? appName,
    String? tagline,
    String? currency,
    String? devName,
    String? devQuals,
    String? devPhone,
    String? aboutDev,
  }) async {
    if (appName != null) {
      this.appName = appName;
      await DB.settingSet('b_appName', appName);
    }
    if (tagline != null) {
      this.tagline = tagline;
      await DB.settingSet('b_tagline', tagline);
    }
    if (currency != null) {
      this.currency = currency;
      kCur = currency;
      await DB.settingSet('b_currency', currency);
    }
    if (devName != null) {
      this.devName = devName;
      await DB.settingSet('b_devName', devName);
    }
    if (devQuals != null) {
      this.devQuals = devQuals;
      await DB.settingSet('b_devQuals', devQuals);
    }
    if (devPhone != null) {
      this.devPhone = devPhone;
      await DB.settingSet('b_devPhone', devPhone);
    }
    if (aboutDev != null) {
      this.aboutDev = aboutDev;
      await DB.settingSet('b_aboutDev', aboutDev);
    }
    notifyListeners();
  }
}

final branding = Branding();
