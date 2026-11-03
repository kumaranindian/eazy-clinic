import 'package:flutter/widgets.dart';

/// The approved EazyClinic logo. Always uses the original artwork; the
/// aspect ratio is preserved (never stretch). Keep clear space around it of at
/// least a quarter of its height.
///
/// - [EcBrandLogo.full]: icon + wordmark + tagline (splash, login, invoices).
/// - [EcBrandLogo.icon]: icon only (app icon, collapsed navigation).
class EcBrandLogo extends StatelessWidget {
  const EcBrandLogo.full({this.height = 160, super.key})
    : _asset = 'assets/branding/eazyclinic_logo.png';

  const EcBrandLogo.icon({this.height = 48, super.key})
    : _asset = 'assets/branding/eazyclinic_icon.png';

  final double height;
  final String _asset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'EazyClinic. You Care. We Manage.',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          _asset,
          package: 'design_system',
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
