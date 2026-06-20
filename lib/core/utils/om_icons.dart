import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Maps the prototype's named icons (`data-icon="..."`) to the **Lucide** icon
/// set — the same clean, consistent line-icon family used in the prototype.
///
/// Lucide is preferred over Material's built-ins because its 1.5px geometric
/// strokes read as calm and "designed" rather than utilitarian, which suits
/// OurMynd's soft aesthetic. Screens reference icons by their semantic name
/// (`OmIcons.energy(EnergyLevel.high)`, `OmIcons.byName('coffee')`) so the
/// underlying icon family can be swapped in this one file.
abstract final class OmIcons {
  static const Map<String, IconData> _map = {
    // Navigation.
    'home': LucideIcons.house,
    'timer': LucideIcons.timer,
    'users': LucideIcons.users,
    'bell': LucideIcons.bell,
    'message': LucideIcons.messageCircle,
    'user': LucideIcons.user,
    // Energy / vibe.
    'zap': LucideIcons.zap,
    'leaf': LucideIcons.leaf,
    'battery': LucideIcons.batteryLow,
    'brain': LucideIcons.brain,
    'waves': LucideIcons.waves,
    'target': LucideIcons.target,
    'sparkles': LucideIcons.sparkles,
    // Habits & routines.
    'coffee': LucideIcons.coffee,
    'book': LucideIcons.bookOpen,
    'keyboard': LucideIcons.keyboard,
    'droplet': LucideIcons.droplet,
    'activity': LucideIcons.activity,
    'spark': LucideIcons.sparkles,
    'seedling': LucideIcons.sprout,
    'wind': LucideIcons.wind,
    'sun': LucideIcons.sun,
    'pill': LucideIcons.pill,
    'bed': LucideIcons.bed,
    'flame': LucideIcons.flame,
    'moon': LucideIcons.moon,
    // Actions & controls.
    'check': LucideIcons.check,
    'checksq': LucideIcons.squareCheck,
    'plus': LucideIcons.plus,
    'plus-circle': LucideIcons.circlePlus,
    'search': LucideIcons.search,
    'star': LucideIcons.star,
    'heart': LucideIcons.heart,
    'mic': LucideIcons.mic,
    'mic-off': LucideIcons.micOff,
    'life-buoy': LucideIcons.lifeBuoy,
    'cloud-rain': LucideIcons.cloudRain,
    'edit': LucideIcons.squarePen,
    'file-text': LucideIcons.fileText,
    'alarm': LucideIcons.alarmClock,
    'hash': LucideIcons.hash,
    'barcode': LucideIcons.scanBarcode,
    'nfc': LucideIcons.nfc,
    'vibrate': LucideIcons.vibrate,
    'send': LucideIcons.send,
    'calendar': LucideIcons.calendarDays,
    'settings': LucideIcons.settings,
    'play': LucideIcons.play,
    'pause': LucideIcons.pause,
    // Chrome / community.
    'close': LucideIcons.x,
    'back': LucideIcons.arrowLeft,
    'chevL': LucideIcons.chevronLeft,
    'chevR': LucideIcons.chevronRight,
    'logout': LucideIcons.logOut,
    'buoy': LucideIcons.lifeBuoy,
    'clap': LucideIcons.partyPopper,
    'hug': LucideIcons.heartHandshake,
    'lock': LucideIcons.lock,
    'x': LucideIcons.x,
    'userPlus': LucideIcons.userPlus,
    'userCheck': LucideIcons.userCheck,
    'image': LucideIcons.image,
    'paperclip': LucideIcons.paperclip,
    'file': LucideIcons.file,
    'download': LucideIcons.download,
    'refresh': LucideIcons.refreshCw,
    'trending-up': LucideIcons.trendingUp,
    'clock': LucideIcons.clock,
    'list': LucideIcons.listTodo,
    'cornerUpLeft': LucideIcons.cornerUpLeft,
    'userX': LucideIcons.userX,
  };

  static IconData byName(String name) => _map[name] ?? LucideIcons.circle;
}
