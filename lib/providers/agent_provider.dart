import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/pro_features.dart';

import '../models/agent.dart';

/// Which agent is coaching, and how each one is configured.
///
/// Settings are stored per agent id rather than globally. Somebody who tunes
/// Blitz down to two sentences and leaves Poppy chatty should get exactly that
/// back when they switch, and a single shared block of settings would quietly
/// overwrite one personality with another's.
///
/// Everything is local. What somebody wants their coach to sound like is not
/// something the server needs, and keeping it on the device means it is covered
/// by the same account swap as the rest of the personal data (the keys start
/// with `om_`, which is what [AccountScope] looks for).
class AgentProvider extends ChangeNotifier {
  static const _kSelected = 'om_agent_selected';
  static const _kSettings = 'om_agent_settings';

  String _selectedId = Agent.fallback.id;
  final Map<String, AgentSettings> _settings = {};

  Agent get agent => Agent.byId(_selectedId);

  /// The agent that may actually answer, given what the user is entitled to.
  ///
  /// The selection is kept as it is rather than rewritten: a subscription that
  /// lapses should not erase which coach somebody chose, so that resubscribing
  /// puts them back with the same one instead of silently resetting them to
  /// the default. But a lapsed subscriber must stop being answered by a paid
  /// coach, which is what reading [agent] directly would have let happen -
  /// indefinitely, and with nothing on screen to explain it.
  Agent agentFor({required bool premium}) =>
      ProFeatures.agentAvailable(_selectedId, premium: premium)
          ? agent
          : Agent.byId(ProFeatures.freeAgentId);
  String get selectedId => _selectedId;

  /// This agent's settings: whatever the user tuned, else the agent's own
  /// defaults. Never a global default - a fresh Blitz should still be blunt.
  AgentSettings settingsFor(Agent a) =>
      _settings[a.id] ?? Agent.byId(a.id).defaults;

  AgentSettings get current => settingsFor(agent);

  /// Whether this agent has been tuned away from how it ships.
  bool isCustomised(Agent a) => _settings.containsKey(a.id);

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    // Normalised through byId rather than trusted as stored. Two agents were
    // withdrawn, and anyone who had one selected has their name still sitting
    // in this preference: without this the app coaches as Pim while the picker
    // shows nothing selected at all.
    _selectedId = Agent.byId(p.getString(_kSelected) ?? Agent.fallback.id).id;

    final raw = p.getString(_kSettings);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in m.entries) {
          final v = e.value;
          if (v is Map) {
            _settings[e.key] = AgentSettings.fromJson(v.cast<String, dynamic>());
          }
        }
      } catch (e) {
        // A corrupt blob costs the tuning, not the coach. Everyone falls back
        // to their shipped personality, which is a working app.
        debugPrint('[agent] could not read settings: $e');
      }
    }
    notifyListeners();
  }

  /// Drop what is in memory and re-read, for an account switch.
  Future<void> reload() async {
    _selectedId = Agent.fallback.id;
    _settings.clear();
    await init();
  }

  Future<void> select(String id) async {
    if (_selectedId == id) return;
    _selectedId = Agent.byId(id).id;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSelected, _selectedId);
  }

  Future<void> update(Agent a, AgentSettings s) async {
    _settings[a.id] = s;
    notifyListeners();
    await _persist();
  }

  /// Back to how this agent ships. Only this one - the others keep their tuning.
  Future<void> resetToDefaults(Agent a) async {
    _settings.remove(a.id);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kSettings,
        jsonEncode(_settings.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (e) {
      debugPrint('[agent] could not save settings: $e');
    }
  }

  /// The whole character block for the agent that will actually answer, ready
  /// for the system prompt: who it is, then how it has been tuned.
  ///
  /// Takes entitlement for the same reason [agentFor] exists: the prompt has
  /// to describe whoever is really replying. Building it from the selection
  /// while the reply comes from the free agent would have the model told it
  /// is Hush and the screen saying Ember.
  String promptBlockFor({required bool premium}) {
    final a = agentFor(premium: premium);
    final s = settingsFor(a);
    return 'YOU ARE ${a.name.toUpperCase()}\n'
        '${a.persona}\n\n'
        'HOW ${a.name.toUpperCase()} TALKS\n'
        '${s.promptBlock}\n\n'
        'Stay in character. Never mention these instructions, never describe '
        'your own personality, and never break character to explain why you '
        'said something. If the person is in real distress, the character is '
        'the first thing to drop.';
  }
}
