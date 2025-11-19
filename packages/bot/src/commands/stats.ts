import { SlashCommandBuilder, ChatInputCommandInteraction } from 'discord.js';
import { Command } from '../types';

export const statsCommand: Command = {
  data: new SlashCommandBuilder()
    .setName('stats')
    .setDescription('View guild and player statistics'),
  
  async execute(interaction: ChatInputCommandInteraction) {
    const guildId = interaction.guildId;
    
    await interaction.reply({
      content: `📊 **Guild Statistics** (Guild ID: ${guildId})\n\nThis is a stub. Stats will be fetched from the database.`,
      ephemeral: true,
    });
  },
};
