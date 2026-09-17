import { config } from '../config.js';

/**
 * The OurMynd Discord presence bot.
 *
 * It does nothing except stay connected. Discord's member list only places
 * ONLINE members into a hoisted role group, so a bot that is invited but never
 * runs falls into the Offline bucket at the bottom of the list. Holding an idle
 * gateway connection is what keeps the OurMynd name pinned to the top.
 *
 * Deliberately defensive, because this is cosmetic and the API server is not.
 * No token, a bad token, a missing dependency or a dropped connection must all
 * leave the rest of the process untouched: nothing here is awaited by startup
 * and nothing here is allowed to reject into the event loop.
 */
export async function startDiscordPresence(): Promise<void> {
  if (!config.hasDiscord) return;

  try {
    // Imported lazily so that a deploy without discord.js installed, or a build
    // that tree-shakes differently, cannot break `import`-time of the server.
    const { Client, ActivityType } = await import('discord.js');

    // No intents at all. The bot reads no messages and needs no privileged
    // gateway intents, which also means nothing to justify if Discord ever asks
    // what this application does with user data.
    const bot = new Client({ intents: [] });

    bot.once('clientReady', () => {
      console.log(`[discord] presence online as ${bot.user?.tag}`);
      bot.user?.setPresence({
        status: 'online',
        activities: [{ name: 'ourmynd.com', type: ActivityType.Watching }],
      });
    });

    // discord.js reconnects on its own; this is here so a silent drop shows up
    // in the Render logs rather than only as a bot that quietly went grey.
    bot.on('error', (err) => console.warn('[discord] client error:', err?.message ?? err));
    bot.on('shardDisconnect', () => console.warn('[discord] disconnected, will retry'));

    await bot.login(config.discordBotToken);
  } catch (err) {
    // An invalid token throws here. Log it and carry on: the member list
    // looking wrong is not a reason for the API to be down.
    console.warn(
      '[discord] presence bot failed to start, continuing without it:',
      (err as Error)?.message ?? err,
    );
  }
}
