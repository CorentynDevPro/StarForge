import { Client, GatewayIntentBits, Events, Collection } from 'discord.js';
import pino from 'pino';
import { Command } from './types';
import { statsCommand } from './commands/stats';
import { guildConfigCommand } from './commands/guildConfig';
import { battleSimCommand } from './commands/battleSim';

const logger = pino({
  transport: {
    target: 'pino-pretty',
    options: {
      translateTime: 'HH:MM:ss Z',
      ignore: 'pid,hostname',
    },
  },
});

const DISCORD_TOKEN = process.env.DISCORD_TOKEN;

if (!DISCORD_TOKEN) {
  logger.error('DISCORD_TOKEN environment variable is required');
  process.exit(1);
}

// Create Discord client
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.GuildMembers,
  ],
});

// Command collection
const commands = new Collection<string, Command>();
commands.set('stats', statsCommand);
commands.set('config', guildConfigCommand);
commands.set('battle-sim', battleSimCommand);

// Ready event
client.once(Events.ClientReady, (readyClient) => {
  logger.info(`🤖 Bot logged in as ${readyClient.user.tag}!`);
  logger.info(`📊 Serving ${readyClient.guilds.cache.size} guilds`);
});

// Interaction handler
client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.isChatInputCommand()) return;

  const command = commands.get(interaction.commandName);

  if (!command) {
    logger.warn(`Unknown command: ${interaction.commandName}`);
    return;
  }

  try {
    await command.execute(interaction);
  } catch (error) {
    logger.error(error, 'Error executing command');
    const reply = {
      content: 'There was an error executing this command!',
      ephemeral: true,
    };

    if (interaction.replied || interaction.deferred) {
      await interaction.followUp(reply);
    } else {
      await interaction.reply(reply);
    }
  }
});

// Guild join event (multi-tenant setup)
client.on(Events.GuildCreate, async (guild) => {
  logger.info(`Joined new guild: ${guild.name} (${guild.id})`);
  // TODO: Initialize guild configuration in database
});

// Error handling
client.on(Events.Error, (error) => {
  logger.error(error, 'Discord client error');
});

process.on('unhandledRejection', (error) => {
  logger.error(error, 'Unhandled rejection');
});

// Login
client.login(DISCORD_TOKEN);

export { client, logger };
