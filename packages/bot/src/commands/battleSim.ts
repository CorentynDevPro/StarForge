import { SlashCommandBuilder, ChatInputCommandInteraction } from 'discord.js';
import { Command } from '../types';

export const battleSimCommand: Command = {
  data: new SlashCommandBuilder()
    .setName('battle-sim')
    .setDescription('Simulate a Gems of War battle')
    .addStringOption(option =>
      option
        .setName('team1')
        .setDescription('First team composition')
        .setRequired(true)
    )
    .addStringOption(option =>
      option
        .setName('team2')
        .setDescription('Second team composition')
        .setRequired(true)
    ),
  
  async execute(interaction: ChatInputCommandInteraction) {
    const team1 = interaction.options.getString('team1', true);
    const team2 = interaction.options.getString('team2', true);

    await interaction.deferReply();

    // TODO: Call battle-sim service
    setTimeout(async () => {
      await interaction.editReply({
        content: `⚔️ **Battle Simulation**\n\n**Team 1:** ${team1}\n**Team 2:** ${team2}\n\n**Result:** This is a stub. Battle simulation will be implemented.`,
      });
    }, 1000);
  },
};
