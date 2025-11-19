import { SlashCommandBuilder, ChatInputCommandInteraction, PermissionFlagsBits } from 'discord.js';
import { Command } from '../types';

export const guildConfigCommand: Command = {
  data: new SlashCommandBuilder()
    .setName('config')
    .setDescription('Configure guild settings (Admin only)')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator)
    .addSubcommand((subcommand) =>
      subcommand.setName('view').setDescription('View current guild configuration'),
    )
    .addSubcommand((subcommand) =>
      subcommand
        .setName('set')
        .setDescription('Set a configuration option')
        .addStringOption((option) =>
          option.setName('key').setDescription('Configuration key').setRequired(true),
        )
        .addStringOption((option) =>
          option.setName('value').setDescription('Configuration value').setRequired(true),
        ),
    ),

  async execute(interaction: ChatInputCommandInteraction) {
    const subcommand = interaction.options.getSubcommand();
    const guildId = interaction.guildId;

    if (subcommand === 'view') {
      // TODO: Fetch guild config from database
      await interaction.reply({
        content: `⚙️ **Guild Configuration** (Guild ID: ${guildId})\n\nThis is a stub. Configuration will be fetched from the database.`,
        ephemeral: true,
      });
    } else if (subcommand === 'set') {
      const key = interaction.options.getString('key', true);
      const value = interaction.options.getString('value', true);

      // TODO: Update guild config in database with RBAC check
      await interaction.reply({
        content: `✅ Configuration updated: \`${key}\` = \`${value}\``,
        ephemeral: true,
      });
    }
  },
};
