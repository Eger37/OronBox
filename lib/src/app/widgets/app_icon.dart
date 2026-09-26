import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/images/app_icon_dark.svg'
        : 'assets/images/app_icon.svg';
    return SvgPicture.asset(asset, width: size, height: size);
  }
}
