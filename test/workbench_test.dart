import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jlens/core/workbench.dart';

class MemoryStorage implements HistoryStorage {
  String? data;
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('read failed');
    return data;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('quota exceeded');
    data = value;
  }
}

class SlowStorage extends MemoryStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  final writes = <String>[];
  @override
  Future<void> write(String value) async {
    writes.add(value);
    if (writes.length == 1) {
      started.complete();
      await release.future;
    }
    await super.write(value);
  }
}

void main() {
  test('慢存储期间合并写入，最终保存最新浏览状态与历史修改', () async {
    final storage = SlowStorage();
    final model = Workbench(storage);
    await model.initialize();
    model.parse();
    await storage.started.future;
    for (var index = 0; index < 10; index++) {
      model.select(index.isEven ? r'$.request_id' : r'$.success');
      model.rename(model.history.single, '记录 $index');
    }
    final flushed = model.flush();
    storage.release.complete();
    await flushed;
    expect(storage.writes, hasLength(2));
    final saved =
        (jsonDecode(storage.data!) as List<Object?>).single
            as Map<String, Object?>;
    expect(saved['selected'], r'$.success');
    expect(saved['title'], '记录 9');
    model.dispose();
  });

  test('成功保存不重复刷新页面，保存失败及恢复只通知错误状态变化', () async {
    final storage = MemoryStorage();
    final model = Workbench(storage);
    await model.initialize();
    model.parse();
    await model.flush();
    var updates = 0;
    model.addListener(() => updates++);
    await model.flush();
    expect(updates, 0);
    storage.failWrite = true;
    await model.flush();
    expect(updates, 1);
    expect(model.storageError, isNotNull);
    await model.flush();
    expect(updates, 1);
    storage.failWrite = false;
    await model.flush();
    expect(updates, 2);
    expect(model.storageError, isNull);
    model.dispose();
  });

  test('重新选择已选节点仍能展开被折叠的祖先，切换历史不丢浏览状态', () async {
    final model = Workbench(MemoryStorage());
    await model.initialize();
    model.edit('{"items":[{"id":1}]}');
    model.parse();
    model.select(r'$.items[0].id');
    model.toggle(r'$.items');
    model.select(r'$.items[0].id');
    expect(model.expanded, contains(r'$.items'));
    final first = model.history.single;
    model.edit('{"other":2}');
    model.parse();
    model.restore(first);
    expect(model.selectedPath, r'$.items[0].id');
    expect(model.expanded, contains(r'$.items[0]'));
    await model.flush();
    model.dispose();
  });

  test('历史恢复原文、视图、焦点、展开节点及选中路径并去重', () async {
    final storage = MemoryStorage();
    final model = Workbench(storage);
    await model.initialize();
    model.edit("{'items': [{'id': 9007199254740993}], 'active': True}");
    expect(model.parse(), isTrue);
    model.setView(LensView.table);
    model.focus(r'$.items');
    model.select(r'$.items[0].id');
    final first = model.history.single;
    model.edit('{"other": 2}');
    model.parse();
    model.restore(first);
    expect(model.view, LensView.table);
    expect(model.selectedPath, r'$.items[0].id');
    expect(model.focusPath, r'$.items');
    expect(model.expanded, contains(r'$.items[0]'));
    model.parse();
    expect(model.history, hasLength(2));
    model.rename(first, '接口返回');
    await model.flush();
    model.dispose();
    final restored = Workbench(storage);
    await restored.initialize();
    expect(restored.history.first.title, '接口返回');
    expect(restored.draft, first.raw);
    expect(restored.selectedPath, r'$.items[0].id');
    expect(restored.view, LensView.table);
    restored.dispose();
  });
  test('无效输入保留上次解析结果且不新增历史', () async {
    final model = Workbench(MemoryStorage());
    await model.initialize();
    model.parse();
    final previous = model.document;
    model.edit('{"bad":');
    expect(model.parse(), isFalse);
    expect(model.document, same(previous));
    expect(model.history, hasLength(1));
    expect(model.dirty, isTrue);
    expect(model.parseError, isNotNull);
    model.dispose();
  });
  test('删除、清空后不因继续浏览重新保存已删除记录', () async {
    final model = Workbench(MemoryStorage());
    await model.initialize();
    model.parse();
    model.delete(model.history.single);
    model.setView(LensView.source);
    await model.flush();
    expect(model.history, isEmpty);
    model.parse();
    model.clearHistory();
    await model.flush();
    expect(model.document, isNotNull);
    expect(model.history, isEmpty);
    model.dispose();
  });
  test('存储失败可见，读取失败不会覆盖原存储', () async {
    final storage = MemoryStorage()
      ..data = 'broken'
      ..failRead = true;
    final model = Workbench(storage);
    await model.initialize();
    model.parse();
    await model.flush();
    expect(model.storageError, contains('历史读取失败'));
    expect(storage.data, 'broken');
    model.dispose();
    final failing = Workbench(MemoryStorage()..failWrite = true);
    await failing.initialize();
    failing.parse();
    await failing.flush();
    expect(failing.storageError, contains('历史保存失败'));
    failing.dispose();
  });
  test('保留最近 50 条，重复查看更新顺序', () async {
    final model = Workbench(MemoryStorage());
    await model.initialize();
    for (var i = 0; i < 55; i++) {
      model.edit('{"id":$i}');
      model.parse();
    }
    expect(model.history, hasLength(50));
    expect(model.history.last.raw, '{"id":5}');
    model.edit('{"id":6}');
    model.parse();
    expect(model.history.first.raw, '{"id":6}');
    await model.flush();
    model.dispose();
  });
}
