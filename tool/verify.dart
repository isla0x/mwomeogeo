// Socket-free verification for restricted environments. The normal suite is in test/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/main.dart' show MwomeogeoApp;
import 'package:mwomeogeo/store.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    stderr.writeln(details);
  };
  try {
    // This executable is a standalone verification harness.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('mwomeogeo-verify-');
    final store = MealStore(await SharedPreferences.getInstance(), dir);
    await store.load();
    final source = File('${dir.path}/camera.jpg');
    await source.writeAsBytes([1, 2, 3, 4]);
    await store.setName('채은');
    await store.saveMeal(
      source: source,
      meal: 1,
      caption: '한 끼의 안부',
      tableIds: ['local-couple', 'local-family'],
    );
    await source.delete();
    final post = store.localPosts.single;
    check(
      await File('${dir.path}/${post.photo}').exists(),
      'Photo must survive removal of camera cache',
    );
    await store.react(post, 'heart');
    await store.react(post, 'yum');
    await store.react(post, 'heart');
    await store.addComment(post, '잘 챙겨 먹어!');
    final restarted = MealStore(await SharedPreferences.getInstance(), dir);
    await restarted.load();
    check(
      restarted.localPosts.length == 1 && !restarted.demo,
      'Record must survive restart',
    );
    check(
      restarted.localPosts.single.reactions.single == 'local:yum',
      'Reactions must toggle and persist',
    );
    check(
      restarted.localPosts.single.comments.single.text == '잘 챙겨 먹어!',
      'Comments must persist',
    );
    restarted.selectTable('local-family');
    check(
      restarted.postsOn(DateTime.now()).length == 1,
      'Cross-post must be visible in both local tables',
    );
    check(
      restarted.postsOn(DateTime(2025, 11, 20)).isEmpty,
      'Calendar must not fabricate historical records',
    );
    await restarted.delete(restarted.localPosts.single);
    check(
      !await File('${dir.path}/${post.photo}').exists(),
      'Deleting a record must remove its private photo',
    );
    final reloaded = MealStore(await SharedPreferences.getInstance(), dir);
    await reloaded.load();
    check(reloaded.localPosts.isEmpty, 'Deleted metadata must remain deleted');
    await reloaded.setDemo(true);
    final demo = reloaded.postsOn(DateTime.now(), meal: 1).first;
    await reloaded.react(demo, 'heart');
    check(
      reloaded.postsOn(DateTime.now(), meal: 1).first.reactions.isNotEmpty,
      'Preview reaction must remain visible',
    );
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'));
    await font.load();
    final key = GlobalKey();
    Future<void> mount(Size size, {double scale = 1}) async {
      runApp(
        Align(
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: RepaintBoundary(
                key: key,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    devicePixelRatio: 1,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: MwomeogeoApp(store: reloaded),
                ),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await WidgetsBinding.instance.endOfFrame;
    }

    Future<void> shot(String name) async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/previews').create(recursive: true);
      await File('build/previews/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    Future<void> tap(String label) async {
      Element? found;
      void visit(Element element) {
        if (element.widget is Text && (element.widget as Text).data == label) {
          found = element;
        }
        element.visitChildren(visit);
      }

      visit(key.currentContext! as Element);
      check(found != null, 'Missing action: $label');
      bool tapped = false;
      found!.visitAncestorElements((e) {
        final w = e.widget;
        if (w is InkWell && w.onTap != null) {
          w.onTap!();
          tapped = true;
          return false;
        }
        if (w is ButtonStyleButton && w.onPressed != null) {
          w.onPressed!();
          tapped = true;
          return false;
        }
        return true;
      });
      check(tapped, 'No handler for $label');
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    await mount(const Size(390, 844));
    await shot('01-feed');
    await tap('모아보기');
    await shot('02-calendar');
    await tap('우리 식탁');
    await reloaded.setDemo(false);
    await shot('03-empty');
    await tap('한 끼 남기기');
    await shot('04-camera');
    // Reset the navigation tree before checking a smaller, text-scaled display.
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await reloaded.setDemo(true);
    await mount(const Size(320, 568), scale: 1.3);
    await shot('05-small-text');
    check(errors.isEmpty, 'Rendering errors: ${errors.join('; ')}');
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'checks': [
          'photo isolation',
          'restart persistence',
          'cross-post',
          'reactions',
          'comments',
          'date filtering',
          'deletion',
          'preview state',
          'feed render',
          'calendar render',
          'empty render',
          'capture render',
          'small display with large text',
        ],
        'screenshots': 'build/previews',
      }),
    );
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    exit(1);
  }
}
