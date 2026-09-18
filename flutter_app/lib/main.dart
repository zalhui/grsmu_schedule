import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

const siteUrl = 'https://rsp-med.grsu.by/Raspisanie/TimeTable/umu.aspx';
const blue = Color.fromARGB(255, 126, 84, 205);

class Lesson {
  final String day, date, time, discipline, staff, auditory;
  Lesson(this.day, this.date, this.time, this.discipline, this.staff,
      this.auditory);
  Map<String, dynamic> toJson() => {
        'day': day,
        'date': date,
        'time': time,
        'discipline': discipline,
        'staff': staff,
        'auditory': auditory
      };
  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
      j['day'] ?? '',
      j['date'] ?? '',
      j['time'] ?? '',
      j['discipline'] ?? '',
      j['staff'] ?? '',
      j['auditory'] ?? '');
  String get type {
    final x = discipline.toLowerCase();
    if (x.startsWith('лек.')) return 'ЛК';
    if (x.startsWith('практ.')) return 'ПЗ';
    if (x.startsWith('лаб.')) return 'ЛР';
    if (x.startsWith('сем.зан.')) return 'СЗ';
    return '';
  }

  String get subject => discipline
      .replaceFirst(RegExp(r'^(лек\.|практ\.\s*зан\.|лаб\.|сем\.зан\.)\s*'), '')
      .trim();
  String get teacher => staff
      .replaceFirst(RegExp(r'^\s*Комиссия:\s*'), '')
      .replaceAll(
          RegExp(r'(Ассистент|ст\.пр\.|проф\.|доц\.|преп\.)\s*',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class Choice {
  final String id, name;
  Choice(this.id, this.name);
}

class Faculty {
  final Choice value;
  final List<StudyForm> forms = [];
  Faculty(this.value);
}

class StudyForm {
  final Choice value;
  final List<StudyCourse> courses = [];
  StudyForm(this.value);
}

class StudyCourse {
  final Choice value;
  final List<Choice> groups = [];
  StudyCourse(this.value);
}

class ScheduleApi {
  final http.Client client = http.Client();
  final Map<String, String> cookies = {};
  Map<String, String> hidden(dom.Document doc) {
    final r = <String, String>{};
    for (final x in doc.querySelectorAll('input[type="hidden"][name]')) {
      r[x.attributes['name']!] = x.attributes['value'] ?? '';
    }
    return r;
  }

  Map<String, String> formValues(dom.Document doc) {
    final r = hidden(doc);
    for (final s in doc.querySelectorAll('select[name]')) {
      final o =
          s.querySelector('option[selected]') ?? s.querySelector('option');
      if (o != null) r[s.attributes['name']!] = o.attributes['value'] ?? '';
    }
    return r;
  }

  void takeCookies(http.Response r) {
    final raw = r.headers['set-cookie'];
    if (raw != null) {
      for (final part in raw.split(',')) {
        final p = part.split(';').first.split('=');
        if (p.length >= 2) cookies[p[0]] = p.sublist(1).join('=');
      }
    }
  }

  Map<String, String> headers() => {
        'User-Agent':
            'Mozilla/5.0 (Android) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
      };
  Future<dom.Document> post(
      dom.Document doc, String field, String value) async {
    final d = formValues(doc);
    d[field] = value;
    d['__EVENTTARGET'] = field;
    d['__EVENTARGUMENT'] = '';
    d['__LASTFOCUS'] = '';
    final r =
        await client.post(Uri.parse(siteUrl), headers: headers(), body: d);
    takeCookies(r);
    if (r.statusCode != 200) {
      throw Exception('Сервер вернул HTTP ${r.statusCode}');
    }
    return html_parser.parse(r.body);
  }

  List<Choice> options(dom.Document d, String name) {
    final s = d.querySelector('select[name="$name"]');
    if (s == null) return [];
    return s
        .querySelectorAll('option')
        .where((o) => (o.attributes['value'] ?? '').isNotEmpty)
        .map((o) => Choice(o.attributes['value']!,
            o.text.trim().replaceAll(RegExp(r'\s+'), ' ')))
        .toList();
  }

  Future<List<Faculty>> catalog() async {
    final r = await client.get(Uri.parse(siteUrl), headers: headers());
    takeCookies(r);
    final initial = html_parser.parse(r.body);
    final out = <Faculty>[];
    for (final f in options(initial, 'ddlFaculty')) {
      var facultyDoc = await post(initial, 'ddlFaculty', f.id);
      final fac = Faculty(f);
      for (final fo in options(facultyDoc, 'ddlDepartment')) {
        final formDoc = await post(facultyDoc, 'ddlDepartment', fo.id);
        final formNode = StudyForm(fo);
        for (final co in options(formDoc, 'ddlCourses')) {
          final courseDoc = await post(formDoc, 'ddlCourses', co.id);
          final course = StudyCourse(co);
          course.groups.addAll(options(courseDoc, 'ddlGroups'));
          formNode.courses.add(course);
        }
        fac.forms.add(formNode);
      }
      out.add(fac);
    }
    return out;
  }

  Future<List<Lesson>> allWeeks(
      String faculty, String form, String course, String group) async {
    final r = await client.get(Uri.parse(siteUrl), headers: headers());
    takeCookies(r);
    var d = html_parser.parse(r.body);
    d = await post(d, 'ddlFaculty', faculty);
    d = await post(d, 'ddlDepartment', form);
    d = await post(d, 'ddlCourses', course);
    d = await post(d, 'ddlGroups', group);
    final week = d.querySelector('select[name="ddlWeek"]');
    if (week == null) throw Exception('Не найден список недель');
    final today = DateTime.now();
    final currentWeek = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final lastWeek = currentWeek.add(const Duration(days: 42));
    final options = week
        .querySelectorAll('option')
        .map((o) => MapEntry(_weekDate(o.attributes['value'] ?? ''), o))
        .where((x) =>
            x.key != null &&
            !x.key!.isBefore(currentWeek) &&
            x.key!.isBefore(lastWeek))
        .toList()
      ..sort((a, b) => a.key!.compareTo(b.key!));
    final result = <Lesson>[];
    for (final entry in options) {
      final o = entry.value;
      final data = formValues(d);
      data['ddlWeek'] = o.attributes['value'] ?? '';
      data['__EVENTTARGET'] = '';
      data['__EVENTARGUMENT'] = '';
      data['__LASTFOCUS'] = '';
      data['btnShowTT'] = 'Показать';
      final resp =
          await client.post(Uri.parse(siteUrl), headers: headers(), body: data);
      takeCookies(resp);
      if (resp.statusCode != 200) continue;
      result.addAll(parseSchedule(html_parser.parse(resp.body)));
    }
    return result;
  }

  DateTime? _weekDate(String value) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})').firstMatch(value.trim());
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  List<Lesson> parseSchedule(dom.Document d) {
    final table = d.querySelector('#TT');
    if (table == null) return [];
    var day = '', date = '';
    final out = <Lesson>[];
    for (final row in table.querySelectorAll('tr')) {
      final dc = row.querySelector('.cell-date');
      if (dc != null) {
        day = dc.querySelector('.day')?.text.trim() ?? day;
        date = dc.querySelector('.date')?.text.trim() ?? date;
      }
      final time = row.querySelector('.cell-time'),
          subject = row.querySelector('.cell-discipline');
      if (time == null ||
          subject == null ||
          row.querySelector('.cell-empty') != null) {
        continue;
      }
      out.add(Lesson(
          day,
          date,
          time.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          subject.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          row.querySelector('.cell-staff')?.text.trim() ?? '',
          row.querySelector('.cell-auditory')?.text.trim() ?? ''));
    }
    return out;
  }
}

class Store {
  static Future<void> save(String id, String name, List<Lesson> x) async {
    final p = await SharedPreferences.getInstance();
    final all =
        jsonDecode(p.getString('schedules') ?? '{}') as Map<String, dynamic>;
    all[id] = {'name': name, 'items': x.map((e) => e.toJson()).toList()};
    await p.setString('schedules', jsonEncode(all));
  }

  static Future<Map<String, List<Lesson>>> read() async {
    final p = await SharedPreferences.getInstance();
    final all =
        jsonDecode(p.getString('schedules') ?? '{}') as Map<String, dynamic>;
    return {
      for (final e in all.entries)
        e.key: (e.value['items'] as List)
            .map((x) => Lesson.fromJson(Map<String, dynamic>.from(x)))
            .toList()
    };
  }

  static Future<Map<String, String>> names() async {
    final p = await SharedPreferences.getInstance();
    final all =
        jsonDecode(p.getString('schedules') ?? '{}') as Map<String, dynamic>;
    return {for (final e in all.entries) e.key: e.value['name'] as String};
  }
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: blue),
          useMaterial3: true),
      home: const Home());
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  Map<String, List<Lesson>> saved = {};
  Map<String, String> names = {};
  String? selected;
  List<Faculty>? catalog;
  bool loading = false;
  String loadingText = 'Загрузка...';
  int dayIndex = 0;
  Offset? swipeStart;
  double dragX = 0;
  final ValueNotifier<double> dragOffset = ValueNotifier(0);
  bool directionLocked = false;
  bool horizontalSwipe = false;
  late final AnimationController swipeController;
  @override
  void initState() {
    super.initState();
    swipeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    refresh();
  }

  @override
  void dispose() {
    swipeController.dispose();
    dragOffset.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    saved = await Store.read();
    names = await Store.names();
    selected ??= (saved.keys.isEmpty ? null : saved.keys.first);
    if (mounted) setState(() {});
  }

  bool past(Lesson x) {
    try {
      final d = DateFormat('dd.MM.yyyy').parse(x.date), now = DateTime.now();
      if (DateUtils.dateOnly(d).isBefore(DateUtils.dateOnly(now))) return true;
      final end = x.time.split('-').last;
      final t = DateFormat('dd.MM.yyyy HH:mm').parse('${x.date} $end');
      return t.isBefore(now);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext c) {
    final items = selected == null ? <Lesson>[] : (saved[selected] ?? []);
    final by = <String, List<Lesson>>{};
    for (final x in items) {
      if (!past(x)) by.putIfAbsent(x.date, () => []).add(x);
    }
    final days = by.entries.toList()
      ..sort((a, b) => _date(a.key).compareTo(_date(b.key)));
    return Scaffold(
      appBar: AppBar(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selected == null ? 'Расписание' : names[selected] ?? '',
                style: const TextStyle(fontSize: 20)),
            Text(
                days.isEmpty
                    ? 'Добавьте расписание'
                    : '${days.first.value.first.day} ${days.first.key}',
                style: const TextStyle(fontSize: 14))
          ])),
      drawer: Drawer(
          child: ListView(children: [
        const DrawerHeader(
            child: Text('Мои расписания', style: TextStyle(fontSize: 28))),
        for (final e in names.entries)
          ListTile(
              title: Text(e.value),
              trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'inspect') inspectSchedule(e.key);
                  },
                  itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                            value: 'inspect', child: Text('🩺 ПРОВЕСТИ ОСМОТР'))
                      ]),
              onTap: () {
                setState(() {
                  selected = e.key;
                  dayIndex = 0;
                });
                Navigator.pop(c);
              }),
        ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Добавить расписание'),
            onTap: () {
              Navigator.pop(c);
              add();
            })
      ])),
      body: Stack(
        children: [
          days.isEmpty
              ? Center(
                  child: ElevatedButton(
                      onPressed: loading ? null : add,
                      child: const Text('Добавить расписание')))
              : _dayPager(days),
          if (loading) _LoadingOverlay(text: loadingText)
        ],
      ),
    );
  }

  DateTime _date(String value) {
    final p = value.split('.');
    return p.length == 3
        ? DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]))
        : DateTime(2100);
  }

  Future<void> add() async {
    if (loading) return;
    if (catalog == null) {
      setState(() {
        loading = true;
        loadingText = 'Загрузка списка групп...';
      });
      try {
        catalog = await ScheduleApi().catalog();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Ошибка каталога: $e')));
        }
      }
      if (mounted) setState(() => loading = false);
    }
    if (catalog != null && mounted) pick();
  }

  void pick() {
    if (catalog!.isEmpty) return;
    Choice? f, fo, co, g;
    showDialog(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, set) {
              List<DropdownMenuItem<Choice>> its(List<Choice> x) => x
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.name)))
                  .toList();
              final fac = catalog!;
              final List<Choice> forms = f == null
                  ? <Choice>[]
                  : fac
                      .firstWhere((x) => x.value.id == f!.id)
                      .forms
                      .map((x) => x.value)
                      .toList();
              final List<Choice> courses = fo == null
                  ? <Choice>[]
                  : fac
                      .firstWhere((x) => x.value.id == f!.id)
                      .forms
                      .firstWhere((x) => x.value.id == fo!.id)
                      .courses
                      .map((x) => x.value)
                      .toList();
              final List<Choice> groups = co == null
                  ? <Choice>[]
                  : fac
                      .firstWhere((x) => x.value.id == f!.id)
                      .forms
                      .firstWhere((x) => x.value.id == fo!.id)
                      .courses
                      .firstWhere((x) => x.value.id == co!.id)
                      .groups;
              return AlertDialog(
                  title: const Text('Добавить группу'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButton<Choice>(
                        isExpanded: true,
                        hint: const Text('Факультет'),
                        value: f,
                        items: fac
                            .map((x) => DropdownMenuItem(
                                value: x.value, child: Text(x.value.name)))
                            .toList(),
                        onChanged: (x) {
                          set(() {
                            f = x;
                            fo = null;
                            co = null;
                            g = null;
                          });
                        }),
                    DropdownButton<Choice>(
                        isExpanded: true,
                        hint: const Text('Форма обучения'),
                        value: fo,
                        items: its(forms),
                        onChanged: f == null
                            ? null
                            : (x) {
                                set(() {
                                  fo = x;
                                  co = null;
                                  g = null;
                                });
                              }),
                    DropdownButton<Choice>(
                        isExpanded: true,
                        hint: const Text('Курс'),
                        value: co,
                        items: its(courses),
                        onChanged: fo == null
                            ? null
                            : (x) {
                                set(() {
                                  co = x;
                                  g = null;
                                });
                              }),
                    DropdownButton<Choice>(
                        isExpanded: true,
                        hint: const Text('Группа'),
                        value: g,
                        items: its(groups),
                        onChanged: co == null
                            ? null
                            : (x) {
                                set(() => g = x);
                              })
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: g == null
                            ? null
                            : () {
                                Navigator.pop(c);
                                download(f!, fo!, co!, g!);
                              },
                        child: const Text('Загрузить'))
                  ]);
            }));
  }

  Future<void> download(Choice f, Choice fo, Choice co, Choice g) async {
    if (loading) return;
    setState(() {
      loading = true;
      loadingText = 'Загрузка расписания...';
    });
    try {
      final x = await ScheduleApi().allWeeks(f.id, fo.id, co.id, g.id);
      await Store.save(g.id, g.name, x);
      await refresh();
      if (mounted) {
        setState(() {
          selected = g.id;
          dayIndex = 0;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Расписание сохранено')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> inspectSchedule(String groupId) async {
    if (loading) return;
    setState(() {
      loading = true;
      loadingText = 'Проверка обновлений...';
    });
    try {
      catalog ??= await ScheduleApi().catalog();
      Faculty? faculty;
      StudyForm? form;
      StudyCourse? course;
      Choice? group;
      for (final f in catalog!) {
        for (final fo in f.forms) {
          for (final co in fo.courses) {
            for (final g in co.groups) {
              if (g.id == groupId) {
                faculty = f;
                form = fo;
                course = co;
                group = g;
              }
            }
          }
        }
      }
      if (faculty == null || form == null || course == null || group == null) {
        throw Exception('Группа не найдена в каталоге');
      }
      final updated = await ScheduleApi()
          .allWeeks(faculty.value.id, form.value.id, course.value.id, group.id);
      final oldItems = saved[groupId] ?? <Lesson>[];
      final oldJson = jsonEncode(oldItems.map((x) => x.toJson()).toList());
      final newJson = jsonEncode(updated.map((x) => x.toJson()).toList());
      if (oldJson == newJson) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Обновлений нет')));
        }
      } else {
        await Store.save(groupId, names[groupId] ?? group.name, updated);
        await refresh();
        if (mounted) {
          setState(() {
            selected = groupId;
            dayIndex = 0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Расписание успешно обновлено')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка проверки: $e')));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Widget _dayPager(List<MapEntry<String, List<Lesson>>> days) {
    return LayoutBuilder(builder: (context, constraints) {
      return ClipRect(
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: (event) => _onPointerMove(event, days.length),
          onPointerUp: (event) =>
              _onPointerUp(event, days.length, constraints.maxWidth),
          onPointerCancel: (_) => _cancelSwipe(),
          child: ValueListenableBuilder<double>(
            valueListenable: dragOffset,
            builder: (context, offset, child) {
              final current = dayIndex.clamp(0, days.length - 1);
              final next = offset < 0 ? current + 1 : current - 1;
              final children = <Widget>[
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: DayPage(
                        key: ValueKey(days[current].key),
                        day: days[current].key,
                        items: days[current].value),
                  ),
                ),
              ];
              if (horizontalSwipe &&
                  offset != 0 &&
                  next >= 0 &&
                  next < days.length) {
                children.add(Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(
                        offset +
                            (offset < 0
                                ? constraints.maxWidth
                                : -constraints.maxWidth),
                        0),
                    child: DayPage(
                        key: ValueKey(days[next].key),
                        day: days[next].key,
                        items: days[next].value),
                  ),
                ));
              }
              return Stack(children: children);
            },
          ),
        ),
      );
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (swipeController.isAnimating) return;
    swipeStart = event.position;
    _setDragOffset(0);
    directionLocked = false;
    horizontalSwipe = false;
  }

  void _onPointerMove(PointerMoveEvent event, int count) {
    final start = swipeStart;
    if (start == null || swipeController.isAnimating) return;
    final delta = event.position - start;
    if (!directionLocked && delta.distance >= 12) {
      directionLocked = true;
      horizontalSwipe = delta.dx.abs() > delta.dy.abs() * 1.25;
    }
    if (!horizontalSwipe) return;
    final next = dayIndex + (delta.dx < 0 ? 1 : -1);
    final effective = next >= 0 && next < count ? delta.dx : delta.dx * 0.2;
    _setDragOffset(effective);
  }

  void _onPointerUp(PointerUpEvent event, int count, double width) {
    final start = swipeStart;
    if (start == null) return;
    final delta = event.position - start;
    if (!horizontalSwipe) {
      _cancelSwipe();
      return;
    }
    final next = dayIndex + (delta.dx < 0 ? 1 : -1);
    final changePage = dragX.abs() > width * 0.25 && next >= 0 && next < count;
    _animateSwipe(changePage ? (dragX < 0 ? -width : width) : 0,
        changePage ? next : null);
  }

  void _cancelSwipe() {
    swipeStart = null;
    directionLocked = false;
    horizontalSwipe = false;
    if (dragX != 0) _setDragOffset(0);
  }

  void _animateSwipe(double target, int? nextPage) {
    final animation = Tween<double>(begin: dragX, end: target).animate(
        CurvedAnimation(parent: swipeController, curve: Curves.easeOutCubic));
    void update() {
      _setDragOffset(animation.value);
    }

    void finish(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeListener(update);
      animation.removeStatusListener(finish);
      swipeController.reset();
      if (mounted) {
        setState(() {
          if (nextPage != null) dayIndex = nextPage;
          _setDragOffset(0);
          swipeStart = null;
          directionLocked = false;
          horizontalSwipe = false;
        });
      }
    }

    animation.addListener(update);
    animation.addStatusListener(finish);
    swipeController.forward(from: 0);
  }

  void _setDragOffset(double value) {
    dragX = value;
    dragOffset.value = value;
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String text;
  const _LoadingOverlay({required this.text});
  @override
  Widget build(BuildContext c) => Positioned.fill(
        child: Material(
          color: Colors.black26,
          child: Center(
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator()),
                    const SizedBox(height: 14),
                    Text(text),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class DayPage extends StatelessWidget {
  final String day;
  final List<Lesson> items;
  const DayPage({super.key, required this.day, required this.items});
  @override
  Widget build(BuildContext c) =>
      ListView(padding: const EdgeInsets.all(12), children: [
        Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
                color: blue, borderRadius: BorderRadius.circular(16)),
            child: Text(day,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold))),
        for (final x in items) _lesson(x),
      ]);
  Widget _lesson(Lesson x) {
    final times = x.time.split('-');
    final start = times.isNotEmpty ? times.first.trim() : x.time;
    final end = times.length > 1 ? times.last.trim() : '';
    final subject = x.type.isEmpty ? x.subject : '${x.subject} (${x.type})';
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 70,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(start, style: const TextStyle(fontSize: 17)),
                    if (end.isNotEmpty)
                      Text(end, style: const TextStyle(fontSize: 17))
                  ])),
          Container(
              width: 8,
              height: 86,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                  color: typeColor(x.type),
                  borderRadius: BorderRadius.circular(5))),
          Expanded(
              child: Card(
                  margin: EdgeInsets.zero,
                  color: const Color(0xffe2e9ed),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(subject,
                                      softWrap: true,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  if (x.auditory.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(x.auditory,
                                            softWrap: true,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black54)))
                                ])),
                            if (x.teacher.isNotEmpty)
                              SizedBox(
                                  width: 112,
                                  child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(x.teacher,
                                          softWrap: true,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black54)))),
                          ]))))
        ]));
  }
}

Color typeColor(String t) => t == 'ЛК'
    ? const Color.fromARGB(255, 149, 231, 152)
    : t == 'ПЗ'
        ? const Color.fromARGB(255, 103, 199, 255)
        : t == 'ЛР'
            ? const Color.fromARGB(255, 255, 136, 128)
            : t == 'СЗ'
                ? const Color.fromARGB(255, 240, 249, 116)
                : Colors.grey;
