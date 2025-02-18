import 'dart:math';

import 'package:flutter_map/plugin_api.dart';

class TileIdentity extends CustomPoint<int> {
  final int z;

  TileIdentity(int z, int x, int y)
      : z = z.toInt(),
        super(x, y);

  @override
  operator ==(other) =>
      other is TileIdentity && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => key();

  String key() => 'z=$z,x=$x,y=$y';

  bool isValid() {
    if (z < 0 || x < 0 || y < 0) {
      return false;
    }
    final max = pow(2, z).toInt();
    return x < max && y < max;
  }

  TileIdentity normalize() {
    final maxX = pow(2, z).toInt();
    if (x >= 0 && x < maxX) {
      return this;
    }
    var normalizedX = x;
    while (normalizedX >= maxX) {
      normalizedX -= maxX;
    }
    while (normalizedX < 0) {
      normalizedX += maxX;
    }
    return TileIdentity(z, normalizedX, y);
  }

  bool overlaps(TileIdentity other) {
    return contains(other) || other.contains(this);
  }

  bool contains(TileIdentity other) {
    final zoomDifference = other.z - z;
    if (zoomDifference == 0) {
      return this == other;
    } else if (zoomDifference < 0) {
      return false;
    }
    final divisor = pow(2, zoomDifference).toInt();
    final translatedX = other.x ~/ divisor;
    final translatedY = other.y ~/ divisor;
    return translatedX == x && translatedY == y;
  }
}
