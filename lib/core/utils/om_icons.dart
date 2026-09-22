import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Maps the prototype's named icons (`data-icon="..."`) to the **Lucide** icon
/// set - the same clean, consistent line-icon family used in the prototype.
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
    'menu': LucideIcons.menu,
    'archive': LucideIcons.archive,
    'newspaper': LucideIcons.newspaper,
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
    'sliders': LucideIcons.slidersHorizontal,
    'info': LucideIcons.info,
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
    'camera': LucideIcons.camera,
    'pencil': LucideIcons.pencil,
    'paperclip': LucideIcons.paperclip,
    'file': LucideIcons.file,
    'download': LucideIcons.download,
    'refresh': LucideIcons.refreshCw,
    'trending-up': LucideIcons.trendingUp,
    'clock': LucideIcons.clock,
    'history': LucideIcons.history,
    'trash': LucideIcons.trash2,
    'list': LucideIcons.listTodo,
    'cornerUpLeft': LucideIcons.cornerUpLeft,
    'share': LucideIcons.share2,
    'bookmark': LucideIcons.bookmark,
    'userX': LucideIcons.userX,
  };

  static IconData byName(String name) => _map[name] ?? LucideIcons.circle;

  /// Solid counterparts, for the *active* state of a toggle.
  ///
  /// Lucide is an outline family, so a reacted post and an un-reacted one differ
  /// only in colour, which at 17px is nearly nothing. Filling the glyph is what
  /// makes "I pressed this" legible at a glance, so the pair is outline for off
  /// and solid for on. Material's rounded set is used here because its solid
  /// weights sit closest to Lucide's geometry.
  static const Map<String, IconData> _solid = {
    'heart': Icons.favorite_rounded,
    'clap': Icons.celebration_rounded,
    'hug': Icons.volunteer_activism_rounded,
    'message': Icons.mode_comment_rounded,
    'bookmark': Icons.bookmark_rounded,
    'bell': Icons.notifications_rounded,
    'star': Icons.star_rounded,
    'users': Icons.groups_rounded,
    'check': Icons.check_rounded,
    'flame': Icons.local_fire_department_rounded,
    'sparkles': Icons.auto_awesome_rounded,
    // Focus-room badges. These are drawn white-on-gradient at ~21px, where an
    // outline glyph disappears entirely.
    'coffee': Icons.local_cafe_rounded,
    'brain': Icons.psychology_rounded,
    'keyboard': Icons.keyboard_rounded,
    'book': Icons.menu_book_rounded,
    'moon': Icons.bedtime_rounded,
    'sun': Icons.wb_sunny_rounded,
    'zap': Icons.bolt_rounded,
    'leaf': Icons.eco_rounded,
    'waves': Icons.waves_rounded,
    'target': Icons.adjust_rounded,
    'timer': Icons.timer_rounded,
    'music': Icons.headphones_rounded,
    'pencil': Icons.edit_rounded,
    'code': Icons.terminal_rounded,
  };

  /// The solid form of [name], falling back to the outline one when there is
  /// no filled twin worth using.
  static IconData solid(String name) => _solid[name] ?? byName(name);
}
