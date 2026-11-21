import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/prediction.dart';

class ClassifierService {
  ClassifierService._internal();
  static final ClassifierService _instance = ClassifierService._internal();
  static ClassifierService get instance => _instance;

  Interpreter? _interpreter;
  List<PlantClass>? _classes;
  bool _isInitialized = false;

  static const int _inputSize = 224;
  static const int _numClasses = 11;

  bool get isReady => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final interpreter = await Interpreter.fromAsset(
      'assets/EfficientNetB0_destilado.tflite',
    );
    final classJson = await rootBundle.loadString('assets/classes.json');
    final classMap = jsonDecode(classJson) as Map<String, dynamic>;
    final classes = List.generate(_numClasses, (i) {
      final entry = classMap[i.toString()] as Map<String, dynamic>;
      return PlantClass(
        index: i,
        id: entry['id'] as String,
        nombre: entry['nombre'] as String,
        cientifico: entry['cientifico'] as String,
      );
    });

    _interpreter = interpreter;
    _classes = classes;
    _isInitialized = true;
  }

  Future<ResultadoInferencia> classify(Uint8List imageBytes) async {
    if (!_isInitialized || _interpreter == null || _classes == null) {
      throw StateError('ClassifierService no inicializado.');
    }

    final stopwatch = Stopwatch()..start();
    final input = _preprocess(imageBytes);
    final output = List.generate(1, (_) => List<double>.filled(_numClasses, 0));
    _interpreter!.run(input, output);
    stopwatch.stop();

    // EfficientNetB0_destilado ya devuelve probabilidades (incluye softmax).
    final probs = output[0];
    final indexed = List.generate(probs.length, (i) => MapEntry(i, probs[i]))
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = indexed.take(3).map((e) => Prediction(
      clase: _classes![e.key],
      confianza: e.value,
    )).toList();

    return ResultadoInferencia(top3: top3, tiempoInferencia: stopwatch.elapsed);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  List<List<List<List<double>>>> _preprocess(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) throw const FormatException('Imagen no válida.');
    final resized = img.copyResize(
      decoded,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // El modelo incluye su propio preprocesamiento y espera RGB en 0..255.
    return [List.generate(_inputSize, (y) => List.generate(_inputSize, (x) {
      final pixel = resized.getPixel(x, y);
      return <double>[pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble()];
    }))];
  }

}
