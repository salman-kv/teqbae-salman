import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/models.dart';
import '../models/rules.dart';
import '../services/location_service.dart';
import 'theme.dart';
import 'widgets.dart';

/// The popups of the Profile tab. All of them are bottom sheets with the same
/// look: icon header, short explanation, content, one clear primary action.

Future<T?> _showSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => Padding(
      // Keep the content above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: builder(ctx),
      ),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.icon, required this.color, required this.title, required this.subtitle});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(icon, color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

/// Rounded box with a coloured message (info, warning, success).
class _Banner extends StatelessWidget {
  const _Banner(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
      );
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.label,
    required this.icon,
    this.suffix,
    this.error,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? suffix;
  final String? error;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            suffixText: suffix,
            prefixIcon: Icon(icon),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );
}

/// Selectable card (preset, theme).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = brandBlue,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null;
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(selected ? Icons.check_circle_rounded : icon, color: selected ? color : Theme.of(context).hintColor, size: 28),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: selected ? color : null)),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ office ----

Future<void> showOfficeSheet(BuildContext context) {
  final a = context.read<AttendanceController>();
  final s = context.read<SettingsController>();
  final current = a.office;
  final server = a.employee?.office;
  if (current == null || server == null) return Future.value();
  return _showSheet<void>(context, (_) => _OfficeSheet(settings: s, current: current, server: server));
}

class _OfficeSheet extends StatefulWidget {
  const _OfficeSheet({required this.settings, required this.current, required this.server});
  final SettingsController settings;
  final OfficeConfig current;
  final OfficeConfig server;

  @override
  State<_OfficeSheet> createState() => _OfficeSheetState();
}

class _OfficeSheetState extends State<_OfficeSheet> {
  late final _lat = TextEditingController(text: widget.current.latitude.toString());
  late final _lng = TextEditingController(text: widget.current.longitude.toString());
  late final _rad = TextEditingController(text: widget.current.radiusMeters.round().toString());
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _rad.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final la = double.tryParse(_lat.text.trim());
    final lo = double.tryParse(_lng.text.trim());
    final ra = double.tryParse(_rad.text.trim());
    final e = <String, String>{};
    if (la == null || la.abs() > 90) e['lat'] = 'Latitude must be a number between -90 and 90.';
    if (lo == null || lo.abs() > 180) e['lng'] = 'Longitude must be a number between -180 and 180.';
    if (ra == null || ra <= 0) e['rad'] = 'Radius must be more than 0 metres.';
    if (e.isNotEmpty) {
      setState(() => _errors = e);
      return;
    }
    await widget.settings.setOffice(la!, lo!, ra!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    await widget.settings.resetOffice();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sv = widget.server;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SheetHeader(
        icon: Icons.location_on_outlined,
        color: brandBlue,
        title: 'Office geofence',
        subtitle: 'Where punching is allowed. Saved on this phone only.',
      ),
      if (widget.settings.hasOfficeOverride) ...[
        const _Banner(Icons.edit_location_alt_outlined, warnAmber,
            'A custom office is active on this phone. Use Reset to go back to the server office.'),
        const SizedBox(height: 12),
      ],
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: brandBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_outlined, size: 20, color: brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Server office: ${sv.latitude}, ${sv.longitude} · ${sv.radiusMeters.round()} m',
              style: const TextStyle(color: brandBlue, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _NumField(controller: _lat, label: 'Latitude', icon: Icons.south_rounded, error: _errors['lat']),
      _NumField(controller: _lng, label: 'Longitude', icon: Icons.east_rounded, error: _errors['lng']),
      _NumField(
        controller: _rad,
        label: 'Allowed radius',
        icon: Icons.radar_rounded,
        suffix: 'm',
        error: _errors['rad'],
      ),
      Text(
        'The mock server checks its own office (mock_server/config.json). '
        'If it differs from this one, the server rejects the punch.',
        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5),
      ),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 58)),
            onPressed: _reset,
            child: const Text('Reset'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: GradientButton(label: 'Save', icon: Icons.check_rounded, onPressed: _save)),
      ]),
    ]);
  }
}

// ---------------------------------------------------------- location ----

Future<void> showLocationSheet(BuildContext context) {
  final a = context.read<AttendanceController>();
  final s = context.read<SettingsController>();
  return _showSheet<void>(context, (_) => _LocationSheet(settings: s, attendance: a, office: a.office));
}

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.settings, required this.attendance, required this.office});
  final SettingsController settings;
  final AttendanceController attendance;
  final OfficeConfig? office;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  late bool _enabled = widget.settings.gpsEnabled;
  late final _lat = TextEditingController(
      text: (widget.settings.gpsEnabled ? widget.settings.gpsLat : widget.office?.latitude ?? 0).toString());
  late final _lng = TextEditingController(
      text: (widget.settings.gpsEnabled ? widget.settings.gpsLng : widget.office?.longitude ?? 0).toString());
  Map<String, String> _errors = {};

  /// The phone's real GPS position (null while it is being read).
  LocationResult? _real;

  @override
  void initState() {
    super.initState();
    _readReal();
  }

  Future<void> _readReal() async {
    if (_real != null) setState(() => _real = null);
    final r = await widget.attendance.readRealLocation();
    if (mounted) setState(() => _real = r);
  }

  /// Copy the real position into the simulator fields and switch the simulator on.
  void _useReal(double lat, double lng) {
    setState(() {
      _lat.text = lat.toStringAsFixed(6);
      _lng.text = lng.toStringAsFixed(6);
      _enabled = true;
      _errors = {};
    });
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  double? get _la => double.tryParse(_lat.text.trim());
  double? get _lo => double.tryParse(_lng.text.trim());

  bool _near(double? a, double b) => a != null && (a - b).abs() < 1e-6;

  void _preset(double dLat) {
    final o = widget.office;
    if (o == null) return;
    setState(() {
      _lat.text = (o.latitude + dLat).toString();
      _lng.text = o.longitude.toString();
      _errors = {};
    });
  }

  Future<void> _save() async {
    final la = _la, lo = _lo;
    final e = <String, String>{};
    if (la == null || la.abs() > 90) e['lat'] = 'Latitude must be a number between -90 and 90.';
    if (lo == null || lo.abs() > 180) e['lng'] = 'Longitude must be a number between -180 and 180.';
    if (e.isNotEmpty) {
      setState(() => _errors = e);
      return;
    }
    await widget.settings.setMockGps(enabled: _enabled, lat: la!, lng: lo!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.office;
    final la = _la, lo = _lo;
    final atOffice = o != null && _near(la, o.latitude) && _near(lo, o.longitude);
    final oneKm = o != null && _near(la, o.latitude + 0.01) && _near(lo, o.longitude);

    Widget? distance;
    if (_enabled && o != null && la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) {
      final d = distanceMeters(la, lo, o.latitude, o.longitude);
      final inside = d <= o.radiusMeters;
      distance = _Banner(
        inside ? Icons.check_circle_outline : Icons.warning_amber_rounded,
        inside ? successGreen : dangerRed,
        '${d.round()} m from the office: ${inside ? 'inside' : 'outside'} the ${o.radiusMeters.round()} m radius, '
        'so punching ${inside ? 'is allowed' : 'will be blocked'}.',
      );
    } else if (!_enabled) {
      distance = const _Banner(Icons.my_location_rounded, brandBlue,
          'Mock GPS is off. The phone\'s real GPS is used when you punch.');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SheetHeader(
        icon: Icons.satellite_alt_outlined,
        color: Color(0xFF0E9AA7),
        title: 'Location simulator',
        subtitle: 'See where the phone is, or pretend to be somewhere else.',
      ),
      _RealLocationCard(
        result: _real,
        office: widget.office,
        mockOn: _enabled,
        onRefresh: _readReal,
        onUse: _useReal,
        onSettings: widget.attendance.openAppSettings,
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _enabled ? const Color(0xFF0E9AA7) : Theme.of(context).dividerColor),
          color: _enabled ? const Color(0xFF0E9AA7).withValues(alpha: 0.08) : null,
        ),
        child: SwitchListTile(
          title: const Text('Use mock GPS', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Punches use the position below instead of the real GPS.'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ),
      const SizedBox(height: 14),
      if (o != null)
        Row(children: [
          Expanded(
            child: _ChoiceCard(
              icon: Icons.apartment_rounded,
              label: 'At office',
              selected: atOffice,
              onTap: _enabled ? () => _preset(0) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ChoiceCard(
              icon: Icons.directions_walk_rounded,
              label: '~1 km away',
              selected: oneKm,
              color: dangerRed,
              onTap: _enabled ? () => _preset(0.01) : null,
            ),
          ),
        ]),
      const SizedBox(height: 16),
      _NumField(
          controller: _lat,
          label: 'Latitude',
          icon: Icons.south_rounded,
          enabled: _enabled,
          error: _errors['lat'],
          onChanged: (_) => setState(() => _errors = {})),
      _NumField(
          controller: _lng,
          label: 'Longitude',
          icon: Icons.east_rounded,
          enabled: _enabled,
          error: _errors['lng'],
          onChanged: (_) => setState(() => _errors = {})),
      ?distance,
      const SizedBox(height: 18),
      GradientButton(label: 'Save', icon: Icons.check_rounded, onPressed: _save),
    ]);
  }
}

/// Shows the phone's real GPS position (read once, not tracked) and how far it
/// is from the office, with a shortcut to copy it into the simulator.
class _RealLocationCard extends StatelessWidget {
  const _RealLocationCard({
    required this.result,
    required this.office,
    required this.mockOn,
    required this.onRefresh,
    required this.onUse,
    required this.onSettings,
  });
  final LocationResult? result; // null = still reading
  final OfficeConfig? office;
  final bool mockOn;
  final VoidCallback onRefresh;
  final void Function(double lat, double lng) onUse;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final hint = Theme.of(context).hintColor;

    Widget message(String text, String action, VoidCallback onTap) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w600)),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        );

    final Widget body;
    if (r == null) {
      body = const Row(children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
        SizedBox(width: 12),
        Text('Getting your location...'),
      ]);
    } else {
      body = switch (r) {
        LocationOk(:final latitude, :final longitude) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (office != null) ...[
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final d = distanceMeters(latitude, longitude, office!.latitude, office!.longitude);
                  final inside = d <= office!.radiusMeters;
                  return Text(
                    '${d.round()} m from the office (${inside ? 'inside' : 'outside'} the allowed area)',
                    style: TextStyle(
                        color: inside ? successGreen : dangerRed, fontWeight: FontWeight.w700, fontSize: 13),
                  );
                }),
              ],
              if (mockOn) ...[
                const SizedBox(height: 4),
                Text('Mock GPS is on: punches use the mock position below, not this one.',
                    style: TextStyle(color: hint, fontSize: 12.5)),
              ],
              TextButton.icon(
                onPressed: () => onUse(latitude, longitude),
                icon: const Icon(Icons.south_rounded, size: 18),
                label: const Text('Use as mock position'),
              ),
            ],
          ),
        LocationDenied() => message('Location permission was not allowed.', 'Try again', onRefresh),
        LocationDeniedForever() =>
          message('Location permission is permanently denied.', 'Open settings', onSettings),
        LocationServiceOff() => message('Location services are off. Turn on GPS.', 'Try again', onRefresh),
        LocationUnavailable() =>
          message('Could not get a position. Try again, ideally outdoors.', 'Try again', onRefresh),
      };
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: brandBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brandBlue.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.my_location_rounded, color: brandBlue, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Current location (real GPS)', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Refresh location',
            onPressed: r == null ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
        Padding(padding: const EdgeInsets.only(right: 6, bottom: 4), child: body),
      ]),
    );
  }
}

// ---------------------------------------------------------- scenario ----

const _scenarios = <({String key, String title, String hint, IconData icon, Color color})>[
  (
    key: 'normal',
    title: 'Normal (200 OK)',
    hint: 'Everything works.',
    icon: Icons.check_circle_outline,
    color: successGreen,
  ),
  (
    key: 'slow',
    title: 'Slow responses (3 s)',
    hint: 'Every call takes 3 seconds, then succeeds.',
    icon: Icons.hourglass_top_rounded,
    color: warnAmber,
  ),
  (
    key: 'timeout',
    title: 'Timeout (no answer, nothing saved)',
    hint: 'The server never answers. The punch stays pending.',
    icon: Icons.timer_off_outlined,
    color: dangerRed,
  ),
  (
    key: 'timeout_after_accept',
    title: 'Timeout after server saved the event',
    hint: 'The server saves it but the reply is lost. The retry must not duplicate it.',
    icon: Icons.sync_problem_outlined,
    color: Color(0xFF7A4DE8),
  ),
  (
    key: 'server_error',
    title: 'Server error (500)',
    hint: 'Every call fails. The quickest way to fake being offline.',
    icon: Icons.error_outline,
    color: dangerRed,
  ),
  (
    key: 'duplicate_conflict',
    title: 'Duplicate attendance (409)',
    hint: 'Punches are refused as "already exists".',
    icon: Icons.content_copy_rounded,
    color: warnAmber,
  ),
  (
    key: 'leave_reject',
    title: 'Leave validation rejection (422)',
    hint: 'Leave requests fail with a field error.',
    icon: Icons.event_busy_outlined,
    color: dangerRed,
  ),
];

Future<void> showScenarioSheet(BuildContext context) async {
  final s = context.read<SettingsController>();
  final picked = await _showSheet<({String name, bool once})>(
    context,
    (_) => _ScenarioSheet(current: s.scenario),
  );
  if (picked == null) return;
  final err = await s.setScenario(picked.name, once: picked.once && picked.name != 'normal');
  if (err != null && context.mounted) showMessage(context, err);
}

class _ScenarioSheet extends StatefulWidget {
  const _ScenarioSheet({required this.current});
  final String current;

  @override
  State<_ScenarioSheet> createState() => _ScenarioSheetState();
}

class _ScenarioSheetState extends State<_ScenarioSheet> {
  bool _once = false;

  bool _isCurrent(String key) => widget.current == key || widget.current.startsWith('$key (');

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SheetHeader(
        icon: Icons.api_rounded,
        color: Color(0xFF7A4DE8),
        title: 'Mock API scenario',
        subtitle: 'Changes how the mock server answers. Tap one to apply it.',
      ),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _once ? brandBlue : Theme.of(context).dividerColor),
          color: _once ? brandBlue.withValues(alpha: 0.08) : null,
        ),
        child: SwitchListTile(
          title: const Text('Only for the next request', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Then the server goes back to Normal.'),
          value: _once,
          onChanged: (v) => setState(() => _once = v),
        ),
      ),
      const SizedBox(height: 14),
      for (final sc in _scenarios) ...[
        _ScenarioTile(
          scenario: sc,
          selected: _isCurrent(sc.key),
          onTap: () => Navigator.pop(context, (name: sc.key, once: _once)),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({required this.scenario, required this.selected, required this.onTap});
  final ({String key, String title, String hint, IconData icon, Color color}) scenario;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = scenario.color;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c : Theme.of(context).dividerColor, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          IconTile(scenario.icon, c, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(scenario.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(scenario.hint, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5)),
            ]),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: c),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- theme ----

Future<void> showThemeSheet(BuildContext context) async {
  final s = context.read<SettingsController>();
  final picked = await _showSheet<ThemeMode>(context, (_) => _ThemeSheet(current: s.themeMode));
  if (picked != null) await s.setTheme(picked);
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.current});
  final ThemeMode current;

  @override
  Widget build(BuildContext context) {
    const items = [
      (ThemeMode.light, 'Light', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
      (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SheetHeader(
        icon: Icons.palette_outlined,
        color: Color(0xFF5B6B8C),
        title: 'Appearance',
        subtitle: 'Choose how the app looks. System follows your phone.',
      ),
      Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _ChoiceCard(
              icon: items[i].$3,
              label: items[i].$2,
              selected: current == items[i].$1,
              onTap: () => Navigator.pop(context, items[i].$1),
            ),
          ),
        ],
      ]),
    ]);
  }
}
