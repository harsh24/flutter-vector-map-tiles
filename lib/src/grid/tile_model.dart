import 'dart:developer';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:executor_lib/executor_lib.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart';

import '../profiler.dart';
import '../stream/tile_supplier.dart';
import '../stream/translated_tile_request.dart';
import '../tile_identity.dart';
import 'slippy_map_translator.dart';
import 'tile_layer_composer.dart';
import 'tile_layer_model.dart';
import 'tile_zoom.dart';

class VectorTileModel extends ChangeNotifier {
  bool _disposed = false;

  bool get disposed => _disposed;

  final TileIdentity tile;
  final int tileZoomSubstitutionOffset;
  final TileProvider tileProvider;
  final Theme theme;
  final Theme? symbolTheme;
  bool paintBackground;
  final bool showTileDebugInfo;
  late final TileZoomProvider zoomProvider;
  TileZoom lastRenderedZoom = TileZoom.undefined();
  TileIdentity? lastRenderedTile;

  late final TileTranslation defaultTranslation;
  TileTranslation? translation;
  Tileset? tileset;
  late final TimelineTask _firstRenderedTask;
  bool _firstRendered = false;
  bool showLabels = true;
  final symbolState = VectorTileSymbolState();
  late final List<TileLayerModel> layers;

  VectorTileModel(
      this.tileProvider,
      this.theme,
      this.symbolTheme,
      this.tile,
      this.tileZoomSubstitutionOffset,
      ZoomScaleFunction zoomScaleFunction,
      ZoomFunction zoomFunction,
      ZoomFunction zoomDetailFunction,
      this.paintBackground,
      this.showTileDebugInfo) {
    zoomProvider = TileZoomProvider(
        tile, zoomScaleFunction, zoomFunction, zoomDetailFunction);
    layers = TileLayerComposer().compose(this, theme);
    defaultTranslation =
        SlippyMapTranslator(tileProvider.maximumZoom).translate(tile);
    _firstRenderedTask = tileRenderingTask(tile);
  }

  bool get hasData => tileset != null;

  void rendered() {
    if (!_firstRendered) {
      _firstRendered = true;
      _firstRenderedTask.finish();
    }
  }

  void startLoading() {
    _VectorTileModelLoader(this).startLoading();
  }

  void _receiveTile(TileResponse received) {
    final newTranslation = SlippyMapTranslator(tileProvider.maximumZoom)
        .specificZoomTranslation(tile, zoom: received.identity.z);
    tileset = received.tileset;
    translation = newTranslation;
    for (final layer in layers) {
      layer.tileset = tileset;
      layer.translation = translation;
    }
    notifyListeners();
    _notifyLayers();
  }

  TileZoom updateRendering() {
    lastRenderedZoom = zoomProvider.provide();
    lastRenderedTile = translation?.translated;
    return lastRenderedZoom;
  }

  void _notifyLayers() {
    for (final layer in layers) {
      layer.notifyListeners();
    }
  }

  bool hasChanged() =>
      lastRenderedZoom != zoomProvider.provide() ||
      lastRenderedTile != translation?.translated;

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      super.dispose();
      _disposed = true;
      for (final layer in layers) {
        layer.dispose();
      }

      if (!_firstRendered) {
        _firstRendered = true;
        _firstRenderedTask.finish(arguments: {'cancelled': true});
      }
    }
  }

  @override
  void removeListener(ui.VoidCallback listener) {
    if (!_disposed) {
      super.removeListener(listener);
    }
  }
}

class VectorTileSymbolState extends ChangeNotifier {
  bool _disposed = false;
  bool _symbolsReady = false;
  bool get symbolsReady => _symbolsReady;

  set symbolsReady(bool ready) {
    if (ready != _symbolsReady) {
      _symbolsReady = ready;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _disposed = true;
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }
}

class _VectorTileModelLoader {
  final VectorTileModel model;

  _VectorTileModelLoader(this.model);

  void startLoading() async {
    final originalTile = model.tile.normalize();
    final maxZoom = model.tileProvider.maximumZoom;
    var originalLoaded = false;
    final int startZoom =
        max(1, min(originalTile.z, maxZoom) - model.tileZoomSubstitutionOffset);
    for (int z = startZoom; z >= max(startZoom - 10, 1); --z) {
      final request = createTranslatedRequest(_newRequest(), maximumZoom: z);
      final localTile = await model.tileProvider
          .provideLocalCopy(request)
          .swallowCancellation();
      if (model.disposed) {
        break;
      }
      if (localTile != null && localTile.tileset != null) {
        model._receiveTile(localTile);
        originalLoaded = z == originalTile.z;
        if (model.hasData) {
          break;
        }
      }
    }
    if (!originalLoaded && !model.disposed) {
      try {
        var request = _newRequest();
        if (model.tileZoomSubstitutionOffset > 0 && originalTile.z > 0) {
          request = createTranslatedRequest(request,
              maximumZoom:
                  max(0, originalTile.z - model.tileZoomSubstitutionOffset));
        }
        final response = await model.tileProvider.provide(request);
        model._receiveTile(response);
      } catch (e) {
        if (e is SocketException) {
          // nothing to do
        } else if (e is CancellationException) {
          // nothing to do
        } else {
          rethrow;
        }
      }
    }
  }

  TileRequest _newRequest() {
    final zoom = model.zoomProvider.provide();
    return TileRequest(
        tileId: model.tile.normalize(),
        zoom: zoom.zoom,
        zoomDetail: zoom.zoomDetail,
        cancelled: () => model.disposed);
  }
}
