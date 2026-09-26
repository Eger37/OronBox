import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:oronbox/src/app/widgets/network_img_layer.dart';

@immutable
class ResourceMediaHeroStyle {
  const ResourceMediaHeroStyle({
    this.opacity = 1,
    this.borderRadius = BorderRadius.zero,
  });

  final double opacity;
  final BorderRadius borderRadius;

  static ResourceMediaHeroStyle lerp(
    ResourceMediaHeroStyle from,
    ResourceMediaHeroStyle to,
    double t,
  ) => ResourceMediaHeroStyle(
    opacity: lerpDouble(from.opacity, to.opacity, t)!,
    borderRadius: BorderRadius.lerp(from.borderRadius, to.borderRadius, t)!,
  );
}

class ResourceMediaHero extends StatelessWidget {
  const ResourceMediaHero({
    super.key,
    required this.tag,
    required this.url,
    required this.width,
    required this.height,
    required this.style,
    this.fit = BoxFit.cover,
  });

  final Object tag;
  final String url;
  final double width;
  final double height;
  final ResourceMediaHeroStyle style;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: ResourceLayoutMediaOpacity.of(context),
    child: Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: _flightShuttleBuilder,
      child: _ResourceMediaEndpoint(
        url: url,
        width: width,
        height: height,
        style: style,
        fit: fit,
      ),
    ),
  );

  static Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final from = (fromHeroContext.widget as Hero).child;
    final to = (toHeroContext.widget as Hero).child;
    if (from is! _ResourceMediaEndpoint || to is! _ResourceMediaEndpoint) {
      return from;
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = flightDirection == HeroFlightDirection.push
            ? animation.value
            : 1 - animation.value;
        return _ResourceMediaSurface(
          url: t < .5 ? from.url : to.url,
          style: ResourceMediaHeroStyle.lerp(from.style, to.style, t),
          fit: t < .5 ? from.fit : to.fit,
        );
      },
    );
  }
}

class ResourceLayoutMediaOpacity extends InheritedWidget {
  const ResourceLayoutMediaOpacity({
    super.key,
    required this.opacity,
    required super.child,
  });

  final double opacity;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ResourceLayoutMediaOpacity>()
          ?.opacity ??
      1;

  @override
  bool updateShouldNotify(ResourceLayoutMediaOpacity oldWidget) =>
      opacity != oldWidget.opacity;
}

class _ResourceMediaEndpoint extends StatelessWidget {
  const _ResourceMediaEndpoint({
    required this.url,
    required this.width,
    required this.height,
    required this.style,
    required this.fit,
  });

  final String url;
  final double width;
  final double height;
  final ResourceMediaHeroStyle style;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: _ResourceMediaSurface(url: url, style: style, fit: fit),
  );
}

class _ResourceMediaSurface extends StatelessWidget {
  const _ResourceMediaSurface({
    required this.url,
    required this.style,
    required this.fit,
  });

  final String url;
  final ResourceMediaHeroStyle style;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: style.opacity,
    child: ClipRRect(
      clipBehavior: Clip.antiAlias,
      borderRadius: style.borderRadius,
      child: NetworkImgLayer(
        src: url,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        borderRadius: BorderRadius.zero,
      ),
    ),
  );
}
