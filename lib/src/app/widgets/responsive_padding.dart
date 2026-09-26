import 'package:material_ui/material_ui.dart';
import 'package:oronbox/src/core/utils/layout.dart';

class ResponsivePadding extends StatelessWidget {
  const ResponsivePadding({
    super.key,
    required this.child,
    this.maxWidth = LayoutBreakpoint.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = responsiveValue(
      width,
      compact: 16.0,
      medium: 24.0,
      expanded: 32.0,
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: child,
        ),
      ),
    );
  }
}
