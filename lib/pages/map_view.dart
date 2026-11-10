import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/regions.dart';
import '../theme.dart';

class MapCell {
  final CellKey key;
  final Color color;
  final bool selected;
  const MapCell(this.key, this.color, {this.selected = false});
}

/// Dark OpenStreetMap view with grid cells and dots, fitted to the data.
class TagMap extends StatelessWidget {
  final Grid grid;
  final List<MapCell> cells;
  final List<Spot> dots;
  final MapController? controller;

  const TagMap({super.key, required this.grid, required this.cells, this.dots = const [], this.controller});

  static const edirne = LatLng(41.6771, 26.5557);

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final c in cells) ...() {
        final ((s, w), (n, e)) = grid.bounds(c.key);
        return [LatLng(s, w), LatLng(n, e)];
      }(),
      for (final d in dots) LatLng(d.lat, d.lng),
    ];
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: edirne,
        initialZoom: 13,
        initialCameraFit: points.isEmpty
            ? null
            : CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 15.5),
        backgroundColor: _paper,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        _tiles(),
        PolygonLayer(
          polygons: [
            for (final c in cells)
              () {
                final ((s, w), (n, e)) = grid.bounds(c.key);
                return Polygon(
                  points: [LatLng(s, w), LatLng(n, w), LatLng(n, e), LatLng(s, e)],
                  color: c.color,
                  borderColor: c.selected ? kDark : c.color.withValues(alpha: 1),
                  borderStrokeWidth: c.selected ? 2.5 : 1,
                );
              }(),
          ],
        ),
        CircleLayer(
          circles: [
            for (final d in dots)
              CircleMarker(
                point: LatLng(d.lat, d.lng),
                radius: 4,
                color: kDark,
                borderColor: kWhite,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        _attribution,
      ],
    );
  }
}

const _paper = Color(0xFFF2F2EE);

TileLayer _tiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.berkant.tag_stats',
      maxNativeZoom: 19,
    );

const _attribution = RichAttributionWidget(
  alignment: AttributionAlignment.bottomLeft,
  attributions: [TextSourceAttribution('OpenStreetMap katkıda bulunanlar')],
);

/// One ride on a light map: the drive to the customer dashed, the ride itself solid.
class RouteMap extends StatelessWidget {
  final List<LatLng> toPickup;
  final List<LatLng> ride;
  final LatLng? acceptedAt;
  final LatLng? pickup;
  final LatLng? dropoff;

  const RouteMap({
    super.key,
    required this.toPickup,
    required this.ride,
    this.acceptedAt,
    this.pickup,
    this.dropoff,
  });

  @override
  Widget build(BuildContext context) {
    final all = [
      ...toPickup,
      ...ride,
      for (final p in [acceptedAt, pickup, dropoff])
        if (p != null) p,
    ];
    Marker pin(LatLng p, Color fill, IconData icon, [Color iconColor = kDark]) => Marker(
          point: p,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: kDark, width: 2),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
        );

    return FlutterMap(
      options: MapOptions(
        initialCenter: all.isEmpty ? TagMap.edirne : all.first,
        initialZoom: 14,
        initialCameraFit: all.length < 2
            ? null
            : CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(48), maxZoom: 17),
        backgroundColor: _paper,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        _tiles(),
        PolylineLayer(
          polylines: [
            if (toPickup.length > 1)
              Polyline(
                points: toPickup,
                strokeWidth: 4,
                color: kBg,
                pattern: StrokePattern.dashed(segments: const [10, 7]),
              ),
            if (ride.length > 1)
              Polyline(
                points: ride,
                strokeWidth: 5,
                color: kGreen,
                borderStrokeWidth: 2,
                borderColor: kDark,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (acceptedAt != null) pin(acceptedAt!, kWhite, Icons.local_taxi),
            if (pickup != null) pin(pickup!, kGreen, Icons.person),
            if (dropoff != null) pin(dropoff!, kDark, Icons.flag, kWhite),
          ],
        ),
        _attribution,
      ],
    );
  }
}

/// Fills the space with a map, or a hint when there is nothing to show.
class MapOrEmpty extends StatelessWidget {
  final bool empty;
  final String emptyText;
  final Widget map;
  const MapOrEmpty({super.key, required this.empty, required this.emptyText, required this.map});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            map,
            if (empty)
              Container(
                color: kDark.withValues(alpha: 0.7),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(32),
                child: Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(color: kWhite)),
              ),
          ],
        ),
      );
}
