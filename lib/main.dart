import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:time_range_picker/time_range_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

void main() => runApp(const SwitchApp());

const DefaultHost = "192.168.178.50";
const Prefix = "api/v1";
const HttpTimeout = Duration(seconds: 4);

class BadRequest implements Exception {
  String message;
  BadRequest(this.message);
}

class LichterketteAnimation {
  int idx;
  String name;
  bool color;
  bool speed;

  LichterketteAnimation(
      {this.idx = 0, this.name = "", this.color = false, this.speed = false});

  factory LichterketteAnimation.fromJson(Map<String, dynamic> json) {
    return LichterketteAnimation(
        idx: json['idx'],
        name: json['name'],
        color: json['color'],
        speed: json['speed']);
  }
}

class Lichterkette {
  bool on = false;
  int brightness = 0;
  int speed = 0;
  int animationIdx = 0;
  int maxBrightness = 0;
  int minSpeed = 0;
  int maxSpeed = 0;
  int maxNofTimeFrames = 0;
  List<LichterketteAnimation> animations = [];
  Color color;
  bool timecontrol = false;
  List<TimeRange> times = [];

  LichterketteAnimation currentAnimation() {
    return animations[animationIdx];
  }

  Lichterkette(
      {required this.on,
      required this.brightness,
      required this.speed,
      required this.animationIdx,
      required this.maxBrightness,
      required this.minSpeed,
      required this.maxSpeed,
      required this.maxNofTimeFrames,
      required this.animations,
      required this.color,
      required this.timecontrol,
      required this.times});

  factory Lichterkette.fromJson(Map<String, dynamic> json) {
    List<LichterketteAnimation> animations = [];
    for (Map<String, dynamic> animationJson in json['available']) {
      animations.add(LichterketteAnimation.fromJson(animationJson));
    }
    List<TimeRange> times = [];
    for (Map<String, dynamic> timeRangeJson in json['time']) {
      times.add(TimeRange(
          startTime: TimeOfDay(
              hour: timeRangeJson['startHour'],
              minute: timeRangeJson['startMinute']),
          endTime: TimeOfDay(
              hour: timeRangeJson['endHour'],
              minute: timeRangeJson['endMinute'])));
    }
    return Lichterkette(
      on: json['on'],
      brightness: json['brightness'],
      speed: json['speed'],
      animationIdx: json['animation'],
      maxBrightness: json['maxBrightness'],
      minSpeed: json['minSpeed'],
      maxSpeed: json['maxSpeed'],
      maxNofTimeFrames: json['maxNofTimeFrames'],
      animations: animations,
      color: Color.fromARGB(
          255, json['color'][0], json['color'][1], json['color'][2]),
      timecontrol: json['timecontrol'],
      times: times,
    );
  }
}

Future<Uri> getHostname() async {
  final prefs = await SharedPreferences.getInstance();
  String hostname = prefs.getString('hostname') ?? '127.0.0.1';
  if (hostname == null) {
    return Uri.http("127.0.0.1");
  }
  return Uri.http(hostname);
}

class ParentProvider extends InheritedWidget {
  final Lichterkette lichterkette;
  final void Function() updateLichterkette;
  final void Function() refresh;
  final void Function() refreshSwitchState;
  final Widget child;

  const ParentProvider(
      {key,
      required this.lichterkette,
      required this.updateLichterkette,
      required this.refresh,
      required this.refreshSwitchState,
      required this.child})
      : super(key: key, child: child);

  @override
  bool updateShouldNotify(ParentProvider oldWidget) {
    return true;
  }

  static ParentProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ParentProvider>()!;
  }
}

class SwitchApp extends StatefulWidget {
  const SwitchApp({super.key});

  @override
  State<SwitchApp> createState() => _SwitchAppState();
}

class InitialParentProvider extends InheritedWidget {
  final void Function() refresh;
  final Widget child;

  const InitialParentProvider({key, required this.refresh, required this.child})
      : super(key: key, child: child);

  @override
  bool updateShouldNotify(InitialParentProvider oldWidget) {
    return true;
  }

  static InitialParentProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<InitialParentProvider>()!;
  }
}

class _SwitchAppState extends State<SwitchApp> {
  // This described a future Lichterkette that has been (or will be) fetched from remote!
  late Future<Lichterkette> futureLichterkette;
  // This describes the current state of the Lichterkette, modified locally in this app.
  Lichterkette? lichterkette;

  bool _connected = false;

  int _selectedIndex = 0;
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void fetchLichterkette() {
    _connected = false;
    futureLichterkette = () async {
      final hostname = await getHostname();
      final response = await http
          .get(hostname.replace(path: '$Prefix/status'))
          .timeout(HttpTimeout);

      if (response.statusCode == 200) {
        // If the server did return a 200 OK response,
        // then parse the JSON.
        lichterkette = Lichterkette.fromJson(jsonDecode(response.body));
        setState(() {
          _connected = true;
          updateTimepoint(); // last successful interaction
        });
        return lichterkette!;
      } else {
        // If the server did not return a 200 OK response,
        // then throw an exception.
        throw BadRequest('Failed to load lichterkette');
      }
    }();
  }

  Timer? timer;

  @override
  void initState() {
    super.initState();
    fetchLichterkette();
    timer = Timer.periodic(const Duration(seconds: 60), (Timer t) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  DateTime? _dateTime;
  void updateTimepoint() {
    _dateTime = DateTime.now();
  }

  void updateLichterkette() {
    setState(() {
      updateTimepoint(); // last successful interaction
    });
  }

  void refresh() {
    setState(() {
      fetchLichterkette();
    });
  }

  void refreshSwitchState() {
    // Delay by a few milliseconds, so on state has been changed appriately.
    Future.delayed(const Duration(milliseconds: 500), () async {
      final hostname = await getHostname();
      final response = await http
          .get(hostname.replace(path: '$Prefix/switch'))
          .timeout(HttpTimeout);

      if (response.statusCode == 200) {
        // If the server did return a 200 OK response, then parse the JSON.
        final decodedResponse = jsonDecode(response.body);
        setState(() {
          lichterkette?.on = decodedResponse['on'];
        });
      } else {
        // What to do? Perhaps ignore?
        //throw BadRequest('Failed to load lichterkette');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> widgetOptions = <Widget>[
      FutureBuilder<Lichterkette>(
        // we wait for the future Lichterkette (if any update is in progress)
        future: futureLichterkette,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              // We do not use the data of the snapshot, but of the local
              // copy!
              assert(lichterkette != null);

              return ParentProvider(
                  lichterkette: lichterkette!,
                  updateLichterkette: updateLichterkette,
                  refresh: refresh,
                  refreshSwitchState: refreshSwitchState,
                  child: ListView(children: <Widget>[
                    Row(
                      children: [LightColorPicker(), OnOffSwitch()],
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    ),
                    AnimationRadioGroup(),
                    BrightnessSlider(),
                    SpeedSlider(),
                  ]));
            } else if (snapshot.hasError) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    IconButton(
                      icon:
                          const Icon(Icons.refresh_sharp, color: Colors.amber),
                      iconSize: 60,
                      tooltip: 'Refresh',
                      onPressed: refresh,
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 10.0),
                        child: Text(
                            "Failed to connect to Lichterkette!\nPlease check internet connection and settings and try again."))
                  ]));
            }
          }

          // By default, show a loading spinner.
          return const CircularProgressIndicator();
        },
      ),
      FutureBuilder<Lichterkette>(
        // we wait for the future Lichterkette (if any update is in progress)
        future: futureLichterkette,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              // We do not use the data of the snapshot, but of the local
              // copy!
              assert(lichterkette != null);
              return ParentProvider(
                  lichterkette: lichterkette!,
                  updateLichterkette: updateLichterkette,
                  refresh: refresh,
                  refreshSwitchState: refreshSwitchState,
                  child: ListView.builder(
                      itemCount: lichterkette!.times.length + 1,
                      itemBuilder: (BuildContext context, int index) {
                        if (index == 0) {
                          return const TimeControlSwitch();
                        } else {
                          TimeRange range = lichterkette!.times[index - 1];
                          intl.NumberFormat formatter = intl.NumberFormat("00");
                          return ListTile(
                              leading: const Icon(Icons.list),
                              trailing: RemoveTimeIntervalButton(
                                correspondingTimeRange: range,
                              ),
                              title: Text(
                                  "${formatter.format(range.startTime.hour)}:${formatter.format(range.startTime.minute)} - ${formatter.format(range.endTime.hour)}:${formatter.format(range.endTime.minute)}",
                                  style: TextStyle(fontSize: 18)));
                        }
                      }));
            } else if (snapshot.hasError) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                    IconButton(
                      icon:
                          const Icon(Icons.refresh_sharp, color: Colors.amber),
                      iconSize: 60,
                      tooltip: 'Refresh',
                      onPressed: refresh,
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 10.0),
                        child: Text(
                            "Failed to connect to Lichterkette!\nPlease check internet connection and settings and try again."))
                  ]));
            }
          }
          // By default, show a loading spinner.
          return const CircularProgressIndicator();
        },
      ),
      ListView(
        children: [
          InitialParentProvider(
            refresh: refresh,
            child: HostnameEdit(),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
            child: FutureBuilder<Lichterkette>(
              // we wait for the future Lichterkette (if any update is in progress)
              future: futureLichterkette,
              builder: (context, snapshot) {
                Duration duration = Duration.zero;
                if (_dateTime != null) {
                  duration = DateTime.now().difference(_dateTime!);
                }
                String unit;
                int value = 0;
                if (duration.inHours > 0) {
                  unit = 'h';
                  value = duration.inHours;
                } else if (duration.inMinutes > 0) {
                  unit = 'min';
                  value = duration.inMinutes;
                } else {
                  unit = 's';
                  value = duration.inSeconds;
                }
                if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasData) {
                    return Text("Status: Connected ($value$unit ago)",
                        style: TextStyle(color: Colors.green));
                  } else if (snapshot.hasError) {
                    return const Text("Status: Disconnected",
                        style: TextStyle(color: Colors.redAccent));
                  }
                }
                return const Text("Status: Connecting...",
                    style: TextStyle(color: Colors.blue));
              },
            ),
          ),
          const VersionInfo(),
        ],
      )
    ];
    return MaterialApp(
      title: 'Lichterkette',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Lichterkette'),
          actions: <Widget>[
            FutureBuilder<Lichterkette>(
              // we wait for the future Lichterkette (if any update is in progress)
              future: futureLichterkette,
              builder: (context, snapshot) {
                // We're not interested in the snapshot itself, but only if
                // the future has ended.
                if (snapshot.hasData || snapshot.hasError) {
                  return IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: refresh,
                  );
                }

                return const IconButton(
                  icon: Icon(Icons.circle_outlined),
                  tooltip: 'Refresh',
                  onPressed: null,
                );
              },
            ),
          ],
        ),
        body: Center(child: widgetOptions[_selectedIndex]),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.lightbulb),
              label: 'Light',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.schedule),
              label: 'Schedule',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.blue[800],
          onTap: _onItemTapped,
        ),
        floatingActionButton: _selectedIndex == 1 && _connected
            ? ParentProvider(
                lichterkette: lichterkette!,
                updateLichterkette: updateLichterkette,
                refresh: refresh,
                refreshSwitchState: refreshSwitchState,
                child: const AddTimeIntervalButton())
            : null,
      ),
    );
  }
}

class OnOffSwitch extends StatefulWidget {
  const OnOffSwitch({super.key});

  @override
  State<OnOffSwitch> createState() => _OnOffSwitchState();
}

class _OnOffSwitchState extends State<OnOffSwitch> {
  bool _waiting = false;
  void onPressed() {
    setState(() {
      _waiting = true;
    });

    var body = jsonEncode({'on': !ParentProvider.of(context).lichterkette.on});
    () async {
      try {
        final hostname = await getHostname();
        var response = await http
            .post(hostname.replace(path: '$Prefix/switch'), body: body)
            .timeout(HttpTimeout);
        var decodedResponse = jsonDecode(response.body);

        if (mounted) {
          ParentProvider.of(context).lichterkette.on = decodedResponse['on'];
          ParentProvider.of(context).updateLichterkette();
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw BadRequest("Invalid parameters!");
        }
      } on BadRequest {
        print("BAD REQUEST!");
        if (mounted) {
          final snackBar = SnackBar(
            content:
                const Text("An error occurred! Please try again or refresh."),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                ParentProvider.of(context).refresh();
              },
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } catch (e) {
        print(e.toString());
        if (mounted) {
          final snackBar = SnackBar(
            content: const Text(
                "Failed to communicate to Lichterkette. Refreshing..."),
            action: SnackBarAction(
              label: 'Close',
              onPressed: () {},
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          ParentProvider.of(context).refresh();
        }
      } finally {
        setState(() {
          _waiting = false;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
        child: IconButton(
          icon: Icon(
            Icons.power_settings_new,
            color: ParentProvider.of(context).lichterkette.on
                ? Colors.green
                : Colors.red,
          ),
          iconSize: 55,
          onPressed: onPressed,
        ));
  }
}

class TimeControlSwitch extends StatefulWidget {
  const TimeControlSwitch({super.key});

  @override
  State<TimeControlSwitch> createState() => _TimeControlSwitchSwitchState();
}

class _TimeControlSwitchSwitchState extends State<TimeControlSwitch> {
  bool _waiting = false;
  void onChanged(bool value) {
    setState(() {
      _waiting = true;
    });

    var body = jsonEncode({'timecontrol': value});
    () async {
      try {
        final hostname = await getHostname();
        var response = await http
            .post(hostname.replace(path: '$Prefix/times'), body: body)
            .timeout(HttpTimeout);

        var decodedResponse = jsonDecode(response.body);

        if (mounted) {
          ParentProvider.of(context).lichterkette.timecontrol =
              decodedResponse['timecontrol'];
          ParentProvider.of(context).updateLichterkette();
          ParentProvider.of(context).refreshSwitchState();
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw BadRequest("Invalid parameters!");
        }
      } on BadRequest {
        print("BAD REQUEST!");
        if (mounted) {
          final snackBar = SnackBar(
            content:
                const Text("An error occurred! Please try again or refresh."),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                ParentProvider.of(context).refresh();
              },
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } catch (e) {
        print(e.toString());
        if (mounted) {
          final snackBar = SnackBar(
            content: const Text(
                "Failed to communicate to Lichterkette. Refreshing..."),
            action: SnackBarAction(
              label: 'Close',
              onPressed: () {},
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          ParentProvider.of(context).refresh();
        }
      } finally {
        setState(() {
          _waiting = false;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        onChanged(!ParentProvider.of(context).lichterkette.timecontrol);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          children: <Widget>[
            const Expanded(
                child: Text(
              "Time control",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            )),
            Switch(
              value: ParentProvider.of(context).lichterkette.timecontrol,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class AddTimeIntervalButton extends StatefulWidget {
  const AddTimeIntervalButton({super.key});

  @override
  State<AddTimeIntervalButton> createState() => _AddTimeIntervalButtonState();
}

class _AddTimeIntervalButtonState extends State<AddTimeIntervalButton> {
  bool _waiting = false;
  void onPressed() {
    setState(() {
      _waiting = true;
    });

    () async {
      try {
        final selectedTimeRange = await showTimeRangePicker(
          context: context,
          start: TimeOfDay.now(),
          interval: const Duration(minutes: 30),
          minDuration: const Duration(minutes: 30),
          use24HourFormat: true,
          ticks: 24,
          ticksColor: Colors.white,
          snap: true,
          rotateLabels: false,
          labels: ["24 h", "3 h", "6 h", "9 h", "12 h", "15 h", "18 h", "21 h"]
              .asMap()
              .entries
              .map((e) {
            return ClockLabel.fromIndex(idx: e.key, length: 8, text: e.value);
          }).toList(),
          labelStyle: const TextStyle(fontSize: 18, color: Colors.black),
          clockRotation: 180.0,
        );
        if (selectedTimeRange != null && mounted) {
          List<TimeRange> oldTimes = [
            ...ParentProvider.of(context).lichterkette.times
          ];
          oldTimes.add(selectedTimeRange);
          List<Map<String, int>> convTimes = [];
          for (TimeRange timeRange in oldTimes) {
            convTimes.add({
              'startHour': timeRange.startTime.hour,
              'startMinute': timeRange.startTime.minute,
              'endHour': timeRange.endTime.hour,
              'endMinute': timeRange.endTime.minute,
            });
          }

          var body = jsonEncode({'time': convTimes});

          final hostname = await getHostname();
          var response = await http
              .post(hostname.replace(path: '$Prefix/times'), body: body)
              .timeout(HttpTimeout);
          var decodedResponse = jsonDecode(response.body);

          List<TimeRange> newTimes = [];
          for (Map<String, dynamic> timeRangeJson in decodedResponse['time']) {
            newTimes.add(TimeRange(
                startTime: TimeOfDay(
                    hour: timeRangeJson['startHour'],
                    minute: timeRangeJson['startMinute']),
                endTime: TimeOfDay(
                    hour: timeRangeJson['endHour'],
                    minute: timeRangeJson['endMinute'])));
          }

          if (mounted) {
            ParentProvider.of(context).lichterkette.times = newTimes;
            ParentProvider.of(context).updateLichterkette();
            ParentProvider.of(context).refreshSwitchState();
          }
          if (response.statusCode != 200 && response.statusCode != 201) {
            throw BadRequest("Invalid parameters!");
          }
        }
      } on BadRequest {
        print("BAD REQUEST!");
        if (mounted) {
          final snackBar = SnackBar(
            content:
                const Text("At most 6 non-overlapping time intervals allowed!"),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                ParentProvider.of(context).refresh();
              },
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } catch (e) {
        print(e.toString());
        if (mounted) {
          final snackBar = SnackBar(
            content: const Text(
                "Failed to communicate to Lichterkette. Refreshing..."),
            action: SnackBarAction(
              label: 'Close',
              onPressed: () {},
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          ParentProvider.of(context).refresh();
        }
      } finally {
        setState(() {
          _waiting = false;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
        onPressed: !_waiting ? onPressed : null, child: const Icon(Icons.add));
  }
}

class RemoveTimeIntervalButton extends StatefulWidget {
  final TimeRange correspondingTimeRange;
  const RemoveTimeIntervalButton(
      {required this.correspondingTimeRange, super.key});

  @override
  State<RemoveTimeIntervalButton> createState() =>
      _RemoveTimeIntervalButtonState();
}

class _RemoveTimeIntervalButtonState extends State<RemoveTimeIntervalButton> {
  bool _waiting = false;

  void onPressed() {
    setState(() {
      _waiting = true;
    });

    () async {
      try {
        List<TimeRange> oldTimes = [
          ...ParentProvider.of(context).lichterkette.times
        ];

        oldTimes
            .removeWhere((element) => element == widget.correspondingTimeRange);

        /// @todo remove
        //oldTimes.add(selectedTimeRange);
        List<Map<String, int>> convTimes = [];
        for (TimeRange timeRange in oldTimes) {
          convTimes.add({
            'startHour': timeRange.startTime.hour,
            'startMinute': timeRange.startTime.minute,
            'endHour': timeRange.endTime.hour,
            'endMinute': timeRange.endTime.minute,
          });
        }

        var body = jsonEncode({'time': convTimes});
        print(body);

        final hostname = await getHostname();
        var response = await http
            .post(hostname.replace(path: '$Prefix/times'), body: body)
            .timeout(HttpTimeout);
        var decodedResponse = jsonDecode(response.body);

        List<TimeRange> newTimes = [];
        for (Map<String, dynamic> timeRangeJson in decodedResponse['time']) {
          newTimes.add(TimeRange(
              startTime: TimeOfDay(
                  hour: timeRangeJson['startHour'],
                  minute: timeRangeJson['startMinute']),
              endTime: TimeOfDay(
                  hour: timeRangeJson['endHour'],
                  minute: timeRangeJson['endMinute'])));
        }

        if (mounted) {
          ParentProvider.of(context).lichterkette.times = newTimes;
          ParentProvider.of(context).updateLichterkette();
          ParentProvider.of(context).refreshSwitchState();
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw BadRequest("Invalid parameters!");
        }
      } on BadRequest {
        print("BAD REQUEST!");
        if (mounted) {
          final snackBar = SnackBar(
            content:
                const Text("At most 6 non-overlapping time intervals allowed!"),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                ParentProvider.of(context).refresh();
              },
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } finally {
        setState(() {
          _waiting = false;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
        onPressed: !_waiting ? onPressed : null,
        icon: const Icon(
          Icons.remove_circle,
          color: Colors.red,
        ));
  }
}

class RoundSliderThumbShape extends SliderComponentShape {
  const RoundSliderThumbShape({
    required this.icon,
    this.enabledThumbRadius = 10.0,
    this.disabledThumbRadius = 10.0,
  });

  final IconData icon;
  final double enabledThumbRadius;
  final double disabledThumbRadius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(
        isEnabled == true ? enabledThumbRadius : disabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Tween<double> radiusTween = Tween<double>(
      begin: disabledThumbRadius,
      end: enabledThumbRadius,
    );
    final ColorTween colorTween = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    );
    canvas.drawCircle(
      center,
      radiusTween.evaluate(enableAnimation),
      Paint()..color = colorTween.evaluate(enableAnimation)!,
    );
    TextPainter textPainter = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(fontSize: 28.0, fontFamily: icon.fontFamily)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr);
    textPainter.layout();
    Offset textCenter = Offset(center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2));
    textPainter.paint(canvas, textCenter);
  }
}

class BrightnessSlider extends StatefulWidget {
  const BrightnessSlider({super.key});

  @override
  State<BrightnessSlider> createState() => _BrightnessSliderState();
}

class _BrightnessSliderState extends State<BrightnessSlider> {
  double? _currentSliderValue;
  bool _waiting = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: const RoundSliderThumbShape(
              icon: Icons.lightbulb_outline,
              enabledThumbRadius: 20.0,
              disabledThumbRadius: 20.0),
        ),
        child: Slider(
          value: _currentSliderValue ??
              ParentProvider.of(context).lichterkette.brightness.toDouble(),
          min: 0,
          max: ParentProvider.of(context).lichterkette.maxBrightness.toDouble(),
          onChanged: ParentProvider.of(context).lichterkette.on && !_waiting
              ? (double value) {
                  setState(() {
                    _currentSliderValue = value;
                  });
                }
              : null,
          onChangeEnd: (double value) {
            setState(() {
              _waiting = true;
            });
            var body = jsonEncode({'brightness': value.toInt()});
            () async {
              try {
                final hostname = await getHostname();
                var response = await http
                    .post(hostname.replace(path: '$Prefix/animation'),
                        body: body)
                    .timeout(HttpTimeout);

                var decodedResponse = jsonDecode(response.body);
                if (mounted) {
                  ParentProvider.of(context).lichterkette.brightness =
                      decodedResponse['brightness'];
                  ParentProvider.of(context).updateLichterkette();
                }
                if (response.statusCode != 200 && response.statusCode != 201) {
                  throw BadRequest("Invalid parameters!");
                }
              } on BadRequest {
                print("BAD REQUEST!");
                if (mounted) {
                  final snackBar = SnackBar(
                    content: const Text(
                        "An error occurred! Please try again or refresh."),
                    action: SnackBarAction(
                      label: 'Refresh',
                      onPressed: () {
                        ParentProvider.of(context).refresh();
                      },
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                }
              } catch (e) {
                print(e.toString());
                if (mounted) {
                  final snackBar = SnackBar(
                    content: const Text(
                        "Failed to communicate to Lichterkette. Refreshing..."),
                    action: SnackBarAction(
                      label: 'Close',
                      onPressed: () {},
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                  ParentProvider.of(context).refresh();
                }
              } finally {
                setState(() {
                  _currentSliderValue = null;
                  _waiting = false;
                });
              }
            }();
          },
        ),
      ),
    );
  }
}

class SpeedSlider extends StatefulWidget {
  const SpeedSlider({super.key});

  @override
  State<SpeedSlider> createState() => _SpeedSliderState();
}

class _SpeedSliderState extends State<SpeedSlider> {
  double? _currentSliderValue;
  bool _waiting = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(
                  icon: Icons.speed_outlined,
                  enabledThumbRadius: 20.0,
                  disabledThumbRadius: 20.0),
            ),
            child: Slider(
              value: _currentSliderValue ??
                  ParentProvider.of(context).lichterkette.speed.toDouble(),
              min: ParentProvider.of(context).lichterkette.minSpeed.toDouble(),
              max: ParentProvider.of(context).lichterkette.maxSpeed.toDouble(),
              onChanged: !_waiting &&
                      ParentProvider.of(context).lichterkette.on &&
                      ParentProvider.of(context)
                          .lichterkette
                          .currentAnimation()
                          .speed
                  ? (double value) {
                      setState(() {
                        _currentSliderValue = value;
                      });
                    }
                  : null,
              onChangeEnd: (double value) {
                setState(() {
                  _waiting = true;
                });
                var body = jsonEncode({'speed': value.toInt()});
                () async {
                  try {
                    final hostname = await getHostname();
                    var response = await http
                        .post(hostname.replace(path: '$Prefix/animation'),
                            body: body)
                        .timeout(HttpTimeout);
                    var decodedResponse = jsonDecode(response.body);

                    if (mounted) {
                      ParentProvider.of(context).lichterkette.speed =
                          decodedResponse['speed'];
                      ParentProvider.of(context).updateLichterkette();
                    }
                    if (response.statusCode != 200 &&
                        response.statusCode != 201) {
                      throw BadRequest("Invalid parameters!");
                    }
                  } on BadRequest {
                    print("BAD REQUEST!");
                    if (mounted) {
                      final snackBar = SnackBar(
                        content: const Text(
                            "An error occurred! Please try again or refresh."),
                        action: SnackBarAction(
                          label: 'Refresh',
                          onPressed: () {
                            ParentProvider.of(context).refresh();
                          },
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                    }
                  } catch (e) {
                    print(e.toString());
                    if (mounted) {
                      final snackBar = SnackBar(
                        content: const Text(
                            "Failed to communicate to Lichterkette. Refreshing..."),
                        action: SnackBarAction(
                          label: 'Close',
                          onPressed: () {},
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                      ParentProvider.of(context).refresh();
                    }
                  } finally {
                    setState(() {
                      _waiting = false;
                      _currentSliderValue = null;
                    });
                  }
                }();
              },
            )));
  }
}

class LightColorPicker extends StatefulWidget {
  const LightColorPicker({super.key});

  @override
  State<LightColorPicker> createState() => _LightColorPickerState();
}

class _LightColorPickerState extends State<LightColorPicker> {
  bool _waiting = false;

  void onColorChanged(Color color) {
    // Can happen if main windows refreshed in the mean time, simply ignore.
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    setState(() {
      _waiting = true;
    });
    var body = jsonEncode({
      'color': [color.red, color.green, color.blue]
    });
    () async {
      try {
        final hostname = await getHostname();
        var response = await http
            .post(hostname.replace(path: '$Prefix/animation'), body: body)
            .timeout(HttpTimeout);
        var decodedResponse = jsonDecode(response.body);
        if (mounted) {
          ParentProvider.of(context).lichterkette.color = Color.fromARGB(
              255,
              decodedResponse['color'][0],
              decodedResponse['color'][1],
              decodedResponse['color'][2]);
          ParentProvider.of(context).updateLichterkette();
        }
        if (response.statusCode != 200 && response.statusCode != 201) {
          throw BadRequest("Invalid parameters!");
        }
      } on BadRequest {
        print("BAD REQUEST!");
        if (mounted) {
          final snackBar = SnackBar(
            content:
                const Text("An error occurred! Please try again or refresh."),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () {
                ParentProvider.of(context).refresh();
              },
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } catch (e) {
        print(e.toString());
        if (mounted) {
          final snackBar = SnackBar(
            content: const Text(
                "Failed to communicate to Lichterkette. Refreshing..."),
            action: SnackBarAction(
              label: 'Close',
              onPressed: () {},
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } finally {
        setState(() {
          _waiting = false;
        });
      }
    }();
  }

  void onButtonPressed(Color color) {
    showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
              title: const Text('Pick a color!'),
              content: SingleChildScrollView(
                  child: BlockPicker(
                pickerColor: color,
                onColorChanged: onColorChanged,
                availableColors: const <Color>[
                  Colors.deepPurple,
                  Colors.purple,
                  Colors.pink,
                  Color.fromARGB(255, 255, 17, 0),
                  Colors.deepOrange,
                  Colors.orange,
                  Color.fromARGB(255, 0, 255, 8),
                  Color.fromARGB(255, 0, 146, 132),
                  Color.fromARGB(255, 0, 0, 255),
                  Color.fromARGB(255, 182, 252, 250),
                ],
              )),
              actions: <Widget>[
                ElevatedButton(
                  child: const Text('Close'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    Color color = ParentProvider.of(context).lichterkette.color;
    bool enabled = !_waiting &&
        ParentProvider.of(context).lichterkette.on &&
        ParentProvider.of(context).lichterkette.currentAnimation().color;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10),
        child: IconButton(
            icon: Icon(Icons.color_lens, color: enabled ? color : Colors.grey),
            iconSize: 55,
            //child: const Text("Select color"),
            onPressed: enabled ? () => onButtonPressed(color) : null));
  }
}

class AnimationRadioGroup extends StatefulWidget {
  const AnimationRadioGroup({super.key});

  @override
  State<AnimationRadioGroup> createState() => _AnimationRadioGroupState();
}

class _AnimationRadioGroupState extends State<AnimationRadioGroup>
    with SingleTickerProviderStateMixin {
  bool _waiting = false;
  // These are the displayed animation in the radio group(!)
  late Animation<int> displayAnimation;
  late AnimationController displayController;

  @override
  void initState() {
    super.initState();
    displayController =
        AnimationController(duration: const Duration(seconds: 5), vsync: this);
    displayAnimation = IntTween(begin: 0, end: 10).animate(displayController)
      ..addListener(() {
        setState(() {
          // The state that has changed here is the animation object’s value.
        });
      });
    // displayController.addListener(() async {
    //   if (displayController.isCompleted) {
    //     await Future.delayed(Duration(milliseconds: 250));
    //     //displayController.reverse();
    //     displayController.forward();
    //   } else if (displayController.isDismissed) {
    //     await Future.delayed(Duration(milliseconds: 250));
    //     displayController.forward();
    //   }
    // });
    // displayController.forward();
    displayController.repeat();
  }

  @override
  void dispose() {
    displayController.dispose();
    super.dispose();
  }

  void onChanged(int? value) {
    if (value != null) {
      setState(() {
        _waiting = true;
      });

      var body = jsonEncode({'animation': value});
      () async {
        try {
          final hostname = await getHostname();
          var response = await http
              .post(hostname.replace(path: '$Prefix/animation'), body: body)
              .timeout(HttpTimeout);
          var decodedResponse = jsonDecode(response.body);

          if (mounted) {
            ParentProvider.of(context).lichterkette.animationIdx =
                decodedResponse['animation'];
            ParentProvider.of(context).updateLichterkette();
          }
          if (response.statusCode != 200 && response.statusCode != 201) {
            throw BadRequest("Invalid parameters!");
          }
        } on BadRequest {
          print("BAD REQUEST!");
          if (mounted) {
            final snackBar = SnackBar(
              content:
                  const Text("An error occurred! Please try again or refresh."),
              action: SnackBarAction(
                label: 'Refresh',
                onPressed: () {
                  ParentProvider.of(context).refresh();
                },
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
          }
        } catch (e) {
          print(e.toString());
          if (mounted) {
            final snackBar = SnackBar(
              content: const Text(
                  "Failed to communicate to Lichterkette. Refreshing..."),
              action: SnackBarAction(
                label: 'Close',
                onPressed: () {},
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
            ParentProvider.of(context).refresh();
          }
        } finally {
          setState(() {
            _waiting = false;
          });
        }
      }();
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> options = [];

    for (LichterketteAnimation animation
        in ParentProvider.of(context).lichterkette.animations) {
      options.add(RadioListTile<int>(
        title: AnimatedDisplayText(
          animationName: animation.name,
          displayAnimation: displayAnimation,
        ),
        value: animation.idx,
        groupValue: ParentProvider.of(context).lichterkette.animationIdx,
        onChanged: !_waiting && ParentProvider.of(context).lichterkette.on
            ? onChanged
            : null,
      ));
    }

    return Column(children: options);
  }
}

class AnimatedDisplayText extends StatefulWidget {
  final Animation<int> displayAnimation;
  final String animationName;

  const AnimatedDisplayText(
      {required this.displayAnimation, required this.animationName, super.key});

  @override
  State<AnimatedDisplayText> createState() => _AnimatedDisplayTextState();
}

class _AnimatedDisplayTextState extends State<AnimatedDisplayText> {
  @override
  Widget build(BuildContext context) {
    final bool enabled = ParentProvider.of(context).lichterkette.on;
    const disabledIcon = Icon(Icons.lightbulb_outline, color: Colors.grey);
    List<Widget> children = [];
    if (widget.animationName == "constant") {
      for (int i = 0; i < 10; ++i) {
        if (enabled) {
          children.add(const Icon(Icons.lightbulb, color: Colors.amber));
        } else {
          children.add(disabledIcon);
        }
      }
    } else if (widget.animationName == "blinking") {
      const enabledIcon = Icon(Icons.lightbulb, color: Colors.amber);
      for (int i = 0; i < 10; ++i) {
        if (i % 2 == widget.displayAnimation.value % 2 && enabled) {
          children.add(enabledIcon);
        } else {
          children.add(disabledIcon);
        }
      }
    } else if (widget.animationName == "random-changing") {
      List<Icon> icons = [
        const Icon(Icons.lightbulb, color: Colors.red),
        const Icon(Icons.lightbulb, color: Colors.green),
        const Icon(Icons.lightbulb, color: Colors.blue),
      ];

      for (int i = 0; i < 10; ++i) {
        if (enabled) {
          int v = (4 * (i + 1) + 5 * (widget.displayAnimation.value + 1)) % 3;
          children.add(icons[v]);
        } else {
          children.add(disabledIcon);
        }
      }
    } else if (widget.animationName == "random-blinking") {
      List<Icon> icons = [
        const Icon(Icons.lightbulb, color: Colors.red),
        const Icon(Icons.lightbulb, color: Colors.green),
        const Icon(Icons.lightbulb, color: Colors.blue),
      ];

      for (int i = 0; i < 10; ++i) {
        if (i % 2 == widget.displayAnimation.value % 2 && enabled) {
          int v = (4 * (i + 1) + 5) % 3;
          children.add(icons[v]);
        } else {
          children.add(disabledIcon);
        }
      }
    } else if (widget.animationName == "running") {
      const enabledIcon = Icon(Icons.lightbulb, color: Colors.amber);
      for (int i = 0; i < 10; ++i) {
        if (i == widget.displayAnimation.value && enabled) {
          children.add(enabledIcon);
        } else {
          children.add(disabledIcon);
        }
      }
    }
    if (children.isNotEmpty) {
      return Row(children: children);
    }
    return Text("${widget.animationName}");
  }
}

class HostnameEdit extends StatefulWidget {
  const HostnameEdit({super.key});

  @override
  State<HostnameEdit> createState() => _HostnameEditState();
}

enum EditState { start, changed, waiting, reject, success }

class _HostnameEditState extends State<HostnameEdit> {
  final myController = TextEditingController();
  EditState _editState = EditState.start;

  @override
  void dispose() {
    // Clean up the controller when the widget is removed from the widget tree.
    // This also removes the _printLatestValue listener.
    myController.dispose();
    super.dispose();
  }

  void setToStoredValue() {
    // Retrieve the current value for the host name from the settings.
    () async {
      myController.text = (await getHostname()).host;
      setState(() {});
    }();
  }

  @override
  void initState() {
    super.initState();
    setToStoredValue();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: TextFormField(
          style: TextStyle(
              color: _editState == EditState.reject
                  ? Colors.redAccent
                  : (_editState == EditState.success ? Colors.green : null)),
          decoration: InputDecoration(
              border: UnderlineInputBorder(),
              labelText: "Enter a valid host name:",
              suffixIcon: _editState != EditState.start &&
                      _editState != EditState.success
                  ? IconButton(
                      icon: _editState != EditState.reject
                          ? (_editState == EditState.waiting
                              ? Icon(Icons.hourglass_bottom)
                              : Icon(Icons.check))
                          : Icon(Icons.undo),
                      onPressed: _editState == EditState.waiting ||
                              _editState == EditState.success
                          ? null
                          : () {
                              if (_editState == EditState.changed) {
                                setState(() => _editState = EditState.waiting);

                                () async {
                                  try {
                                    Uri hostname = Uri.http(myController.text);

                                    final response = await http
                                        .get(hostname.replace(
                                            path: '$Prefix/status'))
                                        .timeout(HttpTimeout);

                                    if (response.statusCode == 200) {
                                      Lichterkette.fromJson(
                                          jsonDecode(response.body));
                                      setState(
                                          () => _editState = EditState.success);
                                      SharedPreferences prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.setString(
                                          "hostname", hostname.host);
                                      if (mounted) {
                                        InitialParentProvider.of(context)
                                            .refresh();
                                      }
                                    } else {
                                      throw BadRequest(
                                          'Failed to load lichterkette');
                                    }
                                  } catch (e) {
                                    print(e.toString());
                                    setState(
                                        () => _editState = EditState.reject);
                                  }
                                }();
                              } else if (_editState == EditState.reject) {
                                setToStoredValue();
                                _editState = EditState.start;
                              }
                            },
                    )
                  : null),
          controller: myController,
          onChanged: (value) => setState(() => _editState = EditState.changed),
          readOnly: _editState == EditState.waiting,
        ));
  }
}

class VersionInfo extends StatefulWidget {
  const VersionInfo({super.key});

  @override
  State<VersionInfo> createState() => _VersionInfoState();
}

class _VersionInfoState extends State<VersionInfo> {
  late Future<String> _versionString;

  @override
  void initState() {
    super.initState();
    _versionString = () async {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      //String appName = packageInfo.appName;
      //String packageName = packageInfo.packageName;
      //String version = packageInfo.version;
      //String buildNumber = packageInfo.buildNumber;
      return "${packageInfo.version}+${packageInfo.buildNumber}";
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 50.0),
        child: FutureBuilder<String>(
            future: _versionString,
            builder: (context, snapshot) {
              String versionString = "????";
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData) {
                versionString = snapshot.data!;
              }
              const String urlString =
                  "https://github.com/flachsenberg/Lichterkette";
              return RichText(
                  text: TextSpan(
                children: [
                  TextSpan(
                    text: "Version: $versionString\n",
                    style: const TextStyle(color: Colors.black),
                  ),
                  const TextSpan(
                      text:
                          "Created by Florian Flachsenberg.\nOpen-source under MIT license, see:\n",
                      style: TextStyle(color: Colors.black)),
                  TextSpan(
                    text: urlString,
                    style: const TextStyle(color: Colors.blue),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        launchUrlString(
                            'https://github.com/flachsenberg/Lichterkette');
                      },
                  ),
                ],
              ));
            }));
  }
}
