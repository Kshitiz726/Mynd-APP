# Wiring the Community + Focus Rooms backend into the Flutter app

The UI currently uses hard-coded data + `Toast.show(...)` stubs. These services
replace those with the real cloud backend (`/server`). Nothing here changes the
look — only the data source.

## 1. One-time setup (after sign-in)
```dart
import 'core/services/api_config.dart';
import 'core/services/realtime_service.dart';

// After you obtain the Supabase (or custom) JWT + user id:
ApiConfig.instance
  ..authToken = jwt
  ..userId = userId;
RealtimeService.instance.connect();   // opens the shared Socket.IO connection
```
Set the server URL at build time (never localhost):
```
flutter run --dart-define=OURMYND_API=https://api.ourmynd.app
```

## 2. Community feed  (`community_screen.dart` → `_FeedTab`)
Replace the hard-coded `_PostCard(...)` list with:
```dart
final community = context.watch<CommunityProvider>();
// once: context.read<CommunityProvider>().loadFeed(refresh: true);
for (final post in community.posts)
  _PostCard.fromModel(post,
    onReact: (kind) => context.read<CommunityProvider>().toggleReaction(post.id, kind));
```
`_ReactButton` already toggles local `setState`; point its `onTap` at
`toggleReaction` so it persists + broadcasts. Counts reconcile via the
`reaction_update` socket event automatically.

## 3. Focus rooms  (`community_screen.dart` → `_RoomsTab`)
```dart
final fr = context.watch<FocusRoomProvider>();
// once: ApiClient.instance.fetchRooms().then((r) => fr.setRooms(r.rooms, r.globalLive));
// Hero "62 minds focusing": fr.globalLive
// Room tile "Join": fr.joinRoom(room.id);
```

## 4. Active focus room (presence grid + voice)
On `joinRoom` the provider already:
- subscribes to presence (`room_state`, `participant_joined/left/update`)
- requests a LiveKit token (`voice_join` → `voice_token`) and connects audio
- runs a smooth local 1s tick, corrected by the server `timer_tick` heartbeat

Wire the controls:
```dart
fr.setSession(task: "Finish quarterly report", mode: 'pomodoro', durationSecs: 25*60);
fr.timerControl('pause'); // 'resume' | 'end'
fr.toggleMute(true);      // mic badge + LiveKit track
fr.setTalking(true);      // push-to-talk (press) / false (release)
fr.raiseHand();           // "Need Help" state
fr.setAmbience('rain');   // silent | rain | cafe | library | typing
fr.leaveRoom();
```

## 5. Build the participant grid
```dart
for (final p in fr.participants)
  ParticipantTile(
    name: p.displayName, initial: p.initial,
    color: p.avatarColor,
    needsHelp: p.state == ParticipantState.needHelp,
    muted: p.micState == MicState.muted,
    dimmed: p.state == ParticipantState.inactive,   // greyed during grace period
    task: p.task,
    time: p.secondsRemaining,   // formatted mm:ss
  );
```
`p.userId == fr.myUserId` identifies the local user.
